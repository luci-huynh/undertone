import Foundation
import Testing
@testable import Undertone

private func settle(_ condition: () -> Bool) async {
    for _ in 0..<300 where !condition() { await Task.yield() }
}

/// L06: Live recovers from device changes and wake; errors stay in Live.
@MainActor
struct LiveRecoveryTests {
    private func running() async -> (LiveSession, FakeLiveCapture, FakeTranscriber, FakeSystemEvents) {
        let capture = FakeLiveCapture()
        let transcriber = FakeTranscriber()
        let events = FakeSystemEvents()
        let session = LiveSession.fake(capture: capture, transcriber: transcriber, systemEvents: events)
        session.start()
        await session.startTask?.value
        return (session, capture, transcriber, events)
    }

    @Test func anOutputDeviceChangeRebuildsTheCaptureOnceAndKeepsSubtitles() async throws {
        let (session, capture, transcriber, events) = await running()
        transcriber.send(.final("Before the switch.", latency: nil))
        await settle { session.transcript.segments.count == 1 }
        // A headphone switch fires several property changes.
        events.send(.outputDeviceChanged)
        events.send(.outputDeviceChanged)
        events.send(.outputDeviceChanged)
        try await Task.sleep(for: .milliseconds(450))
        #expect(capture.startCount == 2)
        #expect(capture.stopCount == 1)
        #expect(session.captureRestarts == 1)
        #expect(capture.isCapturing)
        #expect(session.status.isRunning)
        #expect(session.transcript.segments.map(\.text) == ["Before the switch."])
        #expect(transcriber.stopCount == 0)
        // Audio still reaches the recognizer after the restart.
        capture.emit(rms: 0.2, samples: [0.5])
        #expect(transcriber.received.last == [0.5])
    }

    @Test func wakingFromSleepRebuildsTheCapture() async throws {
        let (session, capture, _, events) = await running()
        events.send(.didWake)
        try await Task.sleep(for: .milliseconds(450))
        #expect(capture.startCount == 2)
        #expect(session.captureRestarts == 1)
    }

    @Test func stoppingEndsListeningForSystemEvents() async throws {
        let (session, capture, _, events) = await running()
        #expect(events.isListening)
        session.stop()
        #expect(!events.isListening)
        events.send(.outputDeviceChanged)
        try await Task.sleep(for: .milliseconds(450))
        #expect(capture.startCount == 1)
    }

    @Test func aFailedRestartIsShownNotHidden() async throws {
        let (session, capture, transcriber, events) = await running()
        transcriber.send(.final("Still readable.", latency: nil))
        await settle { session.transcript.segments.count == 1 }
        capture.failure = .tapRefused(-1)
        events.send(.outputDeviceChanged)
        try await Task.sleep(for: .milliseconds(450))
        #expect(session.status == .failed(LiveCaptureError.tapRefused(-1).message))
        // L08: the session ends (no status tick paints it as listening again),
        // and what was on screen stays readable.
        await settle { transcriber.stopCount == 1 }
        #expect(transcriber.stopCount == 1)
        #expect(!capture.isCapturing)
        #expect(!events.isListening)
        session.refreshStatus()
        #expect(session.status == .failed(LiveCaptureError.tapRefused(-1).message))
        #expect(session.transcript.segments.map(\.text) == ["Still readable."])
    }

    @Test func eventsRightAfterARestartAreIgnoredThenHandledAgain() async throws {
        let clock = ManualClock()
        let capture = FakeLiveCapture()
        let events = FakeSystemEvents()
        let session = LiveSession.fake(capture: capture, systemEvents: events, clock: clock)
        session.start()
        await session.startTask?.value
        events.send(.outputDeviceChanged)
        try await Task.sleep(for: .milliseconds(450))
        #expect(session.captureRestarts == 1)
        // Our own rebuild can echo a device event; it must not restart again.
        events.send(.outputDeviceChanged)
        try await Task.sleep(for: .milliseconds(450))
        #expect(session.captureRestarts == 1)
        clock.advance(.seconds(2))
        events.send(.outputDeviceChanged)
        try await Task.sleep(for: .milliseconds(450))
        #expect(session.captureRestarts == 2)
    }

    @Test(arguments: [false, true])
    func recognitionEndingByItselfIsShownAndEndsCapture(throwing: Bool) async {
        let (session, capture, transcriber, events) = await running()
        transcriber.send(.final("Heard.", latency: nil))
        await settle { session.transcript.segments.count == 1 }
        transcriber.end(throwing: throwing ? LiveTranscriberError.formatUnavailable : nil)
        await settle { !session.status.isRunning }
        #expect(session.status == .failed("Speech recognition stopped. Press Start to try again."))
        #expect(!capture.isCapturing)
        #expect(!events.isListening)
        #expect(session.transcript.segments.map(\.text) == ["Heard."])
        // Start again works.
        session.start()
        await session.startTask?.value
        #expect(session.status.isRunning)
        #expect(session.transcript.isEmpty)
    }

