import Foundation
import Observation
import os

/// What the Live window shows about the capture (PLAN §24.2: listening, no
/// audio and errors are distinguishable).
enum LiveStatus: Equatable {
    case idle
    /// Preparing the on-device speech model (progress 0…1 while it downloads).
    case preparing(Double?)
    case listening
    /// Capture runs; the source is quiet.
    case silent
    /// No process of the chosen app is running.
    case sourceNotRunning
    /// The source is playing but only silence arrives — usually the System
    /// Audio Recording permission is off.
    case noAudioReceived
    case failed(String)

    var label: String {
        switch self {
        case .idle: "Stopped"
        case .preparing(nil): "Starting…"
        case .preparing(let progress?): "Getting the English speech model ready… \(Int(progress * 100))%"
        case .listening: "Listening"
        case .silent: "Listening — no sound"
        case .sourceNotRunning: "The chosen app isn't running"
        case .noAudioReceived: "The app is playing but no sound arrives. Allow Undertone under Privacy & Security → Screen & System Audio Recording (System Audio Recording Only)."
        case .failed(let message): message
        }
    }

    var isRunning: Bool {
        switch self {
        case .preparing, .listening, .silent, .sourceNotRunning, .noAudioReceived: true
        case .idle, .failed: false
        }
    }

    /// The fix is the System Audio Recording permission: the window offers
    /// a button to that System Settings page.
    var needsAudioPermission: Bool {
        switch self {
        case .noAudioReceived: true
        case .failed(let message): message == LiveCaptureError.tapRefused(0).message
        default: false
        }
    }
}

/// Stores the chosen source only (configuration, never audio).
protocol LiveSettingsStoring: AnyObject {
    var source: LiveSource { get set }
    /// Live window stays above other windows (L05a; default on).
    var keepsWindowOnTop: Bool { get set }
}

final class UserDefaultsLiveSettings: LiveSettingsStoring {
    private let defaults: UserDefaults
    private static let key = "LiveSource"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var source: LiveSource {
        get { defaults.string(forKey: Self.key).flatMap(LiveSource.init(rawValue:)) ?? .teams }
        set { defaults.set(newValue.rawValue, forKey: Self.key) }
    }

    var keepsWindowOnTop: Bool {
        get { defaults.object(forKey: "LiveKeepsWindowOnTop") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "LiveKeepsWindowOnTop") }
    }
}

/// One Live session: capture (L02) → on-device speech recognition (L03) →
/// English subtitles. Capture runs only between Start and Stop; Stop, closing
/// the window and quitting stop it, discard pending recognition and clear the
/// buffer and subtitles. Independent of the text flow: nothing here touches ⌥T
/// or the popup, and the popup never stops Live (PLAN §24.3).
@Observable
final class LiveSession {
    /// Samples kept in RAM (PLAN §24.1 bounded buffer, L01: ≤ 30 s).
    static let bufferSeconds: Double = 30
    /// Below this RMS (about −80 dBFS) a block counts as silence.
    static let silenceRMS: Float = 0.0001

    /// A segment is closed after this long without a pause (L01 design).
    static let maxUtterance: Duration = .seconds(12)
    static let maxUtteranceCharacters = 200
    /// No audio block for this long closes the sentence still being recognized
    /// (a source that stops output entirely sends nothing more; L08 review).
    static let pauseFinalize: Duration = .seconds(1)
    /// Device events right after our own capture rebuild are ignored.
    static let restartCooldown: Duration = .milliseconds(1500)

    private(set) var status: LiveStatus = .idle
    /// English subtitles of this session, RAM only.
    private(set) var transcript = LiveTranscript()
    /// Vietnamese translations by segment ID (L04).
    let translations: LiveTranslationQueue
    /// Display level 0…1 (−60 dBFS … 0 dBFS).
    private(set) var level: Double = 0
    var source: LiveSource {
        didSet { settings.source = source }
    }
    /// Window option; the controller applies it to the window level.
    var keepsWindowOnTop: Bool {
        didSet { settings.keepsWindowOnTop = keepsWindowOnTop }
    }

