import AVFoundation
import CoreMedia
import Foundation
import os
import Speech

/// One recognizer update. Text never leaves the process or reaches the logs.
nonisolated enum LiveTranscriptEvent: Equatable, Sendable {
    /// Still changing: replaces the previous volatile text.
    case volatile(String, latency: Duration?)
    /// Settled: becomes a segment; the volatile text before it is dropped.
    case final(String, latency: Duration?)
}

/// The English subtitle state of one Live session (PLAN §24.2): settled
/// segments with IDs plus the text still being recognized. Bounded: only the
/// newest `maxSegments` stay in RAM.
nonisolated struct LiveTranscript: Equatable, Sendable {
    struct Segment: Equatable, Identifiable, Sendable {
        let id: UUID
        let text: String
    }

    /// User decision L05: keep about 50 sentences.
    static let maxSegments = 50

    private(set) var segments: [Segment] = []
    private(set) var volatileText = ""

    var isEmpty: Bool { segments.isEmpty && volatileText.isEmpty }

    /// Applies an update; returns the new segment when one settled.
    @discardableResult
    mutating func apply(_ event: LiveTranscriptEvent) -> Segment? {
        switch event {
        case .volatile(let text, _):
            volatileText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return nil
        case .final(let text, _):
            volatileText = ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Silence or noise gives no text; no empty subtitle is created.
            guard !trimmed.isEmpty else { return nil }
            let segment = Segment(id: UUID(), text: trimmed)
            segments.append(segment)
            if segments.count > Self.maxSegments { segments.removeFirst(segments.count - Self.maxSegments) }
            return segment
        }
    }
}

/// Audio → subtitle latencies of the session, newest 200 (metadata only).
nonisolated struct LatencyRecorder: Sendable {
    private(set) var samples: [Duration] = []

    mutating func record(_ latency: Duration) {
        samples.append(latency)
        if samples.count > 200 { samples.removeFirst(samples.count - 200) }
    }

    func percentile(_ p: Double) -> Duration? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))
        return sorted[index]
    }
}

nonisolated enum LiveTranscriberError: Error, Equatable, Sendable {
    case unsupportedOS
    case languageUnavailable
    case modelUnavailable
    case formatUnavailable

    var message: String {
        switch self {
        case .unsupportedOS: "Live needs macOS 26 or later."
        case .languageUnavailable: "English speech recognition isn't available on this Mac."
        case .modelUnavailable: "The English speech model couldn't be installed. Try again when macOS can download it once; Live then works offline."
        case .formatUnavailable: "The speech recognizer rejected the audio format."
        }
    }
}

/// Local speech recognition for Live (L01 decision: Apple SpeechAnalyzer).
protocol LiveTranscribing: AnyObject {
    /// Makes sure the on-device English model is installed (may download once,
    /// system-managed; `progress` 0…1). Never falls back to a server.
    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws
    /// Starts recognition; audio goes into `sink`, updates come from `events`.
    func start() async throws -> (sink: any LiveAudioSink, events: AsyncThrowingStream<LiveTranscriptEvent, Error>)
    /// Ends the current utterance now (long monologue without a pause).
    func finalizeNow() async
    /// Stops at once; pending audio and results are discarded.
    func stop() async
}

final class UnsupportedLiveTranscriber: LiveTranscribing {
    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws { throw LiveTranscriberError.unsupportedOS }
    func start() async throws -> (sink: any LiveAudioSink, events: AsyncThrowingStream<LiveTranscriptEvent, Error>) {
        throw LiveTranscriberError.unsupportedOS
    }
    func finalizeNow() async {}
    func stop() async {}
}

