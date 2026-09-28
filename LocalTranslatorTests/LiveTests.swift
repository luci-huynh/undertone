import CoreAudio
import Foundation
import Testing
@testable import Undertone

/// L02: source matching, bounded buffer, Start/Stop lifecycle, status, and
/// independence from the text flow. Real capture is a manual check.
struct LiveSourceTests {
    @Test func chromeIsTheAppAndItsHelpersOnly() {
        #expect(LiveSource.chrome.owns(bundleID: "com.google.Chrome"))
        #expect(LiveSource.chrome.owns(bundleID: "com.google.Chrome.helper"))
        #expect(LiveSource.chrome.owns(bundleID: "com.google.Chrome.helper.renderer"))
        for other in ["com.google.Chrome.canary", "com.brave.Browser.helper", "com.apple.Safari", "com.google.ChromeRemoteDesktop"] {
            #expect(!LiveSource.chrome.owns(bundleID: other), "\(other)")
        }
    }

    @Test func slackAndTeamsMatchTheirOwnProcesses() {
        #expect(LiveSource.slack.owns(bundleID: "com.tinyspeck.slackmacgap.helper"))
        #expect(!LiveSource.slack.owns(bundleID: "com.tinyspeck.other"))
        #expect(LiveSource.teams.owns(bundleID: "com.microsoft.teams2"))
        #expect(LiveSource.teams.owns(bundleID: "com.microsoft.teams2.helper"))
        #expect(!LiveSource.teams.owns(bundleID: "com.microsoft.teams"))
        #expect(!LiveSource.teams.owns(bundleID: "com.microsoft.Outlook"))
    }

    @Test func tapListHasKnownHelpersPlusRunningMatchesAndNothingElse() {
        let running = [
            LiveAudioProcess(bundleID: "com.google.Chrome.helper.renderer", isPlaying: true),
            LiveAudioProcess(bundleID: "com.brave.Browser.helper", isPlaying: true),
            LiveAudioProcess(bundleID: "com.apple.Music", isPlaying: true),
        ]
        #expect(LiveSource.chrome.tapBundleIDs(running: running) == ["com.google.Chrome", "com.google.Chrome.helper", "com.google.Chrome.helper.renderer"])
        #expect(LiveSource.slack.tapBundleIDs(running: []) == ["com.tinyspeck.slackmacgap", "com.tinyspeck.slackmacgap.helper"])
    }
}

/// L08 review: the aggregate's clock device must not bring a microphone
/// into the IO buffers, and only the tap's streams are read.
struct LiveClockAndTapTests {
    private func candidate(_ uid: String, inputs: Int, isDefault: Bool = false) -> ClockCandidate {
        ClockCandidate(uid: uid, inputStreams: inputs, isDefault: isDefault)
    }

    @Test func anOutputOnlyDeviceClocksTheAggregateDefaultFirst() {
        let speakers = candidate("speakers", inputs: 0)
        let display = candidate("display", inputs: 0, isDefault: true)
        let headset = candidate("headset", inputs: 1, isDefault: true)
        #expect(ClockDeviceChooser.choose(from: [speakers, display]) == display)
        #expect(ClockDeviceChooser.choose(from: [headset, speakers]) == speakers)
        #expect(ClockDeviceChooser.choose(from: [headset]) == headset)
        #expect(ClockDeviceChooser.choose(from: []) == nil)
    }

    private func bufferList(_ channels: [[Float]]) -> UnsafeMutableAudioBufferListPointer {
        let list = AudioBufferList.allocate(maximumBuffers: channels.count)
        for (index, samples) in channels.enumerated() {
            let data = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
            data.initialize(from: samples, count: samples.count)
            list[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(samples.count * 4), mData: UnsafeMutableRawPointer(data))
        }
        return list
    }

