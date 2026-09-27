import Foundation

/// Pure lifecycle seam; no AX, shortcut, popup, task or transport implementation.
@MainActor
final class TranslationStateMachine {
    enum Phase: Equatable {
        case idle, loading, streaming, success, error, cancelled
    }

    enum Failure: Equatable {
        case unavailable, emptyOutput
    }

    private(set) var phase: Phase = .idle
    private(set) var requestID: UUID?
    private(set) var output = ""
    private(set) var failure: Failure?

    @discardableResult
    func begin() -> UUID {
        let id = UUID()
        requestID = id
        output = ""
        failure = nil
        phase = .loading
        return id
    }

    func receive(_ delta: String, for id: UUID) {
        guard accepts(id), !delta.isEmpty else { return }
        output += delta
        phase = .streaming
    }

    func complete(for id: UUID) {
        guard accepts(id) else { return }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fail(.emptyOutput, for: id)
        } else {
            phase = .success
        }
    }

    func fail(_ reason: Failure, for id: UUID) {
        guard accepts(id) else { return }
        failure = reason
        phase = .error
    }

    func cancel() {
        guard phase == .loading || phase == .streaming else { return }
        requestID = nil
        output = ""
        failure = nil
        phase = .cancelled
    }

    func dismiss() {
        requestID = nil
        output = ""
        failure = nil
        phase = .idle
    }

    private func accepts(_ id: UUID) -> Bool {
        requestID == id && (phase == .loading || phase == .streaming)
    }
}
