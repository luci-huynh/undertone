import AppKit
import SwiftUI
import Testing
@testable import Undertone

/// Renders the Live window to PNG for visual review (L05). Runs only with
/// TEST_RUNNER_LT_RENDER_DIR=<dir>; synthetic text only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LT_RENDER_DIR"] != nil))
struct LiveRenderTests {
    @Test func renderLiveWindow() async throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LT_RENDER_DIR"]!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let vietnamese = [
            "Good morning, everyone.": "Chào buổi sáng, mọi người.",
            "The payment service migration is almost done, and we expect to finish it sometime next week.": "Quá trình chuyển đổi hệ thống thanh toán đã gần hoàn tất, và chúng tôi dự kiến sẽ hoàn thành nó vào khoảng tuần tới.",
        ]
        let queue = LiveTranslationQueue(translate: { text in
            AsyncThrowingStream { continuation in
                if let vi = vietnamese[text] { continuation.yield(vi); continuation.finish() }
                // Other sentences stay “translating”/“waiting” for the picture.
            }
        }, isTextBusy: { false })
        let transcriber = FakeTranscriber()
        let session = LiveSession.fake(transcriber: transcriber, translations: queue)
        session.source = .chrome
        session.start()
        await session.startTask?.value
        for text in ["Good morning, everyone.", "The payment service migration is almost done, and we expect to finish it sometime next week."] {
            transcriber.send(.final(text, latency: nil))
            for _ in 0..<100 { await Task.yield() }
        }
        transcriber.send(.final("However, the reporting dashboard still has two open bugs.", latency: nil))
        for _ in 0..<50 { await Task.yield() }
        transcriber.send(.final("Sarah will look into the currency conversion issue.", latency: nil))
        transcriber.send(.volatile("Any questions before we", latency: nil))
        for _ in 0..<100 { await Task.yield() }

        for scheme in [ColorScheme.light, .dark] {
            let view = LiveWindowView(session: session)
                .frame(width: 520, height: 420)
                .background(scheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
                .environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = CGRect(x: 0, y: 0, width: 520, height: 420)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: dir.appendingPathComponent("live-\(scheme == .dark ? "dark" : "light").png"))
        }
        session.stop()
    }

    /// L08: the problem states at the narrowest window — no audio arriving
    /// (with its System Settings button) and Ollama down (with Open Ollama).
    @Test func renderLiveWindowProblems() async throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LT_RENDER_DIR"]!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let queue = LiveTranslationQueue(translate: { text in
            AsyncThrowingStream { continuation in
                if text.hasPrefix("Good") { continuation.yield("Chào buổi sáng, mọi người."); continuation.finish() }
                else { continuation.finish(throwing: OllamaError.runtimeUnavailable) }
            }
        }, isTextBusy: { false })
        let transcriber = FakeTranscriber()
        let clock = ManualClock()
        let processes = FakeProcessList([LiveAudioProcess(bundleID: "com.microsoft.teams2", isPlaying: true)])
        let session = LiveSession.fake(transcriber: transcriber, translations: queue, processes: processes, clock: clock)
        session.source = .teams
        session.start()
        await session.startTask?.value
        for text in ["Good morning, everyone.", "Let's review the release checklist first."] {
            transcriber.send(.final(text, latency: nil))
            for _ in 0..<100 { await Task.yield() }
        }
        clock.advance(.seconds(5))
        session.refreshStatus()

        for scheme in [ColorScheme.light, .dark] {
            let view = LiveWindowView(session: session)
                .frame(width: 420, height: 360)
                .background(scheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
                .environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = CGRect(x: 0, y: 0, width: 420, height: 360)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: dir.appendingPathComponent("live-problems-\(scheme == .dark ? "dark" : "light").png"))
        }
        #expect(session.status == .noAudioReceived)
        session.stop()
    }
}