    private func format(channels: UInt32, interleaved: Bool) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | (interleaved ? 0 : kAudioFormatFlagIsNonInterleaved),
            mBytesPerPacket: 4 * (interleaved ? channels : 1), mFramesPerPacket: 1, mBytesPerFrame: 4 * (interleaved ? channels : 1),
            mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0
        )
    }

    @Test func onlyTheTapStreamsAreReadAfterTheClockDevicesInputs() throws {
        guard #available(macOS 26.0, *) else { return }
        let list = bufferList([[9, 9, 9, 9], [0.1, 0.2, 0.3, 0.4]])
        defer { for buffer in list { buffer.mData?.deallocate() }; free(list.unsafeMutablePointer) }
        let mono = try #require(CoreAudioTapCapture.tapMono(UnsafePointer(list.unsafePointer), format: format(channels: 1, interleaved: false), skippingStreams: 1))
        #expect(mono == [0.1, 0.2, 0.3, 0.4])
        #expect(CoreAudioTapCapture.tapMono(UnsafePointer(list.unsafePointer), format: format(channels: 1, interleaved: false), skippingStreams: 2) == nil)
    }

    @Test func interleavedStereoIsMixedToMono() throws {
        guard #available(macOS 26.0, *) else { return }
        let list = bufferList([[1, 3, 2, 4]])
        defer { for buffer in list { buffer.mData?.deallocate() }; free(list.unsafeMutablePointer) }
        let mono = try #require(CoreAudioTapCapture.tapMono(UnsafePointer(list.unsafePointer), format: format(channels: 2, interleaved: true), skippingStreams: 0))
        #expect(mono == [2, 3])
    }
}

struct LiveAudioRingBufferTests {
    @Test func keepsAtMostItsCapacityAndDropsTheOldest() {
        let buffer = LiveAudioRingBuffer(capacity: 4)
        buffer.append([1, 2, 3], sampleRate: 4)
        buffer.append([4, 5, 6], sampleRate: 4)
        #expect(buffer.count == 4)
        #expect(buffer.snapshot() == [3, 4, 5, 6])
        #expect(buffer.bufferedSeconds == 1)
    }

    @Test func aBlockLargerThanTheBufferKeepsItsNewestPart() {
        let buffer = LiveAudioRingBuffer(capacity: 3)
        buffer.append([1, 2, 3, 4, 5], sampleRate: 1)
        #expect(buffer.snapshot() == [3, 4, 5])
    }

    @Test func clearFreesEverything() {
        let buffer = LiveAudioRingBuffer.seconds(30, sampleRate: 48_000)
        #expect(buffer.capacity == 1_440_000)
        buffer.append([Float](repeating: 0.5, count: 48_000), sampleRate: 48_000)
        buffer.clear()
        #expect(buffer.count == 0)
        #expect(buffer.snapshot().isEmpty)
        #expect(buffer.bufferedSeconds == 0)
    }
}

@MainActor
struct LiveSessionTests {
    private let chromePlaying = LiveAudioProcess(bundleID: "com.google.Chrome.helper", isPlaying: true)
    private let chromeQuiet = LiveAudioProcess(bundleID: "com.google.Chrome.helper", isPlaying: false)

    @Test func nothingIsCapturedBeforeStart() {
        let capture = FakeLiveCapture()
        let session = LiveSession.fake(capture: capture)
        #expect(session.status == .idle)
        #expect(capture.startCount == 0)
        #expect(session.buffer == nil)
    }

    @Test func startTapsTheChosenSourceAndSoundMeansListening() async {
        let capture = FakeLiveCapture()
        let processes = FakeProcessList([chromePlaying])
        let session = LiveSession.fake(capture: capture, processes: processes)
        session.source = .chrome
        session.start()
        await session.startTask?.value
        #expect(capture.bundleIDs == ["com.google.Chrome", "com.google.Chrome.helper"])
        capture.emit(rms: 0.2)
        session.refreshStatus()
        #expect(session.status == .listening)
        #expect(session.level > 0.5)
        #expect(session.bufferedSeconds > 0)
    }

    @Test func stopEndsCaptureAndFreesTheBuffer() async {
        let capture = FakeLiveCapture()
        let session = LiveSession.fake(capture: capture, processes: FakeProcessList([chromePlaying]))
        session.start()
        await session.startTask?.value
        capture.emit(rms: 0.2)
        let buffer = session.buffer
        session.stop()
        #expect(capture.stopCount == 1)
        #expect(!capture.isCapturing)
        #expect(session.status == .idle)
        #expect(session.buffer == nil)
        #expect(buffer?.count == 0)
        #expect(session.level == 0)
    }