    @ObservationIgnored private let capture: any LiveAudioCapturing
    /// A new recognizer per session, so a session still stopping can never
    /// touch the next one's analyzer (L08 review).
    @ObservationIgnored private let makeTranscriber: () -> any LiveTranscribing
    @ObservationIgnored private var recognizer: (any LiveTranscribing)?
    @ObservationIgnored private var lastRestartAt: ContinuousClock.Instant?
    @ObservationIgnored private let processes: any LiveProcessListing
    @ObservationIgnored private let systemEvents: any LiveSystemEventSource
    /// Where captured audio goes during the running session (for restarts).
    @ObservationIgnored private var sink: (any LiveAudioSink)?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    /// Capture rebuilds after device changes or wake (tests, logs).
    @ObservationIgnored private(set) var captureRestarts = 0
    @ObservationIgnored private let settings: any LiveSettingsStoring
    @ObservationIgnored private let statusInterval: Duration
    /// Silence while the source plays for this long → `.noAudioReceived`.
    @ObservationIgnored private let blockedAfter: Duration
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    @ObservationIgnored private let logger = Logger(subsystem: "local.chienhuynh.Undertone", category: "live")
    @ObservationIgnored private(set) var buffer: LiveAudioRingBuffer?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    /// Exposed so tests can await them.
    @ObservationIgnored private(set) var startTask: Task<Void, Never>?
    @ObservationIgnored private(set) var eventsTask: Task<Void, Never>?
    @ObservationIgnored private(set) var latencies = LatencyRecorder()
    @ObservationIgnored private var volatileSince: ContinuousClock.Instant?
    @ObservationIgnored private var finalizing = false
    /// The current pause (no audio blocks) already closed its sentence.
    @ObservationIgnored private var pauseFinalized = false
    @ObservationIgnored private var startedAt: ContinuousClock.Instant?
    @ObservationIgnored private var lastSound: ContinuousClock.Instant?
    /// Last level report of any kind (audio callbacks arrive only while the source plays).
    @ObservationIgnored private var lastLevel: ContinuousClock.Instant?
    /// First status check that saw the source playing, reset when it stops.
    @ObservationIgnored private var playingSince: ContinuousClock.Instant?
    @ObservationIgnored private var sessionID = UUID()
    /// Metadata for the logs: loudest block and ticks since the last summary.
    @ObservationIgnored private var peakRMS: Float = 0
    @ObservationIgnored private var ticks = 0

    init(
        capture: any LiveAudioCapturing,
        transcriber: @escaping () -> any LiveTranscribing,
        translations: LiveTranslationQueue,
        processes: any LiveProcessListing,
        systemEvents: (any LiveSystemEventSource)? = nil,
        settings: any LiveSettingsStoring,
        statusInterval: Duration = .seconds(1),
        blockedAfter: Duration = .seconds(4),
        now: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.capture = capture
        self.makeTranscriber = transcriber
        self.translations = translations
        self.processes = processes
        self.systemEvents = systemEvents ?? NoLiveSystemEvents()
        self.settings = settings
        self.statusInterval = statusInterval
        self.blockedAfter = blockedAfter
        self.now = now
        source = settings.source
        keepsWindowOnTop = settings.keepsWindowOnTop
    }

    var bufferedSeconds: Double { buffer?.bufferedSeconds ?? 0 }

    /// Start button. Asks for the audio permission only here (first Start).
    func start() {
        guard !status.isRunning else { return }
        let session = UUID()
        sessionID = session
        transcript = LiveTranscript()
        translations.reset()
        latencies = LatencyRecorder()
        status = .preparing(nil)
        startTask = Task { [weak self] in await self?.begin(session) }
    }

