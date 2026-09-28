import Foundation
import ServiceManagement
@testable import Undertone

/// Mirrors the real API: a prompt returns the current trust immediately;
/// a grant only happens later, when the user toggles System Settings.
final class FakeTrust: AccessibilityTrustChecking {
    var trusted: Bool
    private(set) var promptCount = 0
    private(set) var checkCount = 0

    init(trusted: Bool) { self.trusted = trusted }

    func isTrusted(prompt: Bool) -> Bool {
        checkCount += 1
        if prompt { promptCount += 1 }
        return trusted
    }
}

final class FakeSettingsOpener: SystemSettingsOpening {
    private(set) var openCount = 0
    func openAccessibilityPrivacy() { openCount += 1 }
}

extension AccessibilityPermissionService {
    static func fake(trusted: Bool = false) -> AccessibilityPermissionService {
        AccessibilityPermissionService(trust: FakeTrust(trusted: trusted), settings: FakeSettingsOpener())
    }
}

final class FakeHotKeyRegistrar: HotKeyRegistering {
    var failure: HotKeyRegistrationError?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var registered: HotKeyCombination?
    private var handler: ((HotKeyPhase) -> Void)?

    func register(_ combination: HotKeyCombination, handler: @escaping (HotKeyPhase) -> Void) throws {
        registerCount += 1
        if let failure { throw failure }
        registered = combination
        self.handler = handler
    }

    func unregister() {
        unregisterCount += 1
        registered = nil
        handler = nil
    }

    /// Simulates the system delivering an event; no-op once unregistered.
    func send(_ phase: HotKeyPhase) { handler?(phase) }
}

extension GlobalShortcutService {
    static func fake() -> GlobalShortcutService {
        GlobalShortcutService(registrar: FakeHotKeyRegistrar())
    }
}

final class FakeSelectionEnvironment: SelectionEnvironment {
    var frontmost: [SourceApp?]
    var secureInput = false
    var mouse = CGPoint(x: 100, y: 100)
    var layout = ScreenLayout(screens: [.init(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )])
    let currentPID: pid_t = 1
    private(set) var frontmostQueries = 0

    /// Successive frontmost answers (before read, after read); the last repeats.
    init(frontmost: [SourceApp?]) { self.frontmost = frontmost }

    func frontmostApplication() -> SourceApp? {
        defer { frontmostQueries += 1 }
        return frontmost[min(frontmostQueries, frontmost.count - 1)]
    }

    func isSecureInputEnabled() -> Bool { secureInput }

    func mouseLocation() -> CGPoint { mouse }

    func screenLayout() -> ScreenLayout { layout }
}

final class FakeFocusedElementQuery: FocusedElementQuerying, @unchecked Sendable {
    var reading: FocusedElementReading
    private(set) var readPIDs: [pid_t] = []

    init(reading: FocusedElementReading) { self.reading = reading }

    func read(pid: pid_t) async -> FocusedElementReading {
        readPIDs.append(pid)
        return reading
    }
}

final class FakeSelectionCapturer: SelectionCapturing {
    var results: [Result<SelectionSnapshot, SelectionFailure>]
    private(set) var captureCount = 0

    init(results: [Result<SelectionSnapshot, SelectionFailure>]) { self.results = results }

    func capture() async -> Result<SelectionSnapshot, SelectionFailure> {
        defer { captureCount += 1 }
        return results[min(captureCount, results.count - 1)]
    }
}

@MainActor
final class FakePopupPresenter: PopupPresenting {
    var onDismiss: (() -> Void)?
    var onAction: ((PopupContent.Action) -> Void)?
    private(set) var shown: [(content: PopupContent, anchor: SelectionAnchor)] = []
    private(set) var closeCount = 0
    private(set) var isVisible = false

    /// Content currently on screen.
    var current: PopupContent? { isVisible ? shown.last?.content : nil }

    func show(_ content: PopupContent, at anchor: SelectionAnchor) {
        shown.append((content, anchor))
        isVisible = true
    }

    func close() {
        closeCount += 1
        isVisible = false
    }

    /// Simulates Esc or ×.
    func dismissByUser() {
        close()
        onDismiss?()
    }
}

/// Translator whose streams the test drives by hand, one per request.
@MainActor
final class ScriptedTranslator: TranslationProviding {
    private(set) var inputs: [String] = []
    private(set) var directions: [TranslationDirection] = []
    private var continuations: [AsyncThrowingStream<String, Error>.Continuation] = []
    private let terminations = TerminationLog()