    @Test func aStaleSessionNeverStopsTheNextSessionsRecognizer() async {
        let first = FakeTranscriber()
        first.holdsPrepare = true
        let second = FakeTranscriber()
        var made: [FakeTranscriber] = []
        let session = LiveSession.fake(makeTranscriber: {
            let next = made.isEmpty ? first : second
            made.append(next)
            return next
        })
        session.start()
        await settle { first.prepareCount == 1 }
        session.stop()
        session.start()
        await session.startTask?.value
        #expect(second.startCount == 1)
        first.releasePrepare()
        await settle { first.stopCount >= 2 }
        for _ in 0..<20 { await Task.yield() }
        #expect(first.startCount == 0)
        #expect(second.stopCount == 0)
        #expect(session.status.isRunning)
    }
}

/// L06 regression: ⌥T with Live off, running and just stopped; no cross-cancel.
@MainActor
struct TextWithLiveRegressionTests {
    enum LiveState: CaseIterable { case off, running, justStopped }

    private func snapshot(_ text: String) -> SelectionSnapshot {
        SelectionSnapshot(sourcePID: 7, sourceAppName: "Slack", text: text, range: nil, anchor: cursorTestAnchor, capturedAt: Date())
    }

    @Test(arguments: LiveState.allCases)
    func shortcutStreamsCompletesAndCancelsNormally(_ liveState: LiveState) async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("Hello world")), .success(snapshot("Second text"))]),
            translator: translator, popup: popup
        )
        let liveCapture = FakeLiveCapture()
        let live = LiveSession.fake(capture: liveCapture)
        let app = AppCoordinator.fake(flow: flow, live: live)
        app.start()
        if liveState != .off {
            live.start()
            await live.startTask?.value
        }
        if liveState == .justStopped { live.stop() }

        // ⌥T → stream → done.
        flow.trigger()
        await flow.captureTask?.value
        await settle { translator.inputs.count == 1 }
        translator.send("Xin ")
        translator.send("chào")
        translator.finish()
        await flow.translationTask?.value
        #expect(popup.current?.phase == .done)
        #expect(popup.current?.body == "Xin chào")
        #expect(popup.current?.canCopy == true)

        // A second ⌥T, then Close: that request is cancelled, nothing else.
        flow.trigger()
        await flow.captureTask?.value
        await settle { translator.inputs.count == 2 }
        popup.dismissByUser()
        await settle { translator.terminatedRequests == [1] }
        #expect(translator.terminatedRequests == [1])
        #expect(live.status.isRunning == (liveState == .running))
        #expect(liveCapture.stopCount == (liveState == .justStopped ? 1 : 0))
        app.shutdown()
    }

    @Test func closingThePopupDoesNotCancelLiveTranslationAndStoppingLiveDoesNotCancelText() async {
        let ollama = ScriptedLiveTranslate()
        let queue = LiveTranslationQueue(translate: { ollama.translate($0) }, isTextBusy: { false })
        let transcriber = FakeTranscriber()
        let live = LiveSession.fake(transcriber: transcriber, translations: queue)
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("Hello world"))]), translator: translator, popup: popup
        )
        let app = AppCoordinator.fake(flow: flow, live: live)
        app.start()
        live.start()
        await live.startTask?.value
        transcriber.send(.final("Live sentence.", latency: nil))
        await settle { ollama.inputs.count == 1 }

        flow.trigger()
        await flow.captureTask?.value
        await settle { translator.inputs.count == 1 }
        popup.dismissByUser()
        await settle { translator.terminatedRequests == [0] }
        #expect(ollama.terminated.isEmpty)

        flow.trigger()
        await flow.captureTask?.value
        await settle { translator.inputs.count == 2 }
        live.stop()
        await settle { ollama.terminated == [0] }
        #expect(translator.terminatedRequests == [0])
        #expect(popup.isVisible)
        app.shutdown()
    }

    @Test func shortcutDoesNotWaitForTheSpeechModel() async {
        let transcriber = FakeTranscriber()
        transcriber.holdsPrepare = true
        let live = LiveSession.fake(transcriber: transcriber)
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("Hello world"))]), translator: translator, popup: popup
        )
        let app = AppCoordinator.fake(flow: flow, live: live)
        app.start()
        live.start()
        #expect(live.status == .preparing(nil))
        flow.trigger()
        await flow.captureTask?.value
        await settle { translator.inputs.count == 1 }
        translator.send("Xin chào")
        translator.finish()
        await flow.translationTask?.value
        #expect(popup.current?.phase == .done)
        #expect(live.status == .preparing(nil))
        transcriber.releasePrepare()
        await live.startTask?.value
        app.shutdown()
    }
}
