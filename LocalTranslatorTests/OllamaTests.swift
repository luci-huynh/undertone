import Foundation
import Testing
@testable import LocalTranslator

struct LocalEndpointPolicyTests {
    @Test func acceptsOnlyPlainHTTPLoopback() {
        for string in ["http://127.0.0.1:11434", "http://localhost:11434", "http://[::1]:11434", "http://LOCALHOST:8080/"] {
            #expect(LocalEndpointPolicy.isAllowed(URL(string: string)!), "\(string)")
        }
        for string in [
            "https://127.0.0.1:11434", "http://192.168.1.10:11434", "http://example.com:11434",
            "http://127.0.0.1.example.com:11434", "http://localhost.evil.com", "http://user:pw@127.0.0.1:11434",
            "http://0.0.0.0:11434", "file:///tmp/x", "ftp://127.0.0.1",
            // S26: user-info and alternative spellings that could reach another host.
            "http://127.0.0.1@evil.example.com", "http://localhost:11434@evil.example.com",
            "http://[::ffff:127.0.0.1]:11434", "http://127.1:11434", "http://2130706433:11434",
            "http://127.0.0.1%2eevil.example.com", "//127.0.0.1:11434",
        ] {
            #expect(!LocalEndpointPolicy.isAllowed(URL(string: string)!), "\(string)")
        }
    }

    @Test func configuredBaseURLFallsBackToDefaultOrIsRejected() {
        #expect(LocalEndpointPolicy.baseURL(from: nil) == LocalEndpointPolicy.defaultBaseURL)
        #expect(LocalEndpointPolicy.baseURL(from: "") == LocalEndpointPolicy.defaultBaseURL)
        #expect(LocalEndpointPolicy.baseURL(from: "http://127.0.0.1:12000") == URL(string: "http://127.0.0.1:12000"))
        #expect(LocalEndpointPolicy.baseURL(from: "http://ollama.example.com") == nil)
    }
}

struct ModelTagTests {
    @Test func cloudTagsAreRecognised() {
        for tag in ["gpt-oss:20b-cloud", "gemma4:31b-cloud", "glm-5.3:cloud", "deepseek-v4.1-flash:cloud", "GEMMA4:CLOUD"] {
            #expect(ModelTag.isCloud(tag), "\(tag)")
        }
        for tag in ["translategemma:12b", "gpt-oss:20b", "gemma4", "cloudmodel:7b", "my-cloud-model:latest"] {
            #expect(!ModelTag.isCloud(tag), "\(tag)")
        }
    }

    @Test func tagWithoutVariantMeansLatest() {
        #expect(ModelTag.normalized("gemma4") == "gemma4:latest")
        #expect(ModelTag.normalized(" translategemma:12b ") == "translategemma:12b")
    }

    @Test func remoteEntriesAreNotLocal() {
        #expect(Ollama.ModelEntry(name: "translategemma:12b").isLocal)
        #expect(!Ollama.ModelEntry(name: "x:7b", remoteHost: "https://ollama.com").isLocal)
        #expect(!Ollama.ModelEntry(name: "gemma4:cloud").isLocal)
    }
}

struct TranslationModelConfigurationTests {
    @Test func defaultsToApprovedModel() {
        #expect(TranslationModelConfiguration(tag: nil).tag == "translategemma:12b")
        #expect(TranslationModelConfiguration(tag: "  ").tag == "translategemma:12b")
        #expect(TranslationModelConfiguration(tag: "gpt-oss:20b").tag == "gpt-oss:20b")
    }

    @Test func translateGemmaPromptFollowsModelCard() {
        let prompt = TranslateGemmaPrompt.make("Hello\nworld", from: .english, to: .vietnamese)
        #expect(prompt.hasPrefix("You are a professional English (en) to Vietnamese (vi) translator."))
        #expect(prompt.contains("Please translate the following English text into Vietnamese:\n\n\nHello\nworld"))
        #expect(prompt.hasSuffix("\n\n\nHello\nworld"))
        let reverse = TranslateGemmaPrompt.make("Xin chào", from: .vietnamese, to: .english)
        #expect(reverse.contains("Vietnamese (vi) to English (en)"))
        let messages = TranslationModelConfiguration(tag: nil).messages(translating: "Hi", direction: .englishToVietnamese)
        #expect(messages.count == 1)
        #expect(messages[0].role == "user")
    }
}

struct OllamaClientTests {
    private let base = LocalEndpointPolicy.defaultBaseURL

