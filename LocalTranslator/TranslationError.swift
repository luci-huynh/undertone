import Foundation

/// Every way a translation request can end without a full result, with its
/// popup text and recovery (runbook S23). Cancellation by the user (close,
/// new ⌥T, ⇄, Retry) is not an error and never reaches here.
nonisolated enum TranslationError: Equatable, Sendable {
    /// PLAN §14 “Ollama is not running.” [Retry]; also when it quits mid-stream.
    case runtimeUnavailable
    /// PLAN §14 “Translation model is not installed.” No download, no retry.
    case modelMissing
    /// No first token within `StreamWatchdog` first-token limit (model load).
    case coldStartTimeout
    /// Output started, then nothing within the stall limit.
    case stalled
    /// Ollama answered with something that is not its stream format.
    case malformedResponse
    /// The stream ended early (no `done`) or was cancelled by the system.
    case interrupted
    /// Ollama reported an error (e.g. not enough memory); its own text, if any.
    /// A request Ollama rejected (HTTP 4xx, e.g. a model that can't chat)
    /// fails the same way again, so it offers no Retry (L08 review).
    case ollama(message: String?, retryable: Bool = true)
    case emptyOutput
    /// Not sent: longer than the context budget (S22).
    case inputTooLong
    /// Ollama filled the context window; partial output kept (S22).
    case outputTruncated
    /// Endpoint not on this Mac or a cloud model tag: nothing was sent.
    case notLocal
    /// Anything else.
    case unavailable

    init(_ error: Error) {
        switch error {
        case OllamaError.runtimeUnavailable: self = .runtimeUnavailable
        case OllamaError.modelMissing: self = .modelMissing
        case OllamaError.coldStartTimeout: self = .coldStartTimeout
        case OllamaError.streamStalled: self = .stalled
        case OllamaError.malformedStream, OllamaError.invalidResponse: self = .malformedResponse
        case OllamaError.incompleteStream, is CancellationError: self = .interrupted
        case OllamaError.http(let status, let message):
            self = .ollama(message: message, retryable: !(400..<500).contains(status) || status == 408 || status == 429)
        case OllamaError.emptyOutput: self = .emptyOutput
        case OllamaError.inputTooLong: self = .inputTooLong
        case OllamaError.outputTruncated: self = .outputTruncated
        case OllamaError.endpointRejected, OllamaError.cloudModelRejected: self = .notLocal
        default: self = .unavailable
        }
    }

    var message: String {
        switch self {
        case .runtimeUnavailable: "Ollama is not running."
        case .modelMissing: "Translation model is not installed."
        case .coldStartTimeout: "The model took too long to start."
        case .stalled: "Ollama stopped responding."
        case .malformedResponse: "Ollama sent an unexpected response."
        case .interrupted: "The translation was interrupted."
        case .ollama(let message, _): Self.ollamaMessage(message)
        case .emptyOutput: "No translation returned."
        case .inputTooLong: "Selected text is too long to translate at once."
        case .outputTruncated: "Translation stopped early: the text is too long."
        case .notLocal: "Only a local Ollama and local models are allowed. Check Settings."
        case .unavailable: "Translation failed."
        }
    }

    /// One user-initiated retry of the same request; never automatic. Not
    /// offered where the same request would fail the same way.
    var allowsRetry: Bool {
        switch self {
        case .ollama(_, let retryable): retryable
        case .runtimeUnavailable, .coldStartTimeout, .stalled, .malformedResponse, .interrupted, .emptyOutput, .unavailable: true
        case .modelMissing, .inputTooLong, .outputTruncated, .notLocal: false
        }
    }

    /// Category for metadata logs; never includes text or Ollama's message.
    var logLabel: String {
        switch self {
        case .runtimeUnavailable: "runtimeUnavailable"
        case .modelMissing: "modelMissing"
        case .coldStartTimeout: "coldStartTimeout"
        case .stalled: "stalled"
        case .malformedResponse: "malformedResponse"
        case .interrupted: "interrupted"
        case .ollama: "ollamaError"
        case .emptyOutput: "emptyOutput"
        case .inputTooLong: "inputTooLong"
        case .outputTruncated: "outputTruncated"
        case .notLocal: "notLocal"
        case .unavailable: "unavailable"
        }
    }

    /// Ollama's own reason, single line and short, so the popup stays small.
    private static func ollamaMessage(_ message: String?) -> String {
        let line = (message ?? "").split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return "Ollama reported an error." }
        return "Ollama: " + (line.count > 120 ? line.prefix(119) + "…" : line)
    }
}

extension SelectionFailure {
    /// Popup message per docs/COMPATIBILITY.md; nil means no popup.
    var popupMessage: String? {
        switch self {
        case .noSelection: "No text selected."
        case .permissionMissing: "Undertone needs Accessibility permission to read selected text."
        case .unsupported, .noFocusedElement, .axError: "Can't read selected text in this app."
        case .secureInput: "Secure input is on. Selected text isn't read."
        case .timedOut: "The app didn't respond. Try again."
        case .selectionChanged: "The selection changed. Try again."
        case .focusChanged, .cancelled, .sourceIsSelf, .noFrontmostApp: nil
        }
    }

    var popupAction: PopupContent.Action? {
        self == .permissionMissing ? .openAccessibilitySettings : nil
    }
}

/// Separates a slow model start from a stream that stops (runbook S23).
/// Limits come from measurements on this Mac (docs/PROGRESS.md S23): first
/// token ≤ 6.3 s cold, ≤ 3.1 s warm with a 4.9 KB selection; longest gap
/// between deltas 163 ms. There is no total limit: a long selection
/// legitimately streams for about two minutes. Time asleep does not count
/// (SuspendingClock): a stream that resumes after wake is not a stall.
nonisolated enum StreamWatchdog {
    static let firstTokenLimit: Duration = .seconds(60)
    static let stallLimit: Duration = .seconds(15)

    /// Passes `upstream` through; cancels it and throws `coldStartTimeout`
    /// when nothing arrives within `first`, or `streamStalled` when a later
    /// gap exceeds `between`.
    static func watch<Element: Sendable>(
        _ upstream: AsyncThrowingStream<Element, Error>,
        first: Duration = firstTokenLimit,
        between: Duration = stallLimit
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let activity = Activity()
            let reader = Task {
                do {
                    for try await element in upstream {
                        activity.record()
                        continuation.yield(element)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let timer = Task {
                while !Task.isCancelled {
                    let (count, last) = activity.snapshot
                    let deadline = last + (count == 0 ? first : between)
                    if SuspendingClock.now >= deadline {
                        // Publish the error before cancellation can end the reader
                        // normally. onTermination then cancels both tasks.
                        continuation.finish(throwing: count == 0 ? OllamaError.coldStartTimeout : OllamaError.streamStalled)
                        return
                    }
                    // ponytail: at most 100 ms polling delay (plus scheduling);
                    // use an activity wake-up if tighter timeout precision is needed.
                    let nextCheck = min(deadline, SuspendingClock.now + .milliseconds(100))
                    try? await Task.sleep(until: nextCheck, clock: .suspending)
                }
            }
            continuation.onTermination = { _ in
                reader.cancel()
                timer.cancel()
            }
        }
    }

    private final class Activity: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var last = SuspendingClock.now

        var snapshot: (Int, SuspendingClock.Instant) { lock.withLock { (count, last) } }

        func record() {
            lock.withLock {
                count += 1
                last = .now
            }
        }
    }
}