    @Test func levelsFromAStoppedSessionAreIgnored() async {
        let capture = FakeLiveCapture()
        let session = LiveSession.fake(capture: capture)
        session.start()
        await session.startTask?.value
        let lateLevel = capture
        session.stop()
        lateLevel.emit(rms: 0.5)
        #expect(session.level == 0)
        #expect(session.status == .idle)
    }

    @Test func repeatedStartStopNeverLeaksACapture() async {
        let capture = FakeLiveCapture()
        let session = LiveSession.fake(capture: capture)
        for _ in 0..<20 {
            session.start()
            await session.startTask?.value
            session.start() // second press while running does nothing
            session.stop()
        }
        #expect(capture.startCount == 20)
        #expect(!capture.isCapturing)
        #expect(session.buffer == nil)
    }

    @Test func refusedTapShowsWhatToAllow() async {
        let capture = FakeLiveCapture()
        capture.failure = .tapRefused(-1)
        let session = LiveSession.fake(capture: capture)
        session.start()
        await session.startTask?.value
        #expect(session.status == .failed(LiveCaptureError.tapRefused(-1).message))
        #expect(session.status.label.contains("System Audio Recording"))
        #expect(session.buffer == nil)
        // Start is possible again after allowing it.
        capture.failure = nil
        session.start()
        await session.startTask?.value
        #expect(session.status.isRunning)
    }

    @Test func olderMacOSExplainsTheRequirement() async {
        let session = LiveSession(capture: UnsupportedLiveCapture(), transcriber: { FakeTranscriber() }, translations: LiveTranslationQueue(translate: { _ in AsyncThrowingStream { $0.finish() } }, isTextBusy: { false }), processes: FakeProcessList(), settings: MemoryLiveSettings())
        session.start()
        await session.startTask?.value
        #expect(session.status == .failed("Live needs macOS 26 or later."))
    }

    @Test func sourceNotRunningSilentAndBlockedAreDistinct() async {
        let clock = ManualClock()
        let capture = FakeLiveCapture()
        let processes = FakeProcessList([])
        let session = LiveSession.fake(capture: capture, processes: processes, clock: clock)
        session.source = .chrome
        session.start()
        await session.startTask?.value
        #expect(session.status == .sourceNotRunning)

        processes.processes = [chromeQuiet]
        session.refreshStatus()
        #expect(session.status == .silent)

        // Chrome starts playing: not blocked yet (audio arrives with a delay).
        processes.processes = [chromePlaying]
        session.refreshStatus()
        #expect(session.status == .silent)
        // Still playing after more than 4 s and not one block arrived → blocked.
        clock.advance(.seconds(5))
        session.refreshStatus()
        #expect(session.status == .noAudioReceived)

        capture.emit(rms: 0.1)
        session.refreshStatus()
        #expect(session.status == .listening)

        // Sound stops: back to silent after the 1.5 s window.
        processes.processes = [chromeQuiet]
        clock.advance(.seconds(2))
        session.refreshStatus()
        #expect(session.status == .silent)
    }

    @Test func silentBlocksWhileTheSourceKeepsItsStreamOpenAreNotAnError() async {
        let clock = ManualClock()
        let capture = FakeLiveCapture()
        let processes = FakeProcessList([chromePlaying])
        let session = LiveSession.fake(capture: capture, processes: processes, clock: clock)
        session.source = .chrome
        session.start()
        await session.startTask?.value
        session.refreshStatus()
        for _ in 0..<10 {
            clock.advance(.seconds(1))
            capture.emit(rms: 0)
            session.refreshStatus()
        }
        #expect(session.status == .silent)
    }