    @Test func rejectsNonLocalEndpointAtConstruction() {
        #expect(throws: OllamaError.endpointRejected) {
            try OllamaClient(baseURL: URL(string: "http://example.com:11434")!, transport: MockTransport.refusing())
        }
    }

    @Test func readsVersionAndInstalledModels() async throws {
        let transport = MockTransport.ollama(models: ["translategemma:12b"])
        let client = try OllamaClient(baseURL: base, transport: transport)
        #expect(try await client.version() == "0.34.4")
        #expect(try await client.installedModels().map(\.name) == ["translategemma:12b"])
        #expect(transport.requests.allSatisfy { $0.url?.host == "127.0.0.1" && $0.url?.port == 11434 })
    }

    @Test func connectionFailureMeansRuntimeUnavailable() async throws {
        let client = try OllamaClient(baseURL: base, transport: MockTransport.refusing())
        await #expect(throws: OllamaError.runtimeUnavailable) { try await client.version() }
    }

    @Test func http200WithWrongPayloadIsInvalid() async throws {
        let transport = MockTransport { _ in (200, Data("<html>not ollama</html>".utf8), nil) }
        let client = try OllamaClient(baseURL: base, transport: transport)
        await #expect(throws: OllamaError.invalidResponse) { try await client.installedModels() }
        let wrongShape = MockTransport { _ in (200, Data(#"{"something":"else"}"#.utf8), nil) }
        let other = try OllamaClient(baseURL: base, transport: wrongShape)
        await #expect(throws: OllamaError.invalidResponse) { try await other.version() }
    }

    @Test func chatSendsNonStreamingRequestAndReturnsText() async throws {
        let transport = MockTransport.ollama(models: ["translategemma:12b"], reply: "Chào buổi sáng.")
        let client = try OllamaClient(baseURL: base, transport: transport)
        let messages = [Ollama.ChatMessage(role: "user", content: "prompt")]
        #expect(try await client.chat(model: "translategemma:12b", messages: messages) == "Chào buổi sáng.")
        let request = try #require(transport.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/chat")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(body?["stream"] as? Bool == false)
        #expect(body?["model"] as? String == "translategemma:12b")
        #expect(body?["keep_alive"] == nil)
    }

    @Test func missingModelIsReportedFrom404() async throws {
        let client = try OllamaClient(baseURL: base, transport: MockTransport.ollama(models: []))
        await #expect(throws: OllamaError.modelMissing("nope:1b")) {
            try await client.chat(model: "nope:1b", messages: [.init(role: "user", content: "x")])
        }
    }

    @Test func cloudModelIsRefusedWithoutSendingAnything() async throws {
        let transport = MockTransport.ollama(models: ["gpt-oss:20b-cloud"])
        let client = try OllamaClient(baseURL: base, transport: transport)
        await #expect(throws: OllamaError.cloudModelRejected("gpt-oss:20b-cloud")) {
            try await client.chat(model: "gpt-oss:20b-cloud", messages: [.init(role: "user", content: "secret")])
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func responseFromAnotherHostIsRejected() async throws {
        let transport = MockTransport { _ in (200, Data(#"{"version":"1"}"#.utf8), URL(string: "http://example.com/api/version")) }
        let client = try OllamaClient(baseURL: base, transport: transport)
        await #expect(throws: OllamaError.endpointRejected) { try await client.version() }
    }

    @Test func emptyOutputIsAnError() async throws {
        let client = try OllamaClient(baseURL: base, transport: MockTransport.ollama(models: ["m:1"], reply: " \n"))
        await #expect(throws: OllamaError.emptyOutput) {
            try await client.chat(model: "m:1", messages: [.init(role: "user", content: "x")])
        }
    }

    @Test func urlSessionTransportRefusesRedirects() {
        let transport = URLSessionTransport()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "http://127.0.0.1:11434/api/tags")!)
        let redirected = RedirectBox()
        transport.urlSession(
            session, task: task,
            willPerformHTTPRedirection: HTTPURLResponse(url: task.originalRequest!.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!,
            newRequest: URLRequest(url: URL(string: "http://example.com")!)
        ) { redirected.set($0) }
        #expect(redirected.called)
        #expect(redirected.request == nil)
    }
}

@MainActor
struct OllamaReadinessTests {
    @Test func connectedWithInstalledModelIsReady() async {
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: MockTransport.ollama(models: ["translategemma:12b", "gpt-oss:20b-cloud"]))
        await readiness.refresh()
        #expect(readiness.runtime == .connected(version: "0.34.4"))
        #expect(readiness.model == .installed)
        #expect(readiness.isReady)
        #expect(readiness.installedLocalModels == ["translategemma:12b"])
        #expect(readiness.modelLabel == "translategemma:12b")
    }

    @Test func runtimeUnavailableAndModelMissingAreDistinct() async {
        let stopped = OllamaReadinessService(settings: MemoryModelSettings(), transport: MockTransport.refusing())
        await stopped.refresh()
        #expect(stopped.runtime == .notRunning)
        #expect(stopped.model == .unknown)
        #expect(!stopped.isReady)

        let empty = OllamaReadinessService(settings: MemoryModelSettings(), transport: MockTransport.ollama(models: []))
        await empty.refresh()
        #expect(empty.runtime == .connected(version: "0.34.4"))
        #expect(empty.model == .missing)
        #expect(empty.modelLabel == "translategemma:12b (not installed)")
    }

    @Test func nonLocalEndpointOverrideSendsNothing() async {
        let transport = MockTransport.ollama(models: ["translategemma:12b"])
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(baseURLString: "http://192.168.1.20:11434"), transport: transport)
        await readiness.refresh()
        #expect(readiness.runtime == .endpointRejected)
        #expect(readiness.client == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test func cloudTagIsRefusedEvenWhenListed() async {
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(modelTag: "gemma4:31b-cloud"), transport: MockTransport.ollama(models: ["gemma4:31b-cloud"]))
        await readiness.refresh()
        #expect(readiness.model == .cloudRejected)
        #expect(!readiness.isReady)
    }

    @Test func selectingAModelPersistsOnlyTheTag() async {
        let settings = MemoryModelSettings()
        let readiness = OllamaReadinessService(settings: settings, transport: MockTransport.ollama(models: ["translategemma:12b", "translategemma:4b"]))
        await readiness.refresh()
        readiness.selectModel("translategemma:4b")
        #expect(settings.modelTag == "translategemma:4b")
        #expect(readiness.model == .installed)
        readiness.selectModel("nope:1b")
        #expect(readiness.model == .missing)
    }

    @Test func recoversWhenRuntimeStarts() async {
        let flag = Flag()
        let transport = MockTransport { request in
            guard flag.isOn else { throw URLError(.cannotConnectToHost) }
            return try MockTransport.ollama(models: ["translategemma:12b"]).routeForTests(request)
        }
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: transport)
        await readiness.refresh()
        #expect(readiness.runtime == .notRunning)
        flag.isOn = true
        await readiness.refresh()
        #expect(readiness.isReady)
    }

    #if DEBUG
    @Test func sampleTranslationUsesConfiguredModel() async throws {
        let transport = MockTransport.ollama(models: ["translategemma:12b"], reply: "Thanh toán đã được xử lý.")
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: transport)
        await readiness.refresh()
        let result = await readiness.translateSample()
        #expect((try? result.get())?.text == "Thanh toán đã được xử lý.")
        let body = try JSONSerialization.jsonObject(with: transport.requests.last?.httpBody ?? Data()) as? [String: Any]
        let content = ((body?["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
        #expect(content.hasSuffix("\n\n\n" + OllamaReadinessService.sampleSentence))
    }
    #endif
}

private final class RedirectBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var called = false
    private(set) var request: URLRequest?

    func set(_ request: URLRequest?) {
        lock.withLock {
            called = true
            self.request = request
        }
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isOn: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// Live check against the local Ollama with a synthetic sentence. Runs only
/// when TEST_RUNNER_LT_LIVE_OLLAMA=1 is passed to xcodebuild, so the normal
/// suite never depends on a running runtime.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LT_LIVE_OLLAMA"] == "1"))
struct OllamaLiveTests {
    @Test func realTransportReachesLocalOllamaAndTranslates() async throws {
        let client = try OllamaClient(baseURL: LocalEndpointPolicy.defaultBaseURL, transport: URLSessionTransport())
        #expect(!(try await client.version()).isEmpty)
        let models = try await client.installedModels().map(\.name)
        #expect(models.contains("translategemma:12b"))
        let config = TranslationModelConfiguration(tag: nil)
        let output = try await client.chat(model: config.tag, messages: config.messages(translating: "Good morning.", direction: .englishToVietnamese), keepAlive: "30m")
        #expect(!output.isEmpty)
        await #expect(throws: OllamaError.modelMissing("definitely-missing:1b")) {
            try await client.chat(model: "definitely-missing:1b", messages: [.init(role: "user", content: "Hi")])
        }
    }
}