/// SpeechTranscriber (progressive preset: volatile then final results) fed
/// with the tap audio converted to the analyzer's format. Probe on this Mac
/// (L03): en_US asset present, no Speech Recognition authorization needed,
/// 19.8 s of synthetic speech processed in 0.48 s.
@available(macOS 26.0, *)
final class SpeechAnalyzerTranscriber: LiveTranscribing {
    private let logger = Logger(subsystem: "local.chienhuynh.Undertone", category: "live")
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw LiveTranscriberError.languageUnavailable
        }
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        _ = try? await AssetInventory.reserve(locale: locale)
        if await AssetInventory.status(forModules: [module]) != .installed {
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    let watcher = Task { @MainActor in
                        while !Task.isCancelled {
                            progress(request.progress.fractionCompleted)
                            try? await Task.sleep(for: .milliseconds(250))
                        }
                    }
                    defer { watcher.cancel() }
                    try await request.downloadAndInstall()
                }
            } catch {
                logger.notice("Live speech model install failed: \(String(describing: type(of: error)), privacy: .public)")
                throw LiveTranscriberError.modelUnavailable
            }
            guard await AssetInventory.status(forModules: [module]) == .installed else { throw LiveTranscriberError.modelUnavailable }
        }
        transcriber = module
    }

    func start() async throws -> (sink: any LiveAudioSink, events: AsyncThrowingStream<LiveTranscriptEvent, Error>) {
        await stop()
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw LiveTranscriberError.languageUnavailable
        }
        // A fresh module per session: results never carry over between sessions.
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw LiveTranscriberError.formatUnavailable
        }
        let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        try await analyzer.prepareToAnalyze(in: format)
        // Bounded: if recognition falls behind, the oldest audio is dropped
        // instead of queueing without limit (PLAN §24.1).
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(256))
        try await analyzer.start(inputSequence: stream)
        let feed = AnalyzerFeed(format: format, continuation: continuation)

        // Generous so a final result is never pushed out while the consumer is busy.
        let (events, eventContinuation) = AsyncThrowingStream<LiveTranscriptEvent, Error>.makeStream(bufferingPolicy: .bufferingNewest(1_000))
        let task = Task {
            do {
                for try await result in module.results {
                    let text = String(result.text.characters)
                    let latency = feed.latency(forAudioTime: result.range.end)
                    eventContinuation.yield(result.isFinal ? .final(text, latency: latency) : .volatile(text, latency: latency))
                }
                eventContinuation.finish()
            } catch {
                eventContinuation.finish(throwing: error)
            }
        }
        eventContinuation.onTermination = { _ in task.cancel() }
        resultsTask = task
        self.transcriber = module
        self.analyzer = analyzer
        self.input = continuation
        logger.notice("Live speech recognition started: \(Int(format.sampleRate), privacy: .public) Hz, \(format.channelCount, privacy: .public) ch")
        return (feed, events)
    }

    func finalizeNow() async {
        try? await analyzer?.finalize(through: nil)
    }

    func stop() async {
        input?.finish()
        input = nil
        resultsTask?.cancel()
        resultsTask = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
            logger.notice("Live speech recognition stopped")
        }
        analyzer = nil
    }
}

/// Converts tap blocks (mono Float32 at the tap rate) to the analyzer format
/// and remembers when each stretch of audio was captured, so a result's audio
/// time maps back to wall time (audio → subtitle latency). Runs on the
/// capture queue.
@available(macOS 26.0, *)
nonisolated final class AnalyzerFeed: LiveAudioSink, @unchecked Sendable {
    /// When the source pauses (taps then deliver nothing), up to this much
    /// silence is inserted so the recognizer sees the pause between sentences.
    static let maxInsertedSilence: Double = 1.0

    private let format: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    /// Seconds of audio sent to the analyzer so far.
    private var streamSeconds: Double = 0
    private var lastBlockAt: ContinuousClock.Instant?
    /// (stream time at the end of a block, wall time it was captured), newest last.
    private var marks: [(Double, ContinuousClock.Instant)] = []

    init(format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.format = format
        self.continuation = continuation
    }

    func append(_ samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty else { return }
        let now = ContinuousClock.now
        lock.withLock {
            if let last = lastBlockAt {
                let gap = Double((now - last).components.seconds) + Double((now - last).components.attoseconds) / 1e18
                let expected = Double(samples.count) / sampleRate
                if gap > expected + 0.3 {
                    push([Float](repeating: 0, count: Int(min(gap, Self.maxInsertedSilence) * sampleRate)), sampleRate: sampleRate, capturedAt: now)
                }
            }
            lastBlockAt = now
            push(samples, sampleRate: sampleRate, capturedAt: now)
        }
    }

    /// How long after capture the audio at `time` produced a result.
    func latency(forAudioTime time: CMTime) -> Duration? {
        let seconds = time.seconds
        guard seconds.isFinite else { return nil }
        return lock.withLock {
            guard let mark = marks.first(where: { $0.0 >= seconds }) ?? marks.last else { return nil }
            return ContinuousClock.now - mark.1
        }
    }

    private func push(_ samples: [Float], sampleRate: Double, capturedAt: ContinuousClock.Instant) {
        if inputFormat?.sampleRate != sampleRate {
            inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
            converter = inputFormat.flatMap { AVAudioConverter(from: $0, to: format) }
        }
        guard let inputFormat, let converter,
              let source = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }

        let ratio = format.sampleRate / sampleRate
        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return source
        }
        guard error == nil, output.frameLength > 0 else { return }
        continuation.yield(AnalyzerInput(buffer: output))
        streamSeconds += Double(output.frameLength) / format.sampleRate
        marks.append((streamSeconds, capturedAt))
        if marks.count > 2_000 { marks.removeFirst(marks.count - 2_000) }
    }
}
