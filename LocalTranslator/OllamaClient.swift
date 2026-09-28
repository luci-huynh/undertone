import Foundation

/// Sends one HTTP request. Separated so tests can use a mock. Nonisolated:
/// network I/O must not run on the main actor.
nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// The response head first, then body bytes in arbitrary chunks.
    func stream(_ request: URLRequest) -> AsyncThrowingStream<HTTPStreamPart, Error>
}

nonisolated enum HTTPStreamPart: Sendable {
    case response(HTTPURLResponse)
    case data(Data)
}

nonisolated enum OllamaError: Error, Equatable {
    /// Configured endpoint is not loopback HTTP.
    case endpointRejected
    /// Nothing answers on the endpoint (not installed, not running, stopped).
    case runtimeUnavailable
    case modelMissing(String)
    /// The tag runs on Ollama's servers; refused to keep text on this Mac.
    case cloudModelRejected(String)
    /// HTTP 200 whose body is not the expected JSON, or a non-HTTP answer.
    case invalidResponse
    case http(status: Int, message: String?)
    case emptyOutput
    /// A streamed line is not valid JSON.
    case malformedStream
    /// The stream ended before Ollama's `done` frame.
    case incompleteStream
    /// Ollama stopped because the context window was full (`done_reason` "length").
    case outputTruncated
    /// Not sent: prompt and expected output would not fit the context window.
    case inputTooLong
    /// No output before the first-token limit (model load) — `StreamWatchdog`.
    case coldStartTimeout
    /// Output started, then stopped for longer than the stall limit.
    case streamStalled
}

