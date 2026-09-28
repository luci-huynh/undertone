import CoreGraphics
import Foundation
import Testing
@testable import Undertone

/// S26: the whole ⌥T path with the real router, prompt builder, budget,
/// Ollama client, stream parser, watchdog and coordinator; only the network
/// (MockTransport) and the AX capture are fakes. No Ollama, no TCC.
@MainActor
struct PipelineIntegrationTests {
    private let anchor = SelectionAnchor(source: .selectionBounds, rect: CGRect(x: 200, y: 500, width: 120, height: 18), screenIndex: 0, visibleFrame: testScreen)

    private func snapshot(_ text: String) -> SelectionSnapshot {
        SelectionSnapshot(sourcePID: 42, sourceAppName: "Slack", text: text, range: nil, anchor: anchor, capturedAt: Date())
    }

    private func chatBody(_ transport: MockTransport) throws -> [String: Any]? {
        let request = transport.requests.last { $0.url?.path == "/api/chat" }
        return try JSONSerialization.jsonObject(with: request?.httpBody ?? Data()) as? [String: Any]
    }

    private func run(
        _ text: String, transport: MockTransport
    ) async -> (TranslationCoordinator, FakePopupPresenter) {
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: transport)
        let popup = FakePopupPresenter()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot(text))]),
            translator: OllamaTranslationService(readiness: readiness),
            popup: popup,
            detection: nil
        )
        flow.trigger()
        await flow.captureTask?.value
        await flow.translationTask?.value
        return (flow, popup)
    }

    @Test func vietnameseSelectionIsTranslatedToEnglishEndToEnd() async throws {
        let transport = MockTransport.ollama(models: ["translategemma:12b"], reply: "The refund will be processed before Friday.")
        let text = "Khoản hoàn tiền sẽ được xử lý trước thứ Sáu nhé."
        let (_, popup) = await run(text, transport: transport)

        #expect(popup.current?.title == "Vietnamese → English")
        #expect(popup.current?.phase == .done)
        #expect(popup.current?.body == "The refund will be processed before Friday.")
        #expect(popup.current?.canCopy == true)
        #expect(popup.shown.first?.content.phase == .loading)
        #expect(popup.shown.allSatisfy { $0.anchor == anchor })

        let body = try chatBody(transport)
        #expect(body?["model"] as? String == "translategemma:12b")
        #expect(body?["stream"] as? Bool == true)
        #expect(body?["keep_alive"] as? String == "30m")
        #expect((body?["options"] as? [String: Any])?["num_ctx"] as? Int == 4096)
        let prompt = ((body?["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
        #expect(prompt.hasPrefix("You are a professional Vietnamese (vi) to English (en) translator."))
        #expect(prompt.hasSuffix("\n\n\n" + text))
        // Privacy: every request stayed on loopback.
        #expect(!transport.requests.isEmpty)
        #expect(transport.requests.allSatisfy { $0.url.map(LocalEndpointPolicy.isAllowed) == true })
    }

    @Test func englishSelectionGoesToVietnamese() async throws {
        let transport = MockTransport.ollama(models: ["translategemma:12b"], reply: "Thanh toán đã được xử lý.")
        let (_, popup) = await run("The payment has been processed and the receipt was sent.", transport: transport)
        #expect(popup.current?.title == "English → Vietnamese")
        #expect(popup.current?.body == "Thanh toán đã được xử lý.")
        let prompt = ((try chatBody(transport)?["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
        #expect(prompt.hasPrefix("You are a professional English (en) to Vietnamese (vi) translator."))
    }

    @Test func urlOnlySelectionNeverReachesOllama() async {
        let transport = MockTransport.ollama(models: ["translategemma:12b"])
        let (_, popup) = await run("app.example.com/p/Enable-Platform-functionality?source=copy_link", transport: transport)
        #expect(popup.shown.first?.content.body == TranslationCoordinator.nothingToTranslateMessage)
        #expect(transport.requests.isEmpty)
    }

    @Test func tooLongSelectionIsRefusedWithoutAnyRequest() async {
        let transport = MockTransport.ollama(models: ["translategemma:12b"])
        let text = String(repeating: "The payment has been processed. ", count: 200)
        let (_, popup) = await run(text, transport: transport)
        #expect(popup.current?.message == "Selected text is too long to translate at once.")
        #expect(popup.current?.action == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test func ollamaDownThenRetryRecovers() async throws {
        let ollama = MockTransport.ollama(models: ["translategemma:12b"], reply: "Xin chào.")
        let up = Flag()
        let transport = MockTransport { request in
            guard up.value else { throw URLError(.cannotConnectToHost) }
            return try ollama.routeForTests(request)
        }
        let (flow, popup) = await run("Good morning, everyone, the meeting starts now.", transport: transport)
        #expect(popup.current?.message == "Ollama is not running.")
        #expect(popup.current?.action == .retry)

        up.value = true
        popup.onAction?(.retry)
        await flow.translationTask?.value
        #expect(popup.current?.phase == .done)
        #expect(popup.current?.body == "Xin chào.")
    }

    @Test func missingModelEndToEndIsExplainedWithoutRetry() async {
        let transport = MockTransport.ollama(models: ["some-other:1b"])
        let (_, popup) = await run("Good morning, everyone, the meeting starts now.", transport: transport)
        #expect(popup.current?.message == "Translation model is not installed.")
        #expect(popup.current?.action == nil)
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