    /// Requests whose stream the consumer stopped (cancel propagates to the producer).
    var terminatedRequests: [Int] { terminations.values }

    func translate(_ text: String, direction: TranslationDirection) -> AsyncThrowingStream<String, Error> {
        inputs.append(text)
        directions.append(direction)
        let index = inputs.count - 1
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let log = terminations
        continuation.onTermination = { termination in
            if case .cancelled = termination { log.append(index) }
        }
        continuations.append(continuation)
        return stream
    }

    func send(_ delta: String, request: Int = 0) { continuations[request].yield(delta) }
    func finish(request: Int = 0) { continuations[request].finish() }
    func fail(request: Int = 0) { continuations[request].finish(throwing: URLError(.cannotConnectToHost)) }
    func fail(_ error: Error, request: Int = 0) { continuations[request].finish(throwing: error) }
}

final class TerminationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Int] = []
    var values: [Int] { lock.withLock { stored } }
    func append(_ value: Int) { lock.withLock { stored.append(value) } }
}

let testScreen = CGRect(x: 0, y: 0, width: 1440, height: 875)
let cursorTestAnchor = SelectionAnchor(source: .mouse, rect: CGRect(x: 500, y: 500, width: 0, height: 0), screenIndex: 0, visibleFrame: testScreen)

@MainActor
extension TranslationCoordinator {
    static func fake(
        selection: (any SelectionCapturing)? = nil,
        translator: (any TranslationProviding)? = nil,
        popup: FakePopupPresenter? = nil,
        noticeDuration: Duration = .zero,
        renderInterval: Duration = .zero,
        detection: LanguageDetection? = .english
    ) -> TranslationCoordinator {
        TranslationCoordinator(
            selection: selection ?? FakeSelectionCapturer(results: [.failure(.noSelection)]),
            translator: translator ?? ScriptedTranslator(),
            popup: popup ?? FakePopupPresenter(),
            cursorAnchor: { cursorTestAnchor },
            noticeDuration: noticeDuration,
            renderInterval: renderInterval,
            // nil: the real on-device router.
            detectLanguage: detection.map { fixed in { _ in fixed } } ?? LanguageRouter.detect
        )
    }
}

@MainActor
extension AppCoordinator {
    static func fake(
        shortcut: GlobalShortcutService? = nil,
        flow: TranslationCoordinator? = nil,
        readiness: OllamaReadinessService? = nil,
        selectionTrigger: SelectionTriggerService? = nil,
        live: LiveSession? = nil
    ) -> AppCoordinator {
        AppCoordinator(
            readiness: readiness ?? OllamaReadinessService(settings: MemoryModelSettings(), transport: MockTransport.refusing()),
            permission: .fake(),
            shortcut: shortcut ?? .fake(),
            flow: flow ?? .fake(),
            selectionTrigger: selectionTrigger ?? .fake(),
            launchAtLogin: LaunchAtLoginService(item: FakeLoginItem()),
            live: live ?? .fake()
        )
    }
}

