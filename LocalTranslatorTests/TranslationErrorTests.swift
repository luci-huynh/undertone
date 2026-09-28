import Foundation
import Testing
@testable import Undertone

/// Failure injection for S23: every error maps to one short message and a
/// recovery; timeouts are separated; cancellation is never an error.
struct TranslationErrorTests {
    @Test(arguments: [
        (OllamaError.runtimeUnavailable as Error, TranslationError.runtimeUnavailable),
        (OllamaError.modelMissing("x:1b"), .modelMissing),
        (OllamaError.coldStartTimeout, .coldStartTimeout),
        (OllamaError.streamStalled, .stalled),
        (OllamaError.malformedStream, .malformedResponse),
        (OllamaError.invalidResponse, .malformedResponse),
        (OllamaError.incompleteStream, .interrupted),
        (CancellationError(), .interrupted),
        (OllamaError.http(status: 500, message: "model requires more system memory"), .ollama(message: "model requires more system memory")),
        (OllamaError.emptyOutput, .emptyOutput),
        (OllamaError.inputTooLong, .inputTooLong),
        (OllamaError.outputTruncated, .outputTruncated),
        (OllamaError.endpointRejected, .notLocal),
        (OllamaError.cloudModelRejected("x:cloud"), .notLocal),
        (URLError(.badURL), .unavailable),
    ])
    func everyErrorIsNormalised(_ error: Error, _ expected: TranslationError) {
        #expect(TranslationError(error) == expected)
    }

    @Test func planMessagesAndRecovery() {
        #expect(TranslationError.runtimeUnavailable.message == "Ollama is not running.")
        #expect(TranslationError.runtimeUnavailable.allowsRetry)
        #expect(TranslationError.modelMissing.message == "Translation model is not installed.")
        #expect(!TranslationError.modelMissing.allowsRetry)
        // The same request would fail the same way.
        #expect(!TranslationError.inputTooLong.allowsRetry)
        #expect(!TranslationError.outputTruncated.allowsRetry)
        #expect(!TranslationError.notLocal.allowsRetry)
        #expect(TranslationError.coldStartTimeout.allowsRetry && TranslationError.stalled.allowsRetry)
        #expect(TranslationError.coldStartTimeout.message != TranslationError.stalled.message)
    }

    @Test func aRequestOllamaRejectedOffersNoRetry() {
        #expect(!TranslationError(OllamaError.http(status: 400, message: "\"nomic-embed-text\" does not support chat")).allowsRetry)
        #expect(TranslationError(OllamaError.http(status: 400, message: "bad")).message == "Ollama: bad")
        #expect(TranslationError(OllamaError.http(status: 500, message: nil)).allowsRetry)
        #expect(TranslationError(OllamaError.http(status: 429, message: nil)).allowsRetry)
    }

    @Test func ollamaMessageIsShortSingleLineAndNeverLogged() {
        let long = String(repeating: "x", count: 300) + "\nsecond line"
        let message = TranslationError.ollama(message: long).message
        #expect(message.hasPrefix("Ollama: "))
        #expect(message.count <= 128)
        #expect(!message.contains("second line"))
        #expect(TranslationError.ollama(message: nil).message == "Ollama reported an error.")
        #expect(TranslationError.ollama(message: "secret detail").logLabel == "ollamaError")
    }
}

/// Timing tests use short limits; the product limits are fixed constants.
struct StreamWatchdogTests {
    private func collect(_ stream: AsyncThrowingStream<String, Error>) async -> (output: [String], error: Error?) {
        var output: [String] = []
        do {
            for try await element in stream { output.append(element) }
            return (output, nil)
        } catch {
            return (output, error)
        }
    }

    @Test func productLimitsFollowMeasurements() {
        #expect(StreamWatchdog.firstTokenLimit == .seconds(60))
        #expect(StreamWatchdog.stallLimit == .seconds(15))
    }

