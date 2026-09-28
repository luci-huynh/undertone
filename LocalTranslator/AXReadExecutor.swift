import Foundation
import ApplicationServices

/// The lock protects the only mutable state shared by the task and AX queue.
nonisolated final class AXReadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }

    func check() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }
}

nonisolated final class AXReadExecutor: Sendable {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue(label: "local.chienhuynh.LocalTranslator.ax", qos: .userInitiated)) {
        self.queue = queue
    }

    func read(_ operation: @escaping @Sendable (AXReadCancellation) throws -> FocusedElementReading) async -> FocusedElementReading {
        let cancellation = AXReadCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    let result: FocusedElementReading
                    do {
                        // Cancelled queued work never starts AX IPC. An active AX
                        // call finishes at its timeout, then the next check stops it.
                        try cancellation.check()
                        let reading = try operation(cancellation)
                        try cancellation.check()
                        result = reading
                    } catch is CancellationError {
                        result = FocusedElementReading(failure: .cancelled)
                    } catch {
                        result = FocusedElementReading(failure: .axError(AXError.failure.rawValue))
                    }
                    // Only this worker resumes the continuation, including cancellation.
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}
