import Foundation

/// Receives captured mono samples on the capture queue.
nonisolated protocol LiveAudioSink: AnyObject, Sendable {
    func append(_ samples: [Float], sampleRate: Double)
}

/// Sends every block to several sinks (ring buffer + speech recognizer).
nonisolated final class LiveAudioFanOut: LiveAudioSink, @unchecked Sendable {
    private let sinks: [any LiveAudioSink]
    init(_ sinks: [any LiveAudioSink]) { self.sinks = sinks }
    func append(_ samples: [Float], sampleRate: Double) {
        for sink in sinks { sink.append(samples, sampleRate: sampleRate) }
    }
}

/// Fixed-size mono sample buffer for the Live session (PLAN §24.1: bounded,
/// RAM only, freed on Stop). When full, the oldest samples are overwritten.
/// Written from the capture queue; lock-protected.
nonisolated final class LiveAudioRingBuffer: LiveAudioSink, @unchecked Sendable {
    let capacity: Int
    private let lock = NSLock()
    private var storage: [Float]
    private var start = 0
    private var stored = 0
    private var rate: Double = 0

    /// - Parameter capacity: maximum samples kept (e.g. 30 s × sample rate).
    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = [Float](repeating: 0, count: max(1, capacity))
    }

    static func seconds(_ seconds: Double, sampleRate: Double) -> LiveAudioRingBuffer {
        LiveAudioRingBuffer(capacity: Int(seconds * sampleRate))
    }

    var count: Int { lock.withLock { stored } }
    var sampleRate: Double { lock.withLock { rate } }
    var bufferedSeconds: Double { lock.withLock { rate > 0 ? Double(stored) / rate : 0 } }

    func append(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) {
        lock.withLock {
            guard !storage.isEmpty else { return } // cleared: the session ended
            rate = sampleRate
            for sample in samples.suffix(capacity) {
                storage[(start + stored) % capacity] = sample
                if stored < capacity {
                    stored += 1
                } else {
                    start = (start + 1) % capacity
                }
            }
        }
    }

    func append(_ samples: [Float], sampleRate: Double) {
        samples.withUnsafeBufferPointer { append($0, sampleRate: sampleRate) }
    }

    /// Oldest first.
    func snapshot() -> [Float] {
        lock.withLock { (0..<stored).map { storage[(start + $0) % capacity] } }
    }

    /// Drops all samples and the storage itself (Stop, close, quit).
    func clear() {
        lock.withLock {
            storage = []
            start = 0
            stored = 0
            rate = 0
        }
    }
}
