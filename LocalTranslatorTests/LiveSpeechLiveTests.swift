import AVFoundation
import Foundation
import Testing
@testable import Undertone

/// Real on-device recognition through the app's adapter (L03). Runs only with
/// TEST_RUNNER_LT_LIVE_ASR=1 and TEST_RUNNER_LT_ASR_AUDIO=<dir> holding
/// synthetic `say` files; prints `ASR` lines (synthetic text only).
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LT_LIVE_ASR"] == "1"), .serialized)
struct LiveSpeechLiveTests {
    private var audioDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["LT_ASR_AUDIO"] ?? "/nonexistent")
    }

    /// Reads a file as 48 kHz mono Float32 like the tap delivers.
    private func tapSamples(_ name: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: audioDirectory.appendingPathComponent(name))
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let converter = try #require(AVAudioConverter(from: file.processingFormat, to: target))
        let source = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: source)
        let output = try #require(AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(file.length) * 48_000 / file.processingFormat.sampleRate) + 1024))
        var supplied = false
        converter.convert(to: output, error: nil) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return source
        }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }

    /// Feeds 10 ms blocks at real time, like a meeting, and collects results.
    @available(macOS 26.0, *)
    private func transcribe(_ samples: [Float], tail: Duration = .seconds(3)) async throws -> (finals: [String], volatiles: Int, latencies: LatencyRecorder) {
        let transcriber = SpeechAnalyzerTranscriber()
        try await transcriber.prepare { _ in }
        let (sink, events) = try await transcriber.start()
        var finals: [String] = []
        var volatiles = 0
        var latencies = LatencyRecorder()
        let collector = Task {
            for try await event in events {
                switch event {
                case .final(let text, let latency):
                    finals.append(text)
                    if let latency { latencies.record(latency) }
                case .volatile(_, let latency):
                    volatiles += 1
                    if let latency { latencies.record(latency) }
                }
            }
        }
        let block = 480
        var index = 0
        let clock = ContinuousClock()
        let start = clock.now
        while index < samples.count {
            let end = min(index + block, samples.count)
            sink.append(Array(samples[index..<end]), sampleRate: 48_000)
            index = end
            try await clock.sleep(until: start + .milliseconds(index / 48))
        }
        try await Task.sleep(for: tail)
        await transcriber.finalizeNow()
        try await Task.sleep(for: .seconds(1))
        await transcriber.stop()
        collector.cancel()
        return (finals, volatiles, latencies)
    }

    @Test func meetingSpeechBecomesEnglishSubtitles() async throws {
        guard #available(macOS 26.0, *) else { Issue.record("needs macOS 26"); return }
        let result = try await transcribe(tapSamples("long-sample.aiff"))
        let text = result.finals.joined(separator: " ")
        for final in result.finals { print("ASR\tfinal\t\(final)") }
        let p50 = result.latencies.percentile(0.5).map(LiveSession.ms) ?? -1
        let p95 = result.latencies.percentile(0.95).map(LiveSession.ms) ?? -1
        print("ASR\tstats\tfinals \(result.finals.count), volatile updates \(result.volatiles), latency p50 \(p50) ms, p95 \(p95) ms (\(result.latencies.samples.count))")
        for word in ["morning", "migration", "next week", "dashboard", "questions"] {
            #expect(text.localizedCaseInsensitiveContains(word), "missing “\(word)”")
        }
        #expect(result.volatiles > 0, "no partial subtitles before finals")
    }

    @Test func silenceProducesNoText() async throws {
        guard #available(macOS 26.0, *) else { Issue.record("needs macOS 26"); return }
        let result = try await transcribe([Float](repeating: 0, count: 48_000 * 5), tail: .seconds(1))
        let text = result.finals.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        print("ASR\tsilence\tfinals \(result.finals.count), volatiles \(result.volatiles), text chars \(text.count)")
        #expect(text.isEmpty)
    }
}