    @Test func passesThroughAndFinishes() async {
        let (upstream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        continuation.yield("a")
        continuation.yield("b")
        continuation.finish()
        let result = await collect(StreamWatchdog.watch(upstream, first: .seconds(5), between: .seconds(5)))
        #expect(result.output == ["a", "b"])
        #expect(result.error == nil)
    }

    @Test func nothingBeforeTheFirstLimitIsAColdStartTimeoutAndCancelsUpstream() async {
        let (upstream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let log = TerminationLog()
        continuation.onTermination = { termination in
            if case .cancelled = termination { log.append(1) }
        }
        let result = await collect(StreamWatchdog.watch(upstream, first: .milliseconds(80), between: .seconds(5)))
        #expect(result.error as? OllamaError == .coldStartTimeout)
        for _ in 0..<100 where log.values.isEmpty { await Task.yield() }
        #expect(log.values == [1])
    }

    @Test func aGapAfterOutputIsAStallAndKeepsEarlierOutput() async {
        let (upstream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        continuation.yield("Xin ")
        let result = await collect(StreamWatchdog.watch(upstream, first: .seconds(5), between: .milliseconds(80)))
        #expect(result.output == ["Xin "])
        #expect(result.error as? OllamaError == .streamStalled)
    }

    @Test func steadyOutputLongerThanTheStallLimitIsFine() async {
        let (upstream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let producer = Task {
            for index in 0..<8 {
                try? await Task.sleep(for: .milliseconds(30))
                continuation.yield("\(index)")
            }
            continuation.finish()
        }
        // 8 × 30 ms = 240 ms total, every gap well under 150 ms.
        let result = await collect(StreamWatchdog.watch(upstream, first: .milliseconds(150), between: .milliseconds(150)))
        await producer.value
        #expect(result.output.count == 8)
        #expect(result.error == nil)
    }

    @Test func firstTokenShortensDeadlineAndTimeoutNeverCompletesSuccessfully() async {
        // Repeat the cancellation race; the first deadline is intentionally
        // much longer than the stall deadline, unlike the older timing tests.
        for _ in 0..<5 {
            let (upstream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
            let log = TerminationLog()
            continuation.onTermination = { termination in
                if case .cancelled = termination { log.append(1) }
            }
            let start = ContinuousClock.now
            let watched = StreamWatchdog.watch(upstream, first: .seconds(2), between: .milliseconds(80))
            let producer = Task {
                try? await Task.sleep(for: .milliseconds(50))
                continuation.yield("partial")
            }
            let result = await collect(watched)
            await producer.value
            #expect(result.output == ["partial"])
            #expect(result.error as? OllamaError == .streamStalled)
            #expect(ContinuousClock.now - start < .seconds(1))
            for _ in 0..<200 where log.values.isEmpty { await Task.yield() }
            #expect(log.values == [1])
        }
    }

    @Test func upstreamErrorsPassThrough() async {
        let (upstream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        continuation.yield("a")
        continuation.finish(throwing: OllamaError.runtimeUnavailable)
        let result = await collect(StreamWatchdog.watch(upstream, first: .seconds(5), between: .seconds(5)))
        #expect(result.output == ["a"])
        #expect(result.error as? OllamaError == .runtimeUnavailable)
    }
}

/// Sends the response head and then nothing, like a model that never loads.
private final class SilentTransport: HTTPTransport, @unchecked Sendable {
    let terminations = TerminationLog()

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        switch request.url?.path {
        case "/api/version": return (Data(#"{"version":"0.34.4"}"#.utf8), response)
        default: return (Data(#"{"models":[{"name":"translategemma:12b"}]}"#.utf8), response)
        }
    }

    func stream(_ request: URLRequest) -> AsyncThrowingStream<HTTPStreamPart, Error> {
        let (stream, continuation) = AsyncThrowingStream<HTTPStreamPart, Error>.makeStream()
        continuation.yield(.response(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!))
        let log = terminations
        continuation.onTermination = { termination in
            if case .cancelled = termination { log.append(1) }
        }
        return stream
    }
}

@MainActor
struct TranslationTimeoutServiceTests {
    @Test func slowModelStartTimesOutAndCancelsTheRequest() async {
        let transport = SilentTransport()
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: transport)
        var service = OllamaTranslationService(readiness: readiness)
        service.firstTokenLimit = .milliseconds(80)
        await #expect(throws: OllamaError.coldStartTimeout) {
            for try await _ in service.translate("Hello", direction: .englishToVietnamese) {}
        }
        for _ in 0..<200 where transport.terminations.values.isEmpty { await Task.yield() }
        #expect(transport.terminations.values == [1])
    }
}

struct ClientTimeoutMappingTests {
    @Test func urlSessionIdleTimeoutIsAStallNotAStoppedOllama() async throws {
        let transport = MockTransport { _ in throw URLError(.timedOut) }
        let client = try OllamaClient(baseURL: LocalEndpointPolicy.defaultBaseURL, transport: transport)
        await #expect(throws: OllamaError.streamStalled) {
            for try await _ in client.chatStream(model: "translategemma:12b", messages: [.init(role: "user", content: "p")]) {}
        }
    }
}