    @Test func sourceChoiceIsStoredButNotChangedWhileRunning() {
        let settings = MemoryLiveSettings()
        let session = LiveSession(capture: FakeLiveCapture(), transcriber: { FakeTranscriber() }, translations: LiveTranslationQueue(translate: { _ in AsyncThrowingStream { $0.finish() } }, isTextBusy: { false }), processes: FakeProcessList(), settings: settings)
        session.source = .slack
        #expect(settings.source == .slack)
    }

    @Test func defaultSourceIsTeams() {
        let suite = "local.chienhuynh.Undertone.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = UserDefaultsLiveSettings(defaults: defaults)
        #expect(settings.source == .teams)
        #expect(settings.keepsWindowOnTop)
        settings.source = .chrome
        settings.keepsWindowOnTop = false
        #expect(UserDefaultsLiveSettings(defaults: defaults).source == .chrome)
        #expect(!UserDefaultsLiveSettings(defaults: defaults).keepsWindowOnTop)
    }
}

/// PLAN §24.3: the two features are independent.
@MainActor
struct LiveIndependenceTests {
    @Test func shortcutWorksWhileLiveRunsAndDoesNotStopIt() async {
        let shortcut = GlobalShortcutService.fake()
        let popup = FakePopupPresenter()
        let flow = TranslationCoordinator.fake(popup: popup)
        let capture = FakeLiveCapture()
        let live = LiveSession.fake(capture: capture)
        let app = AppCoordinator.fake(shortcut: shortcut, flow: flow, live: live)
        app.start()
        live.start()
        await live.startTask?.value

        shortcut.onTrigger?()
        await flow.captureTask?.value
        #expect(popup.current?.body == "No text selected.")
        #expect(live.status.isRunning)
        #expect(capture.stopCount == 0)

        popup.dismissByUser()
        #expect(live.status.isRunning)
    }

    @Test func stoppingLiveLeavesTheTextPopupAlone() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(SelectionSnapshot(sourcePID: 1, sourceAppName: nil, text: "Hello world", range: nil, anchor: cursorTestAnchor, capturedAt: Date()))]),
            translator: translator, popup: popup
        )
        let live = LiveSession.fake()
        let app = AppCoordinator.fake(flow: flow, live: live)
        live.start()
        await live.startTask?.value
        flow.trigger()
        await flow.captureTask?.value
        for _ in 0..<50 where translator.inputs.isEmpty { await Task.yield() }
        live.stop()
        #expect(popup.isVisible)
        #expect(translator.terminatedRequests.isEmpty)
        _ = app
    }

    @Test func quitStopsLive() async {
        let capture = FakeLiveCapture()
        let live = LiveSession.fake(capture: capture)
        let app = AppCoordinator.fake(live: live)
        app.start()
        live.start()
        await live.startTask?.value
        app.shutdown()
        #expect(!capture.isCapturing)
        #expect(live.status == .idle)
    }
}

/// L03: subtitles from the recognizer, bounded and per session.
struct LiveTranscriptTests {
    @Test func volatileTextIsReplacedByTheFinalSegment() {
        var transcript = LiveTranscript()
        transcript.apply(.volatile("We expect", latency: nil))
        transcript.apply(.volatile("We expect the migration", latency: nil))
        #expect(transcript.volatileText == "We expect the migration")
        let segment = transcript.apply(.final(" We expect the migration to finish. ", latency: nil))
        #expect(segment?.text == "We expect the migration to finish.")
        #expect(transcript.segments.map(\.text) == ["We expect the migration to finish."])
        #expect(transcript.volatileText.isEmpty)
    }

    @Test func silenceCreatesNoSubtitle() {
        var transcript = LiveTranscript()
        #expect(transcript.apply(.final("   ", latency: nil)) == nil)
        #expect(transcript.isEmpty)
    }

    @Test func onlyTheNewestSegmentsStayInMemory() {
        var transcript = LiveTranscript()
        #expect(LiveTranscript.maxSegments == 50) // user decision L05
        for index in 0..<60 { transcript.apply(.final("Sentence \(index).", latency: nil)) }
        #expect(transcript.segments.count == LiveTranscript.maxSegments)
        #expect(transcript.segments.first?.text == "Sentence 10.")
        #expect(Set(transcript.segments.map(\.id)).count == LiveTranscript.maxSegments)
    }