/// Ephemeral URLSession: no cache, cookies or credential storage, and every
/// redirect refused (Ollama never redirects; a redirect could leave the Mac).
nonisolated final class URLSessionTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private let session: URLSession

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.connectionProxyDictionary = [:]
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
        super.init()
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request, delegate: self)
        guard let http = response as? HTTPURLResponse else { throw OllamaError.invalidResponse }
        return (data, http)
    }

    func stream(_ request: URLRequest) -> AsyncThrowingStream<HTTPStreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request, delegate: self)
                    guard let http = response as? HTTPURLResponse else { throw OllamaError.invalidResponse }
                    continuation.yield(.response(http))
                    // Forward whatever has arrived at each newline (or every 4 KB);
                    // the parser does not rely on chunk boundaries.
                    var chunk = Data()
                    for try await byte in bytes {
                        chunk.append(byte)
                        if byte == 0x0A || chunk.count >= 4096 {
                            continuation.yield(.data(chunk))
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty { continuation.yield(.data(chunk)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // Completion-handler form: the async form crashes the Swift 6.4 compiler (SILGen)
    // under this target's default MainActor isolation.
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Minimal Ollama API client (PLAN F01, Milestone 4). Knows nothing about
/// which model to use or how to prompt it; that is configuration.
nonisolated struct OllamaClient: Sendable {
    let baseURL: URL
    private let transport: any HTTPTransport
    /// Readiness checks must answer fast; a missing runtime refuses at once.
    var checkTimeout: TimeInterval = 3
    /// First request after idle loads the model (~5 s for translategemma:12b).
    var generationTimeout: TimeInterval = 120

    init(baseURL: URL, transport: any HTTPTransport) throws {
        guard LocalEndpointPolicy.isAllowed(baseURL) else { throw OllamaError.endpointRejected }
        self.baseURL = baseURL
        self.transport = transport
    }

    func version() async throws -> String {
        let data = try await get("api/version")
        return try decode(Ollama.VersionResponse.self, from: data).version
    }

    func installedModels() async throws -> [Ollama.ModelEntry] {
        let data = try await get("api/tags")
        return try decode(Ollama.TagsResponse.self, from: data).models
    }

    /// Non-streaming chat; returns the assistant text.
    func chat(
        model: String, messages: [Ollama.ChatMessage], keepAlive: String? = nil, options: Ollama.ChatOptions? = nil
    ) async throws -> String {
        let request = try await makeChatRequest(model: model, messages: messages, stream: false, keepAlive: keepAlive, options: options)
        let data = try await perform(request, model: model)
        let response = try decode(Ollama.ChatResponse.self, from: data)
        if let error = response.error { throw OllamaError.http(status: 200, message: error) }
        guard let content = response.message?.content else { throw OllamaError.invalidResponse }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OllamaError.emptyOutput }
        if response.doneReason == "length" { throw OllamaError.outputTruncated }
        return content
    }

    /// Streaming chat: yields `message.content` deltas in order and finishes
    /// only after Ollama's `done` frame; a `done` for a full context window
    /// throws `outputTruncated` after the partial text. Cancelling the
    /// consumer cancels the HTTP request.
    func chatStream(
        model: String, messages: [Ollama.ChatMessage], keepAlive: String? = nil, options: Ollama.ChatOptions? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let transport = transport
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try await makeChatRequest(model: model, messages: messages, stream: true, keepAlive: keepAlive, options: options)
                    var parser = OllamaChatStreamParser()
                    var status: Int?
                    var errorBody = Data()
                    var doneReason: String?
                    func deliver(_ events: [OllamaStreamEvent]) {
                        for event in events {
                            switch event {
                            case .delta(let text): continuation.yield(text)
                            case .done(let reason): doneReason = reason
                            }
                        }
                    }
                    for try await part in transport.stream(request) {
                        switch part {
                        case .response(let response):
                            guard let url = response.url, LocalEndpointPolicy.isAllowed(url) else { throw OllamaError.endpointRejected }
                            status = response.statusCode
                        case .data(let bytes):
                            guard status == 200 else {
                                errorBody.append(bytes)
                                continue
                            }
                            deliver(try parser.consume(bytes))
                        }
                    }
                    guard let status else { throw OllamaError.invalidResponse }
                    guard status == 200 else { throw Self.error(status: status, body: errorBody, model: model) }
                    deliver(try parser.finish())
                    if doneReason == "length" { throw OllamaError.outputTruncated }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapTransportError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeChatRequest(
        model: String, messages: [Ollama.ChatMessage], stream: Bool, keepAlive: String?, options: Ollama.ChatOptions?
    ) async throws -> URLRequest {
        guard !ModelTag.isCloud(model) else { throw OllamaError.cloudModelRejected(model) }
        // Check fresh metadata for both chat paths: a saved alias can point to
        // a remote model even without a cloud suffix. Never send text if unknown.
        let matches = try await installedModels().filter { ModelTag.normalized($0.name) == ModelTag.normalized(model) }
        guard !matches.isEmpty else { throw OllamaError.modelMissing(model) }
        guard matches.allSatisfy(\.isLocal) else { throw OllamaError.cloudModelRejected(model) }
        try Task.checkCancellation()
        let body = Ollama.ChatRequest(model: model, messages: messages, stream: stream, keepAlive: keepAlive, options: options)
        var request = try makeRequest("api/chat", timeout: generationTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func error(status: Int, body: Data, model: String?) -> OllamaError {
        if status == 404, let model { return .modelMissing(model) }
        let message = try? JSONDecoder().decode(Ollama.ErrorResponse.self, from: body).error
        return .http(status: status, message: message)
    }

    private static func mapTransportError(_ error: Error) -> Error {
        switch error {
        case let error as OllamaError: error
        case let error as URLError where error.code == .cancelled: CancellationError()
        // URLSession's idle timeout (120 s) only backs up `StreamWatchdog`.
        case let error as URLError where error.code == .timedOut: OllamaError.streamStalled
        case is URLError: OllamaError.runtimeUnavailable
        default: error
        }
    }

    private func get(_ path: String) async throws -> Data {
        var request = try makeRequest(path, timeout: checkTimeout)
        request.httpMethod = "GET"
        return try await perform(request, model: nil)
    }

    private func makeRequest(_ path: String, timeout: TimeInterval) throws -> URLRequest {
        let url = baseURL.appending(path: path)
        guard LocalEndpointPolicy.isAllowed(url) else { throw OllamaError.endpointRejected }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpShouldHandleCookies = false
        return request
    }

    private func perform(_ request: URLRequest, model: String?) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw Self.mapTransportError(error)
        }
        // Defence in depth: the answer must come from the same local endpoint.
        guard let url = response.url, LocalEndpointPolicy.isAllowed(url) else { throw OllamaError.endpointRejected }
        if response.statusCode == 200 { return data }
        throw Self.error(status: response.statusCode, body: data, model: model)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw OllamaError.invalidResponse
        }
    }
}
