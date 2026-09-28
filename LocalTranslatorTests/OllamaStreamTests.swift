import Foundation
import Testing
@testable import Undertone

/// Real `/api/chat` stream shape (captured from Ollama 0.34.4 with a synthetic
/// sentence), with Vietnamese multi-byte characters in every delta.
private let fixture = """
{"model":"translategemma:12b","created_at":"2026-09-28T02:19:55.97128Z","message":{"role":"assistant","content":"Chào"},"done":false}
{"model":"translategemma:12b","created_at":"2026-09-28T02:19:56.030964Z","message":{"role":"assistant","content":" buổi"},"done":false}
{"model":"translategemma:12b","created_at":"2026-09-28T02:19:56.097115Z","message":{"role":"assistant","content":" sáng"},"done":false}
{"model":"translategemma:12b","created_at":"2026-09-28T02:19:56.163895Z","message":{"role":"assistant","content":" 👋."},"done":false}
{"model":"translategemma:12b","created_at":"2026-09-28T02:19:56.2321Z","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","total_duration":677495083,"eval_count":5}

"""

private let expected = "Chào buổi sáng 👋."

private func run(_ chunks: [Data]) throws -> (text: String, events: [OllamaStreamEvent]) {
    var parser = OllamaChatStreamParser()
    var events: [OllamaStreamEvent] = []
    for chunk in chunks { events += try parser.consume(chunk) }
    events += try parser.finish()
    let text = events.compactMap { if case .delta(let t) = $0 { t } else { nil } }.joined()
    return (text, events)
}

private func split(_ data: Data, every size: Int) -> [Data] {
    stride(from: 0, to: data.count, by: size).map { data.subdata(in: $0..<min($0 + size, data.count)) }
}

struct OllamaStreamParserTests {
    @Test func wholeStreamInOneChunk() throws {
        let result = try run([Data(fixture.utf8)])
        #expect(result.text == expected)
        #expect(result.events.last == .done(reason: "stop"))
        #expect(result.events.filter { if case .done = $0 { true } else { false } }.count == 1)
    }

    @Test func everyByteBoundaryKeepsVietnameseIntact() throws {
        let data = Data(fixture.utf8)
        // Split into two chunks at every possible offset, including inside
        // multi-byte characters (ào, ổ, á, 👋) and inside JSON.
        for offset in 1..<data.count {
            let result = try run([data.prefix(offset), data.suffix(from: offset)])
            #expect(result.text == expected, "split at \(offset)")
        }
    }

    @Test func tinyAndIrregularChunks() throws {
        let data = Data(fixture.utf8)
        for size in [1, 2, 3, 5, 7, 64] {
            #expect(try run(split(data, every: size)).text == expected, "chunk size \(size)")
        }
    }

    @Test func blankLinesAndCRLFAreIgnored() throws {
        let crlf = fixture.replacingOccurrences(of: "\n", with: "\r\n\r\n  \r\n")
        #expect(try run([Data(crlf.utf8)]).text == expected)
    }

    @Test func finalLineWithoutNewlineStillCompletes() throws {
        let trimmed = fixture.trimmingCharacters(in: .newlines)
        #expect(try run([Data(trimmed.utf8)]).text == expected)
    }

    @Test func endOfStreamBeforeDoneIsNotSuccess() {
        let partial = fixture.split(separator: "\n").prefix(3).joined(separator: "\n") + "\n"
        #expect(throws: OllamaError.incompleteStream) { try run([Data(partial.utf8)]) }
        #expect(throws: OllamaError.incompleteStream) { try run([]) }
        // Cut in the middle of the last frame.
        let data = Data(fixture.utf8)
        #expect(throws: OllamaError.malformedStream) { try run([data.prefix(data.count - 40)]) }
    }

    @Test func errorFrameIsReported() {
        let stream = #"{"message":{"role":"assistant","content":"Chào"},"done":false}"# + "\n" + #"{"error":"model runner has unexpectedly stopped"}"# + "\n"
        #expect(throws: OllamaError.http(status: 200, message: "model runner has unexpectedly stopped")) { try run([Data(stream.utf8)]) }
    }