    @Test func latencyPercentiles() {
        var recorder = LatencyRecorder()
        for ms in [100, 200, 300, 400, 1_000] { recorder.record(.milliseconds(ms)) }
        #expect(recorder.percentile(0.5) == .milliseconds(300))
        #expect(recorder.percentile(0.95) == .milliseconds(1_000))
        for _ in 0..<300 { recorder.record(.milliseconds(1)) }
        #expect(recorder.samples.count == 200)
    }
}

@MainActor
struct LiveSpeechSessionTests {
    private func running(_ transcriber: FakeTranscriber? = nil, clock: ManualClock = ManualClock()) async -> (LiveSession, FakeLiveCapture, FakeTranscriber) {
        let transcriber = transcriber ?? FakeTranscriber()
        let capture = FakeLiveCapture()
        let session = LiveSession.fake(capture: capture, transcriber: transcriber, clock: clock)
        session.start()
        await session.startTask?.value
        return (session, capture, transcriber)
    }

    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    @Test func startPreparesTheModelThenListensAndFeedsTheRecognizer() async {
        let (session, capture, transcriber) = await running()
        #expect(transcriber.prepareCount == 1)
        #expect(transcriber.startCount == 1)
        #expect(capture.startCount == 1)
        capture.emit(rms: 0.2, samples: [0.1, 0.2, 0.3])
        #expect(transcriber.received == [[0.1, 0.2, 0.3]])
        #expect(session.bufferedSeconds > 0)
    }

    @Test func subtitlesUpdateWhileListeningAndNeverWaitForTranslation() async {
        let (session, _, transcriber) = await running()
        transcriber.send(.volatile("Good morning", latency: .milliseconds(400)))
        await settle { session.transcript.volatileText == "Good morning" }
        #expect(session.transcript.volatileText == "Good morning")
        transcriber.send(.final("Good morning, everyone.", latency: .milliseconds(600)))
        await settle { session.transcript.segments.count == 1 }
        #expect(session.transcript.segments.map(\.text) == ["Good morning, everyone."])
        #expect(session.latencies.samples == [.milliseconds(400), .milliseconds(600)])
    }

    @Test func stopClearsSubtitlesStopsRecognitionAndDropsLateResults() async {
        let (session, capture, transcriber) = await running()
        transcriber.send(.final("First.", latency: nil))
        await settle { session.transcript.segments.count == 1 }
        session.stop()
        #expect(session.transcript.isEmpty)
        #expect(!capture.isCapturing)
        await settle { transcriber.stopCount >= 1 }
        #expect(transcriber.stopCount >= 1)
        transcriber.send(.final("Late.", latency: nil))
        for _ in 0..<20 { await Task.yield() }
        #expect(session.transcript.isEmpty)
    }

    @Test func modelProgressIsShownAndFailureNeverFallsBackToACloud() async {
        let transcriber = FakeTranscriber()
        transcriber.progressSteps = [0.25]
        transcriber.prepareFailure = .modelUnavailable
        let capture = FakeLiveCapture()
        let session = LiveSession.fake(capture: capture, transcriber: transcriber)
        session.start()
        #expect(session.status == .preparing(nil))
        await session.startTask?.value
        #expect(session.status == .failed(LiveTranscriberError.modelUnavailable.message))
        #expect(capture.startCount == 0)
    }

    @Test func stopDuringModelPreparationStartsNothing() async {
        let transcriber = FakeTranscriber()
        let capture = FakeLiveCapture()
        let session = LiveSession.fake(capture: capture, transcriber: transcriber)
        session.start()
        session.stop()
        await session.startTask?.value
        for _ in 0..<20 { await Task.yield() }
        #expect(capture.startCount == 0)
        #expect(session.status == .idle)
    }