@MainActor
final class FakeSelectionEvents: SelectionEventSource {
    private(set) var handler: ((SelectionMouseEvent) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var isRunning: Bool { handler != nil }

    func start(_ handler: @escaping (SelectionMouseEvent) -> Void) {
        startCount += 1
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func send(_ events: SelectionMouseEvent...) {
        for event in events { handler?(event) }
    }
}

@MainActor
final class FakeTriggerPresenter: SelectionTriggerPresenting {
    var onClick: (() -> Void)?
    private(set) var isVisible = false
    private(set) var shownAt: [SelectionAnchor] = []

    func show(at anchor: SelectionAnchor) {
        shownAt.append(anchor)
        isVisible = true
    }

    func hide() { isVisible = false }

    func click() { onClick?() }
}

final class MemoryTriggerSettings: SelectionTriggerSettingsStoring {
    var showsSelectionTrigger: Bool
    init(_ on: Bool = true) { showsSelectionTrigger = on }
}

@MainActor
extension SelectionTriggerService {
    static func fake(
        selection: (any SelectionCapturing)? = nil,
        presenter: FakeTriggerPresenter? = nil,
        events: FakeSelectionEvents? = nil,
        settings: MemoryTriggerSettings? = nil,
        visibleDuration: Duration = .seconds(60)
    ) -> SelectionTriggerService {
        SelectionTriggerService(
            selection: selection ?? FakeSelectionCapturer(results: [.failure(.noSelection)]),
            presenter: presenter ?? FakeTriggerPresenter(),
            events: events ?? FakeSelectionEvents(),
            settings: settings ?? MemoryTriggerSettings(),
            cursorAnchor: { cursorTestAnchor },
            settleDelay: .zero,
            visibleDuration: visibleDuration
        )
    }
}

final class MemoryModelSettings: ModelSettingsStoring {
    var modelTag: String?
    var baseURLString: String?

    init(modelTag: String? = nil, baseURLString: String? = nil) {
        self.modelTag = modelTag
        self.baseURLString = baseURLString
    }
}

/// Answers requests from a routing closure and records them. Never touches the network.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Route = @Sendable (URLRequest) throws -> (Int, Data, URL?)
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let route: Route

    init(route: @escaping Route) { self.route = route }

    var requests: [URLRequest] { lock.withLock { recorded } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let (status, data, responseURL) = try route(request)
        let response = HTTPURLResponse(url: responseURL ?? request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }

    /// Streams the routed body split by `chunking` (whole body by default).
    var chunking: @Sendable (Data) -> [Data] = { [$0] }

    func stream(_ request: URLRequest) -> AsyncThrowingStream<HTTPStreamPart, Error> {
        lock.withLock { recorded.append(request) }
        let route = route
        let chunking = chunking
        return AsyncThrowingStream { continuation in
            do {
                let (status, body, responseURL) = try route(request)
                let response = HTTPURLResponse(url: responseURL ?? request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
                continuation.yield(.response(response))
                for chunk in chunking(body) {
                    continuation.yield(.data(chunk))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Exposes the routing closure so one mock can delegate to another.
    func routeForTests(_ request: URLRequest) throws -> (Int, Data, URL?) { try route(request) }

    /// Like a stopped Ollama: connection refused.
    static func refusing() -> MockTransport {
        MockTransport { _ in throw URLError(.cannotConnectToHost) }
    }

    /// A running Ollama with the given installed models; chat echoes `reply`.
    static func ollama(models: [String], reply: String = "Thanh toán đã được xử lý.") -> MockTransport {
        MockTransport { request in
            switch request.url?.path {
            case "/api/version":
                return (200, Data(#"{"version":"0.34.4"}"#.utf8), nil)
            case "/api/tags":
                let entries = models.map { #"{"name":"\#($0)","model":"\#($0)","digest":"abc","size":1}"# }
                return (200, Data(#"{"models":[\#(entries.joined(separator: ","))]}"#.utf8), nil)
            case "/api/chat":
                let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                let model = body?["model"] as? String ?? ""
                guard models.contains(model) else {
                    return (404, Data(#"{"error":"model '\#(model)' not found"}"#.utf8), nil)
                }
                if body?["stream"] as? Bool == true {
                    // NDJSON like Ollama: one frame per word, then done.
                    var lines = PlaceholderTranslationService.chunks(of: reply).map { word in
                        String(data: try! JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": word], "done": false]), encoding: .utf8)!
                    }
                    lines.append(#"{"message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}"#)
                    return (200, Data((lines.joined(separator: "\n") + "\n").utf8), nil)
                }
                let content = try JSONSerialization.data(withJSONObject: ["model": model, "message": ["role": "assistant", "content": reply], "done": true])
                return (200, content, nil)
            default:
                return (404, Data("404 page not found".utf8), nil)
            }
        }
    }
}

@MainActor
final class FakeLoginItem: LoginItemControlling {
    var status: SMAppService.Status = .notRegistered
    var registerResult: SMAppService.Status = .enabled
    var failure: Error?
    private(set) var openedSettings = 0

    func register() throws {
        if let failure { throw failure }
        status = registerResult
    }

    func unregister() throws {
        if let failure { throw failure }
        status = .notRegistered
    }

    func openSystemSettings() { openedSettings += 1 }
}

// MARK: - Live (Feature 2)

final class FakeLiveCapture: LiveAudioCapturing {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var bundleIDs: [String] = []
    private(set) var sink: (any LiveAudioSink)?
    private var onLevel: (@MainActor (LiveAudioLevel) -> Void)?
    var failure: LiveCaptureError?
    var isCapturing: Bool { onLevel != nil }

    func start(bundleIDs: [String], into sink: any LiveAudioSink, onLevel: @escaping @MainActor (LiveAudioLevel) -> Void) throws {
        startCount += 1
        if let failure { throw failure }
        self.bundleIDs = bundleIDs
        self.sink = sink
        self.onLevel = onLevel
    }

    func stop() {
        stopCount += 1
        onLevel = nil
    }

    /// Simulates audio from the tapped processes.
    @MainActor
    func emit(rms: Float, samples: [Float] = [0.1, -0.1]) {
        sink?.append(samples, sampleRate: 48_000)
        onLevel?(LiveAudioLevel(rms: rms))
    }
}

/// Recognizer the test drives by hand.
final class FakeTranscriber: LiveTranscribing {
    var prepareFailure: LiveTranscriberError?
    var progressSteps: [Double] = []
    /// When set, prepare() waits until `releasePrepare()` (model download in progress).
    var holdsPrepare = false
    private var prepareGate: CheckedContinuation<Void, Never>?
    func releasePrepare() {
        prepareGate?.resume()
        prepareGate = nil
    }
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var finalizeCount = 0
    private(set) var received: [[Float]] = []
    private var continuation: AsyncThrowingStream<LiveTranscriptEvent, Error>.Continuation?

    private final class Sink: LiveAudioSink, @unchecked Sendable {
        let owner: FakeTranscriber
        init(_ owner: FakeTranscriber) { self.owner = owner }
        func append(_ samples: [Float], sampleRate: Double) {
            MainActor.assumeIsolated { owner.received.append(samples) }
        }
    }

    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {
        prepareCount += 1
        for step in progressSteps { progress(step) }
        if holdsPrepare { await withCheckedContinuation { prepareGate = $0 } }
        if let prepareFailure { throw prepareFailure }
    }

    func start() async throws -> (sink: any LiveAudioSink, events: AsyncThrowingStream<LiveTranscriptEvent, Error>) {
        startCount += 1
        let (stream, continuation) = AsyncThrowingStream<LiveTranscriptEvent, Error>.makeStream()
        self.continuation = continuation
        return (Sink(self), stream)
    }

    /// When set, finalizeNow() waits until `releaseFinalize()`.
    var holdsFinalize = false
    private var finalizeGate: CheckedContinuation<Void, Never>?
    func releaseFinalize() {
        finalizeGate?.resume()
        finalizeGate = nil
    }

    func finalizeNow() async {
        finalizeCount += 1
        if holdsFinalize { await withCheckedContinuation { finalizeGate = $0 } }
    }

    func stop() async {
        stopCount += 1
        continuation?.finish()
    }

    func send(_ event: LiveTranscriptEvent) { continuation?.yield(event) }
    /// The recognizer ends on its own (nil: finished, else failed).
    func end(throwing error: Error? = nil) {
        if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
    }
}

final class FakeSystemEvents: LiveSystemEventSource {
    private var handler: ((LiveSystemEvent) -> Void)?
    var isListening: Bool { handler != nil }
    func start(_ handler: @escaping (LiveSystemEvent) -> Void) { self.handler = handler }
    func stop() { handler = nil }
    func send(_ event: LiveSystemEvent) { handler?(event) }
}

final class FakeProcessList: LiveProcessListing {
    var processes: [LiveAudioProcess]
    init(_ processes: [LiveAudioProcess] = []) { self.processes = processes }
    func audioProcesses() -> [LiveAudioProcess] { processes }
}

final class MemoryLiveSettings: LiveSettingsStoring {
    var source: LiveSource = .teams
    var keepsWindowOnTop = true
}

/// Manual clock for Live status timing.
final class ManualClock {
    private(set) var now = ContinuousClock.now
    func advance(_ duration: Duration) { now += duration }
}

@MainActor
extension LiveSession {
    static func fake(
        capture: FakeLiveCapture? = nil,
        transcriber: FakeTranscriber? = nil,
        translations: LiveTranslationQueue? = nil,
        processes: FakeProcessList? = nil,
        systemEvents: FakeSystemEvents? = nil,
        clock: ManualClock = ManualClock(),
        makeTranscriber: (() -> FakeTranscriber)? = nil
    ) -> LiveSession {
        let recognizer = transcriber ?? FakeTranscriber()
        return LiveSession(
            capture: capture ?? FakeLiveCapture(), transcriber: makeTranscriber ?? { recognizer },
            translations: translations ?? LiveTranslationQueue(translate: { _ in AsyncThrowingStream { $0.finish() } }, isTextBusy: { false }),
            processes: processes ?? FakeProcessList(), systemEvents: systemEvents ?? FakeSystemEvents(), settings: MemoryLiveSettings(),
            statusInterval: .seconds(3600), blockedAfter: .seconds(4), now: { clock.now }
        )
    }
}
