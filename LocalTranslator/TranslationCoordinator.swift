import Foundation
import os

/// Produces output for a selection as a stream of text deltas.
protocol TranslationProviding {
    /// Direction line for the popup, e.g. “English → Vietnamese”.
    func title(for direction: TranslationDirection) -> String
    func translate(_ text: String, direction: TranslationDirection) -> AsyncThrowingStream<String, Error>
}

extension TranslationProviding {
    func title(for direction: TranslationDirection) -> String { direction.title }
}

/// Real translation through the local Ollama (S20), in the direction the
/// coordinator routed (S21).
struct OllamaTranslationService: TranslationProviding {
    /// User decision B (docs/OLLAMA.md): keep the model loaded 30 min after use.
    static let keepAlive = "30m"

    let readiness: OllamaReadinessService
    var firstTokenLimit = StreamWatchdog.firstTokenLimit
    var stallLimit = StreamWatchdog.stallLimit

    func translate(_ text: String, direction: TranslationDirection) -> AsyncThrowingStream<String, Error> {
        guard let client = readiness.client else {
            return AsyncThrowingStream { $0.finish(throwing: OllamaError.endpointRejected) }
        }
        // Refused before anything is sent, never cut silently (runbook S22).
        guard TranslationBudget.fits(text) else {
            return AsyncThrowingStream { $0.finish(throwing: OllamaError.inputTooLong) }
        }
        let configuration = readiness.configuration
        let upstream = StreamWatchdog.watch(
            client.chatStream(
                model: configuration.tag,
                messages: configuration.messages(translating: text, direction: direction),
                keepAlive: Self.keepAlive,
                options: TranslationBudget.options
            ),
            first: firstTokenLimit,
            between: stallLimit
        )
        let readiness = readiness
        // Pass deltas through; on a runtime/model failure refresh readiness so
        // the menu and Settings reflect it.
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await delta in upstream { continuation.yield(delta) }
                    continuation.finish()
                } catch {
                    if let error = error as? OllamaError, error == .runtimeUnavailable || error == .modelMissing(configuration.tag) {
                        Task { @MainActor in await readiness.refresh() }
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// S14 stand-in until the Ollama client exists (S18–S20): streams the
/// selection itself back in word-sized chunks so the popup's loading and
/// streaming states can be exercised. No network, nothing stored.
struct PlaceholderTranslationService: TranslationProviding {
    var initialDelay: Duration = .milliseconds(250)
    /// Whole stream takes at most about this long, whatever the length.
    var totalDuration: Duration = .milliseconds(1200)

    func title(for direction: TranslationDirection) -> String { TranslationCoordinator.placeholderTitle }

    func translate(_ text: String, direction: TranslationDirection) -> AsyncThrowingStream<String, Error> {
        let chunks = Self.chunks(of: text)
        let step = chunks.isEmpty ? .zero : min(.milliseconds(40), totalDuration / chunks.count)
        let initialDelay = initialDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(for: initialDelay)
                    for chunk in chunks {
                        try await Task.sleep(for: step)
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Splits after each run of whitespace, keeping the text byte-identical when joined.
    nonisolated static func chunks(of text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        var previousWasSpace = false
        for character in text {
            let isSpace = character.isWhitespace
            if previousWasSpace && !isSpace {
                chunks.append(current)
                current = ""
            }
            current.append(character)
            previousWasSpace = isSpace
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

/// ⌥T flow: capture an immutable snapshot, route its direction (S21), open
/// the popup at its anchor, stream output into it. Each trigger or ⇄ cancels
/// the previous request first; every result is checked against the newest
/// trigger/request ID so older work can never overwrite newer content. The
/// selection is read once per trigger and never re-read while the popup is open.
@MainActor
final class TranslationCoordinator {
    static let placeholderTitle = "Selected text · translation not connected yet"
    static let nothingToTranslateMessage = "Nothing to translate."

    private let selection: any SelectionCapturing
    private let translator: any TranslationProviding
    private let popup: any PopupPresenting
    /// Cursor anchor at trigger time, for popups that have no selection anchor.
    private let cursorAnchor: () -> SelectionAnchor?
    private let noticeDuration: Duration
    /// Streaming deltas are rendered at most this often (each render re-measures the popup).
    private let renderInterval: Duration
    private let detectLanguage: (String) -> LanguageDetection
    let state = TranslationStateMachine()
    var onOpenAccessibilitySettings: (() -> Void)?

    private let logger = Logger(subsystem: "local.chienhuynh.LocalTranslator", category: "selection")
    private var triggerSequence = 0
    private var anchor: SelectionAnchor?
    /// The open popup's text and direction, kept only while it is open (for ⇄).
    private var request: (text: String, direction: TranslationDirection, guessed: Bool)?
    private var renderTask: Task<Void, Never>?
    /// Exposed so tests can await them.
    private(set) var captureTask: Task<Void, Never>?
    private(set) var translationTask: Task<Void, Never>?
    private(set) var noticeTask: Task<Void, Never>?

    init(
        selection: any SelectionCapturing,
        translator: any TranslationProviding,
        popup: any PopupPresenting,
        cursorAnchor: @escaping () -> SelectionAnchor?,
        noticeDuration: Duration = .seconds(2),
        renderInterval: Duration = .milliseconds(40),
        detectLanguage: @escaping (String) -> LanguageDetection = LanguageRouter.detect
    ) {
        self.selection = selection
        self.translator = translator
        self.popup = popup
        self.cursorAnchor = cursorAnchor
        self.noticeDuration = noticeDuration
        self.renderInterval = renderInterval
        self.detectLanguage = detectLanguage
        popup.onDismiss = { [weak self] in self?.cancelWork() }
        popup.onAction = { [weak self] action in
            switch action {
            case .openAccessibilitySettings:
                self?.popup.close()
                self?.cancelWork()
                self?.onOpenAccessibilitySettings?()
            case .switchDirection:
                self?.switchDirection()
            case .retry:
                self?.retry()
            }
        }
    }

    func trigger() {
        cancelWork()
        triggerSequence += 1
        let sequence = triggerSequence
        let fallbackAnchor = cursorAnchor()
        let startedAt = Date()
        captureTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let result = await selection.capture()
            guard sequence == triggerSequence, !Task.isCancelled else { return }
            let elapsed = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
            switch result {
            case .success(let snapshot):
                logger.notice("Selection captured: \(snapshot.text.count, privacy: .public) chars in \(elapsed, privacy: .public) ms")
                startRequest(for: snapshot, anchor: snapshot.anchor ?? fallbackAnchor)
                // S27 measurement: trigger → popup on screen (metadata only).
                let shown = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
                logger.notice("Popup shown \(shown, privacy: .public) ms after trigger")
            case .failure(let failure):
                logger.notice("Selection not captured: \(failure.label, privacy: .public) in \(elapsed, privacy: .public) ms")
                showNotice(for: failure, anchor: fallbackAnchor)
            }
        }
    }

    func shutdown() {
        triggerSequence += 1
        cancelWork()
        popup.close()
    }

    /// ⇄ in the popup: translate the same text the other way. The running
    /// stream is cancelled and the request ID changes, so no delta of the old
    /// direction can reach the popup. Not remembered (PLAN F05 defines no
    /// saved override).
    func switchDirection() {
        guard let request, anchor != nil else { return }
        translationTask?.cancel()
        renderTask?.cancel()
        renderTask = nil
        logger.notice("Direction switched to \(request.direction.switched.shortTitle, privacy: .public)")
        translate(request.text, direction: request.direction.switched, guessed: false)
    }

    /// Retry in a failed popup, or ↻ after a finished one (S25): the same text
    /// and direction once more, only when the user asks (no automatic
    /// retries, no duplicate requests).
    func retry() {
        let canRetry = state.phase == .success || (state.phase == .error && state.failure?.allowsRetry == true)
        guard let request, anchor != nil, canRetry else { return }
        translationTask?.cancel()
        renderTask?.cancel()
        renderTask = nil
        logger.notice("Retry")
        translate(request.text, direction: request.direction, guessed: request.guessed)
    }

    private func startRequest(for snapshot: SelectionSnapshot, anchor: SelectionAnchor?) {
        guard let anchor else { return }
        switch TranslationRoute(detectLanguage(snapshot.text)) {
        case .nothingToTranslate:
            logger.notice("Nothing to translate")
            showNotice(Self.nothingToTranslateMessage, action: nil, anchor: anchor)
        case .translate(let direction, let guessed):
            logger.notice("Direction \(direction.shortTitle, privacy: .public)\(guessed ? " (guessed)" : "", privacy: .public)")
            self.anchor = anchor
            translate(snapshot.text, direction: direction, guessed: guessed)
        }
    }

    private func translate(_ text: String, direction: TranslationDirection, guessed: Bool) {
        request = (text, direction, guessed)
        let id = state.begin()
        present(for: id)
        let requestStart = ContinuousClock.now
        translationTask = Task { [weak self] in
            // A request replaced before it ran (quick ⇄ ⇄) never reaches the translator.
            guard let self, !Task.isCancelled else { return }
            do {
                var firstText: Duration?
                for try await delta in translator.translate(text, direction: direction) {
                    guard state.requestID == id, !Task.isCancelled else { return }
                    if firstText == nil { firstText = ContinuousClock.now - requestStart }
                    state.receive(delta, for: id)
                    scheduleRender(for: id)
                }
                guard !Task.isCancelled else { return }
                state.complete(for: id)
                // S27 measurement: request → first text and → done (metadata only).
                let total = ContinuousClock.now - requestStart
                logger.notice("Translated \(text.count, privacy: .public) → \(self.state.output.count, privacy: .public) chars; first text \(Self.milliseconds(firstText), privacy: .public) ms, done \(Self.milliseconds(total), privacy: .public) ms")
            } catch {
                // Our own cancellation (close, ⌥T, ⇄, Retry) is not an error.
                guard !Task.isCancelled, state.requestID == id else { return }
                let failure = TranslationError(error)
                logger.notice("Translation failed: \(failure.logLabel, privacy: .public), \(self.state.output.count, privacy: .public) chars received")
                state.fail(failure, for: id)
            }
            renderTask?.cancel()
            renderTask = nil
            present(for: id)
        }
    }

    private static func milliseconds(_ duration: Duration?) -> Int {
        guard let duration else { return -1 }
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }

    /// Coalesces bursts of deltas into one render per `renderInterval`.
    private func scheduleRender(for id: UUID) {
        guard renderInterval > .zero else { return present(for: id) }
        guard renderTask == nil else { return }
        let interval = renderInterval
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard let self, !Task.isCancelled else { return }
            renderTask = nil
            present(for: id)
        }
    }

    /// Renders the state machine for request `id`; anything else is stale.
    private func present(for id: UUID) {
        guard state.requestID == id, let anchor, let request else { return }
        // A guess is marked so the direction is never presented as certain (S21).
        let title = translator.title(for: request.direction) + (request.guessed ? " (guessed)" : "")
        let alternate = request.direction.switched
        let content: PopupContent
        switch state.phase {
        case .loading:
            content = PopupContent(title: title, body: "", phase: .loading, session: id, alternateDirection: alternate)
        case .streaming:
            content = PopupContent(title: title, body: state.output, phase: .streaming, session: id, alternateDirection: alternate)
        case .success:
            content = PopupContent(
                title: title, body: state.output, phase: .done, session: id, alternateDirection: alternate, offersRetranslate: true
            )
        case .error:
            // Partial output stays visible with the reason (runbook S20).
            let partial = state.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : state.output
            let failure = state.failure ?? .unavailable
            content = PopupContent(
                title: title, body: partial, phase: .failed, action: failure.allowsRetry ? .retry : nil,
                message: failure.message, session: id, alternateDirection: alternate
            )
        case .idle, .cancelled:
            return
        }
        popup.show(content, at: anchor)
    }

    private func showNotice(for failure: SelectionFailure, anchor: SelectionAnchor?) {
        guard let message = failure.popupMessage, let anchor else {
            popup.close()
            return
        }
        showNotice(message, action: failure.popupAction, anchor: anchor)
    }

    private func showNotice(_ message: String, action: PopupContent.Action?, anchor: SelectionAnchor) {
        popup.show(PopupContent(title: "", body: message, phase: .notice, action: action, session: UUID()), at: anchor)
        // PLAN §14: small popup, auto-dismiss. One with an action stays until used or closed.
        guard action == nil else { return }
        let sequence = triggerSequence
        let duration = noticeDuration
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled, sequence == triggerSequence else { return }
            popup.close()
        }
    }

    /// Cancels capture, request and notice timer; clears output from memory.
    private func cancelWork() {
        captureTask?.cancel()
        translationTask?.cancel()
        noticeTask?.cancel()
        renderTask?.cancel()
        translationTask = nil
        noticeTask = nil
        renderTask = nil
        anchor = nil
        request = nil
        state.dismiss()
    }
}