    @Test func aLongMonologueIsClosedIntoASegment() async {
        let clock = ManualClock()
        let (session, _, transcriber) = await running(clock: clock)
        transcriber.send(.volatile("And then", latency: nil))
        await settle { !session.transcript.volatileText.isEmpty }
        clock.advance(.seconds(13))
        transcriber.send(.volatile("And then we kept talking without a pause", latency: nil))
        await settle { transcriber.finalizeCount == 1 }
        #expect(transcriber.finalizeCount == 1)

        transcriber.send(.volatile(String(repeating: "word ", count: 50), latency: nil))
        await settle { transcriber.finalizeCount == 2 }
        #expect(transcriber.finalizeCount == 2)
    }

    @Test func closingASentenceNeverHoldsUpLaterResults() async {
        let transcriber = FakeTranscriber()
        transcriber.holdsFinalize = true
        let (session, _, _) = await running(transcriber)
        transcriber.send(.volatile(String(repeating: "word ", count: 50), latency: nil))
        await settle { transcriber.finalizeCount == 1 }
        transcriber.send(.final("Settled.", latency: nil))
        await settle { session.transcript.segments.count == 1 }
        #expect(session.transcript.segments.map(\.text) == ["Settled."])
        transcriber.releaseFinalize()
    }

    @Test func aPauseWithoutAudioClosesThePendingSentenceOnce() async {
        let clock = ManualClock()
        let (session, capture, transcriber) = await running(clock: clock)
        capture.emit(rms: 0.2)
        transcriber.send(.volatile("We should ship", latency: nil))
        await settle { !session.transcript.volatileText.isEmpty }
        clock.advance(.milliseconds(400))
        session.refreshStatus()
        #expect(transcriber.finalizeCount == 0)
        #expect(session.level > 0)
        // The source stops sending audio altogether.
        clock.advance(.milliseconds(700))
        session.refreshStatus()
        await settle { transcriber.finalizeCount == 1 }
        #expect(transcriber.finalizeCount == 1)
        #expect(session.level == 0)
        for _ in 0..<20 { await Task.yield() }
        clock.advance(.seconds(1))
        session.refreshStatus()
        for _ in 0..<20 { await Task.yield() }
        #expect(transcriber.finalizeCount == 1)
        // A new pause after more audio closes again.
        capture.emit(rms: 0.2)
        clock.advance(.seconds(2))
        session.refreshStatus()
        await settle { transcriber.finalizeCount == 2 }
        #expect(transcriber.finalizeCount == 2)
    }
}

/// L05: what the Live window pairs up.
struct LivePairsTests {
    private let a = LiveTranscript.Segment(id: UUID(), text: "First.")
    private let b = LiveTranscript.Segment(id: UUID(), text: "Second.")
    private let c = LiveTranscript.Segment(id: UUID(), text: "Third.")

    @Test func eachSegmentGetsItsOwnVietnameseLine() {
        let pairs = LivePairs.make(segments: [a, b], states: [a.id: .done("Một."), b.id: .translating("Ha")])
        #expect(pairs == [
            LivePair(id: a.id, english: "First.", vietnamese: .done("Một.")),
            LivePair(id: b.id, english: "Second.", vietnamese: .translating("Ha")),
        ])
    }

    @Test func mergedSegmentsShowAsOnePairWithOneTranslation() {
        let pairs = LivePairs.make(segments: [a, b, c], states: [a.id: .merged(into: b.id), b.id: .done("Một. Hai."), c.id: .waiting])
        #expect(pairs.map(\.english) == ["First. Second.", "Third."])
        #expect(pairs.map(\.vietnamese) == [.done("Một. Hai."), .waiting])
        #expect(pairs.first?.id == b.id)
    }

    @Test func skippedFailedAndUnknownStatesAreExplicit() {
        let pairs = LivePairs.make(segments: [a, b, c], states: [a.id: .skipped, b.id: .failed("Ollama is not running.")])
        #expect(pairs.map(\.vietnamese) == [.skipped, .failed("Ollama is not running."), .waiting])
    }

    @Test func aGroupCutOffByTheLimitStillShowsItsEnglish() {
        let pairs = LivePairs.make(segments: [a, b], states: [a.id: .merged(into: UUID()), b.id: .merged(into: UUID())])
        #expect(pairs.map(\.english) == ["First. Second."])
    }
}