    @Test func invalidUTF8InALineIsMalformed() {
        var bytes = Data(#"{"message":{"role":"assistant","content":""#.utf8)
        bytes.append(contentsOf: [0xC3, 0x28]) // invalid 2-byte sequence
        bytes.append(Data(#""},"done":false}"#.utf8) + Data("\n".utf8))
        var parser = OllamaChatStreamParser()
        #expect(throws: OllamaError.malformedStream) { try parser.consume(bytes) }
    }

    @Test func malformedJSONIsReported() {
        #expect(throws: OllamaError.malformedStream) { try run([Data("{not json}\n".utf8)]) }
    }

    @Test func thinkingAndToolPayloadsAreNotOutput() throws {
        let stream = """
        {"message":{"role":"assistant","content":"","thinking":"Let me think about the user"},"done":false}
        {"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"x","arguments":{}}}]},"done":false}
        {"message":{"role":"assistant","content":"Xin chào"},"done":false}
        {"message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}

        """
        #expect(try run([Data(stream.utf8)]).text == "Xin chào")
    }

    @Test func textInTheDoneFrameIsKeptAndLaterFramesIgnored() throws {
        let stream = """
        {"message":{"role":"assistant","content":"Xin"},"done":false}
        {"message":{"role":"assistant","content":" chào"},"done":true,"done_reason":"stop"}
        {"message":{"role":"assistant","content":" EXTRA"},"done":false}

        """
        let result = try run([Data(stream.utf8)])
        #expect(result.text == "Xin chào")
        #expect(result.events.last == .done(reason: "stop"))
    }
}

struct OllamaChatStreamClientTests {
    private let base = LocalEndpointPolicy.defaultBaseURL
    private let messages = [Ollama.ChatMessage(role: "user", content: "prompt")]

    private func streamingTransport(body: String, status: Int = 200, chunk: Int = 3) -> MockTransport {
        let transport = MockTransport { request in
            if request.url?.path == "/api/tags" {
                return (200, Data(#"{"models":[{"name":"translategemma:12b"},{"name":"nope:1b"}]}"#.utf8), nil)
            }
            return (status, Data(body.utf8), nil)
        }
        transport.chunking = { split($0, every: chunk) }
        return transport
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var deltas: [String] = []
        for try await delta in stream { deltas.append(delta) }
        return deltas
    }

    @Test func yieldsDeltasInOrderAndSendsStreamingRequest() async throws {
        let transport = streamingTransport(body: fixture)
        let client = try OllamaClient(baseURL: base, transport: transport)
        let deltas = try await collect(client.chatStream(model: "translategemma:12b", messages: messages, keepAlive: "30m"))
        #expect(deltas == ["Chào", " buổi", " sáng", " 👋."])
        let body = try JSONSerialization.jsonObject(with: transport.requests.last?.httpBody ?? Data()) as? [String: Any]
        #expect(body?["stream"] as? Bool == true)
        #expect(body?["keep_alive"] as? String == "30m")
    }

    @Test func missingModelBeforeStreamStarts() async throws {
        let transport = streamingTransport(body: #"{"error":"model 'nope:1b' not found"}"#, status: 404)
        let client = try OllamaClient(baseURL: base, transport: transport)
        await #expect(throws: OllamaError.modelMissing("nope:1b")) {
            _ = try await collect(client.chatStream(model: "nope:1b", messages: messages))
        }
    }

    @Test func connectionRefusedIsRuntimeUnavailable() async throws {
        let client = try OllamaClient(baseURL: base, transport: MockTransport.refusing())
        await #expect(throws: OllamaError.runtimeUnavailable) {
            _ = try await collect(client.chatStream(model: "translategemma:12b", messages: messages))
        }
    }

    @Test func prematureEndIsAnErrorAfterPartialOutput() async throws {
        let partial = fixture.split(separator: "\n").prefix(2).joined(separator: "\n") + "\n"
        let client = try OllamaClient(baseURL: base, transport: streamingTransport(body: partial))
        var received: [String] = []
        await #expect(throws: OllamaError.incompleteStream) {
            for try await delta in client.chatStream(model: "translategemma:12b", messages: messages) { received.append(delta) }
        }
        #expect(received == ["Chào", " buổi"])
    }

    @Test func fullContextIsReportedAfterPartialOutput() async throws {
        let truncated = fixture.split(separator: "\n").prefix(2).joined(separator: "\n")
            + "\n" + #"{"message":{"role":"assistant","content":""},"done":true,"done_reason":"length"}"# + "\n"
        let client = try OllamaClient(baseURL: base, transport: streamingTransport(body: truncated))
        var received: [String] = []
        await #expect(throws: OllamaError.outputTruncated) {
            for try await delta in client.chatStream(model: "translategemma:12b", messages: messages) { received.append(delta) }
        }
        #expect(received == ["Chào", " buổi"])
    }

    @Test func contextOptionIsSentOnlyWhenGiven() async throws {
        let transport = streamingTransport(body: fixture)
        let client = try OllamaClient(baseURL: base, transport: transport)
        _ = try await collect(client.chatStream(model: "translategemma:12b", messages: messages, options: Ollama.ChatOptions(numCtx: 4096)))
        _ = try await collect(client.chatStream(model: "translategemma:12b", messages: messages))
        let bodies = try transport.requests.filter { $0.url?.path == "/api/chat" }
            .map { try JSONSerialization.jsonObject(with: $0.httpBody ?? Data()) as? [String: Any] }
        #expect((bodies[0]?["options"] as? [String: Any])?["num_ctx"] as? Int == 4096)
        #expect(bodies[1]?["options"] == nil)
    }

    @Test func redirectStatusIsAnErrorWithoutOutput() async throws {
        let client = try OllamaClient(baseURL: base, transport: streamingTransport(body: fixture, status: 302))
        var received: [String] = []
        await #expect(throws: OllamaError.http(status: 302, message: nil)) {
            for try await delta in client.chatStream(model: "translategemma:12b", messages: messages) { received.append(delta) }
        }
        #expect(received.isEmpty)
    }

    @Test func cloudModelSendsNothing() async throws {
        let transport = streamingTransport(body: fixture)
        let client = try OllamaClient(baseURL: base, transport: transport)
        await #expect(throws: OllamaError.cloudModelRejected("gpt-oss:20b-cloud")) {
            _ = try await collect(client.chatStream(model: "gpt-oss:20b-cloud", messages: messages))
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func foreignResponseURLIsRejected() async throws {
        let transport = MockTransport { _ in (200, Data(fixture.utf8), URL(string: "http://example.com/api/chat")) }
        let client = try OllamaClient(baseURL: base, transport: transport)
        await #expect(throws: OllamaError.endpointRejected) {
            _ = try await collect(client.chatStream(model: "translategemma:12b", messages: messages))
        }
    }

    @Test func consumerCancellationStopsTheStream() async throws {
        let transport = SlowStreamTransport()
        let client = try OllamaClient(baseURL: base, transport: transport)
        let consumer = Task {
            var count = 0
            for try await _ in client.chatStream(model: "translategemma:12b", messages: messages) {
                count += 1
                if count == 2 { break }
            }
            return count
        }
        #expect(try await consumer.value == 2)
        try await Task.sleep(for: .milliseconds(200))
        #expect(transport.wasCancelled)
        #expect(transport.framesSent < 50)
    }
}

/// Sends one frame every 10 ms, up to 100, and records cancellation.
private final class SlowStreamTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var sent = 0
    var wasCancelled: Bool { lock.withLock { cancelled } }
    var framesSent: Int { lock.withLock { sent } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(#"{"models":[{"name":"translategemma:12b"}]}"#.utf8),
         HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func stream(_ request: URLRequest) -> AsyncThrowingStream<HTTPStreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.response(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
                do {
                    for _ in 0..<100 {
                        try await Task.sleep(for: .milliseconds(10))
                        self.lock.withLock { self.sent += 1 }
                        continuation.yield(.data(Data(#"{"message":{"role":"assistant","content":"x"},"done":false}"#.utf8 + [0x0A])))
                    }
                    continuation.finish()
                } catch {
                    self.lock.withLock { self.cancelled = true }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Live streaming smoke against local Ollama (synthetic sentence); runs only
/// with TEST_RUNNER_LT_LIVE_OLLAMA=1.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LT_LIVE_OLLAMA"] == "1"))
struct OllamaLiveStreamTests {
    @Test func realStreamGrowsAndEnds() async throws {
        let client = try OllamaClient(baseURL: LocalEndpointPolicy.defaultBaseURL, transport: URLSessionTransport())
        let config = TranslationModelConfiguration(tag: nil)
        var deltas: [String] = []
        let started = Date()
        var firstDelta: TimeInterval?
        for try await delta in client.chatStream(
            model: config.tag,
            messages: config.messages(translating: "The payment has been processed and the receipt was sent to your email.", direction: .englishToVietnamese),
            keepAlive: "30m"
        ) {
            if firstDelta == nil { firstDelta = Date().timeIntervalSince(started) }
            deltas.append(delta)
        }
        let text = deltas.joined()
        print("LIVE STREAM: \(deltas.count) deltas, first after \(String(format: "%.2f", firstDelta ?? -1)) s, total \(String(format: "%.2f", Date().timeIntervalSince(started))) s: \(text)")
        #expect(deltas.count > 3)
        #expect(!text.isEmpty)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["LT_LIVE_OLLAMA"] == "1"))
struct OllamaLiveCancelTests {
    /// Stops reading after three deltas; Ollama's server log then shows the
    /// request ending early with a cancelled task (checked in PROGRESS S20).
    @Test func cancellingMidStreamClosesTheConnection() async throws {
        let client = try OllamaClient(baseURL: LocalEndpointPolicy.defaultBaseURL, transport: URLSessionTransport())
        let config = TranslationModelConfiguration(tag: nil)
        let paragraph = String(repeating: "The quarterly report shows steady growth across every region, and the team plans to expand next year. ", count: 12)
        var count = 0
        let started = Date()
        for try await _ in client.chatStream(model: config.tag, messages: config.messages(translating: paragraph, direction: .englishToVietnamese), keepAlive: "30m") {
            count += 1
            if count == 3 { break }
        }
        print("LIVE CANCEL: stopped after \(count) deltas at \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
        try await Task.sleep(for: .seconds(1))
        #expect(count == 3)
    }
}