    private func begin(_ session: UUID) async {
        let transcriber = makeTranscriber()
        recognizer = transcriber
        do {
            try await transcriber.prepare { [weak self] progress in
                guard let self, sessionID == session else { return }
                status = .preparing(progress)
            }
            guard sessionID == session else {
                await transcriber.stop()
                return
            }
            let (speechSink, events) = try await transcriber.start()
            guard sessionID == session else {
                await transcriber.stop()
                return
            }
            // Capacity for 48 kHz; the tap's real rate is recorded with the samples.
            let buffer = LiveAudioRingBuffer.seconds(Self.bufferSeconds, sampleRate: 48_000)
            let sink = LiveAudioFanOut([buffer, speechSink])
            try startCapture(into: sink, session: session)
            self.sink = sink
            self.buffer = buffer
            systemEvents.start { [weak self] event in self?.systemChanged(event, session: session) }
            startedAt = now()
            lastSound = nil
            lastLevel = nil
            playingSince = nil
            volatileSince = nil
            level = 0
            logger.notice("Live started: \(self.source.rawValue, privacy: .public)")
            refreshStatus()
            statusTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let interval = self?.statusInterval else { return }
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled else { return }
                    self?.refreshStatus()
                }
            }
            eventsTask = Task { [weak self] in
                do {
                    for try await event in events {
                        guard let self, sessionID == session else { return }
                        receive(event)
                    }
                    // The recognizer ended by itself while the session still runs.
                    self?.recognitionEnded(session, error: nil)
                } catch {
                    self?.recognitionEnded(session, error: error)
                }
            }
        } catch {
            guard sessionID == session else { return }
            await transcriber.stop()
            recognizer = nil
            let message = (error as? LiveCaptureError)?.message ?? (error as? LiveTranscriberError)?.message ?? "Couldn't start Live."
            logger.notice("Live start failed: \(String(describing: error), privacy: .public)")
            status = .failed(message)
        }
    }

    private func startCapture(into sink: any LiveAudioSink, session: UUID) throws {
        let bundleIDs = source.tapBundleIDs(running: processes.audioProcesses())
        try capture.start(bundleIDs: bundleIDs, into: sink) { [weak self] level in
            guard let self, sessionID == session, status.isRunning else { return }
            receive(level)
        }
    }

    /// Speech recognition stopping on its own is shown, never silent (L08 review).
    private func recognitionEnded(_ session: UUID, error: Error?) {
        guard sessionID == session, status.isRunning else { return }
        logger.notice("Live speech recognition ended: \(error.map { String(describing: type(of: $0)) } ?? "finished", privacy: .public)")
        fail("Speech recognition stopped. Press Start to try again.")
    }

    /// Output device changed or the Mac woke: rebuild the tap and aggregate
    /// device, keeping recognition, subtitles and the translation queue.
    /// Bursts of events (a device change fires several) restart once.
    private func systemChanged(_ event: LiveSystemEvent, session: UUID) {
        guard sessionID == session, sink != nil, restartTask == nil else { return }
        if let lastRestartAt, now() - lastRestartAt < Self.restartCooldown { return }
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, sessionID == session, let sink else { return }
            restartTask = nil
            capture.stop()
            do {
                try startCapture(into: sink, session: session)
                lastRestartAt = now()
                captureRestarts += 1
                logger.notice("Live capture restarted after \(String(describing: event), privacy: .public)")
            } catch {
                let message = (error as? LiveCaptureError)?.message ?? "Couldn't restart audio capture."
                logger.notice("Live capture restart failed: \(String(describing: error), privacy: .public)")
                fail(message)
            }
        }
    }

    /// Stop button, closing the Live window, quitting.
    func stop() {
        endSession()
        translations.reset()
        transcript = LiveTranscript()
        status = .idle
    }

    /// A failure while running: capture and recognition end so no status tick
    /// paints the session as listening; the subtitles stay readable until
    /// Start or closing the window (L08 review).
    private func fail(_ message: String) {
        endSession()
        status = .failed(message)
    }

    private func endSession() {
        restartTask?.cancel()
        restartTask = nil
        systemEvents.stop()
        sink = nil
        startTask?.cancel()
        startTask = nil
        eventsTask?.cancel()
        eventsTask = nil
        statusTask?.cancel()
        statusTask = nil
        sessionID = UUID()
        let wasRunning = status.isRunning
        capture.stop()
        if let recognizer {
            Task { await recognizer.stop() }
        }
        recognizer = nil
        lastRestartAt = nil
        finalizing = false
        pauseFinalized = false
        buffer?.clear()
        buffer = nil
        if wasRunning, let startedAt {
            let seconds = Int((now() - startedAt).components.seconds)
            logger.notice("Live stopped after \(seconds, privacy: .public) s; \(self.latencySummary, privacy: .public); \(self.translations.latencySummary, privacy: .public)")
        }
        level = 0
        startedAt = nil
    }

    private func receive(_ event: LiveTranscriptEvent) {
        switch event {
        case .volatile(let text, let latency), .final(let text, let latency):
            if let latency { latencies.record(latency) }
            if case .final = event {
                volatileSince = nil
                if let segment = transcript.apply(event) {
                    logger.notice("Live segment: \(segment.text.count, privacy: .public) chars")
                    // Only settled segments are translated, never each partial update.
                    translations.enqueue(segment)
                    translations.prune(keeping: Set(transcript.segments.map(\.id)))
                }
            } else {
                if volatileSince == nil, !text.isEmpty { volatileSince = now() }
                transcript.apply(event)
            }
        }
        // A long monologue without a pause is closed into a segment (L01).
        let tooLong = volatileSince.map { now() - $0 >= Self.maxUtterance } ?? false
        if tooLong || transcript.volatileText.count >= Self.maxUtteranceCharacters { requestFinalize() }
    }

    /// Closes the current sentence without blocking the event stream.
    private func requestFinalize() {
        guard !finalizing, let recognizer else { return }
        finalizing = true
        volatileSince = nil
        let session = sessionID
        Task { [weak self] in
            await recognizer.finalizeNow()
            guard let self, sessionID == session else { return }
            finalizing = false
        }
    }

    /// “p50 … ms, p95 … ms (n)” — metadata for logs.
    var latencySummary: String {
        guard let p50 = latencies.percentile(0.5), let p95 = latencies.percentile(0.95) else { return "no speech results" }
        return "speech latency p50 \(Self.ms(p50)) ms, p95 \(Self.ms(p95)) ms (\(latencies.samples.count) results)"
    }

    static func ms(_ duration: Duration) -> Int {
        Int(duration.components.seconds) * 1000 + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    private func receive(_ level: LiveAudioLevel) {
        peakRMS = max(peakRMS, level.rms)
        let decibels = 20 * log10(Double(max(level.rms, 1e-9)))
        self.level = min(1, max(0, (decibels + 60) / 60))
        lastLevel = now()
        pauseFinalized = false
        if level.rms >= Self.silenceRMS { lastSound = now() }
    }

    /// Decides the status from the process list and recent sound.
    func refreshStatus() {
        guard startedAt != nil else { return }
        let owned = processes.audioProcesses().filter { source.owns(bundleID: $0.bundleID) }
        let recentSound = lastSound.map { now() - $0 < .milliseconds(1500) } ?? false
        // No audio blocks: the meter falls to zero and the pending sentence is closed.
        let quiet = lastLevel.map { now() - $0 } ?? .seconds(3600)
        if quiet > .milliseconds(500), level != 0 { level = 0 }
        if quiet >= Self.pauseFinalize, !pauseFinalized, !transcript.volatileText.isEmpty {
            pauseFinalized = true
            requestFinalize()
        }
        let previous = status
        let playing = owned.contains(where: \.isPlaying)
        defer { logStatus(previous: previous, playing: playing) }
        if playing { playingSince = playingSince ?? now() } else { playingSince = nil }
        // The tap delivers audio only while the source plays. Blocked means: the
        // source has been playing for a while and not a single block arrived since.
        let blocked = playingSince.map { since in
            now() - since >= blockedAfter && (lastLevel.map { $0 < since } ?? true)
        } ?? false
        if recentSound {
            status = .listening
        } else if owned.isEmpty {
            status = .sourceNotRunning
        } else if blocked {
            status = .noAudioReceived
        } else {
            status = .silent
        }
    }

    /// Metadata only (status name, dBFS, seconds): never audio or text.
    private func logStatus(previous: LiveStatus, playing: Bool) {
        if status != previous {
            logger.notice("Live status: \(String(describing: self.status).prefix(40), privacy: .public)")
        }
        ticks += 1
        guard ticks >= 5 else { return }
        let peak = peakRMS > 0 ? Int((20 * log10(Double(peakRMS))).rounded()) : -999
        logger.notice("Live level: peak \(peak, privacy: .public) dBFS, source playing \(playing, privacy: .public), buffered \(Int(self.bufferedSeconds), privacy: .public) s, segments \(self.transcript.segments.count, privacy: .public), \(self.latencySummary, privacy: .public), \(self.translations.latencySummary, privacy: .public), waiting \(self.translations.waitingCount, privacy: .public)")
        ticks = 0
        peakRMS = 0
    }
}
