import Foundation
import Observation
import os

/// What the Vietnamese line under an English segment shows (PLAN §24.2).
enum LiveTranslationState: Equatable {
    case waiting
    /// Streaming; the partial translation so far.
    case translating(String)
    case done(String)
    /// Translated together with later segments; the text is shown under `into`.
    case merged(into: UUID)
    /// The queue fell more than `maxWait` behind; not translated, said so.
    case skipped
    case failed(String)
}

/// Translates finalized English segments to Vietnamese through the local
/// Ollama, one request at a time, while listening and recognition continue
/// (L01 design): at most `maxWaiting` segments wait — more are merged into one
/// request — and a segment waiting longer than `maxWait` is marked skipped
/// instead of queueing without end. ⌥T goes first: while a text request runs
/// no new Live request starts, and a running Live request is preempted (L06).
/// Cancelling Live never touches the text request.
@Observable
final class LiveTranslationQueue {
    static let maxWaiting = 3
    static let maxWait: Duration = .seconds(30)

    private(set) var states: [UUID: LiveTranslationState] = [:]

    @ObservationIgnored private let translate: (String) -> AsyncThrowingStream<String, Error>
    @ObservationIgnored private let isTextBusy: () -> Bool
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    @ObservationIgnored private let textBusyPoll: Duration
    @ObservationIgnored private let logger = Logger(subsystem: "local.chienhuynh.Undertone", category: "live")
    /// Observed, so the window's “n waiting” stays current (L08 review).
    private var waiting: [Unit] = []
    @ObservationIgnored private(set) var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// Segment final → translation complete (includes waiting), metadata only.
    @ObservationIgnored private(set) var latencies = LatencyRecorder()
    @ObservationIgnored private(set) var requestCount = 0
    /// Requests given up for a ⌥T request (then retried).
    @ObservationIgnored private(set) var preemptions = 0

    /// One request: one segment, or several merged when the queue was full.
    private struct Unit {
        var ids: [UUID]
        var text: String
        /// Oldest segment's time (translation latency).
        let enqueuedAt: ContinuousClock.Instant
        /// Newest segment's time (the 30 s rule), so a merge does not skip
        /// segments that only waited seconds.
        var lastEnqueuedAt: ContinuousClock.Instant
    }

    init(
        translate: @escaping (String) -> AsyncThrowingStream<String, Error>,
        isTextBusy: @escaping () -> Bool,
        textBusyPoll: Duration = .milliseconds(200),
        now: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.translate = translate
        self.isTextBusy = isTextBusy
        self.textBusyPoll = textBusyPoll
        self.now = now
    }

    var waitingCount: Int { waiting.count }

    func enqueue(_ segment: LiveTranscript.Segment) {
        states[segment.id] = .waiting
        dropStale()
        let time = now()
        waiting.append(Unit(ids: [segment.id], text: segment.text, enqueuedAt: time, lastEnqueuedAt: time))
        if waiting.count > Self.maxWaiting { mergeWaiting() }
        if worker == nil { startWorker() }
    }

    /// Stop: cancels the running request and forgets everything.
    func reset() {
        generation += 1
        worker?.cancel()
        worker = nil
        waiting = []
        states = [:]
        // Metrics are per session.
        latencies = LatencyRecorder()
        requestCount = 0
        preemptions = 0
    }

    /// Keeps only states for segments still on screen (transcript is bounded).
    func prune(keeping ids: Set<UUID>) {
        states = states.filter { ids.contains($0.key) }
        waiting.removeAll { unit in unit.ids.allSatisfy { !ids.contains($0) } }
    }

    /// Merges everything waiting into one request, oldest first, as long as it
    /// fits the context budget; what does not fit is skipped (said so).
    private func mergeWaiting() {
        var merged = waiting.removeFirst()
        while !waiting.isEmpty {
            let next = waiting.removeFirst()
            let candidate = merged.text + " " + next.text
            if TranslationBudget.fits(candidate) {
                merged.ids += next.ids
                merged.text = candidate
                merged.lastEnqueuedAt = max(merged.lastEnqueuedAt, next.lastEnqueuedAt)
            } else {
                for id in merged.ids { states[id] = .skipped }
                merged = next
            }
        }
        waiting = [merged]
        logger.notice("Live translation queue full: merged \(merged.ids.count, privacy: .public) segments into one request")
    }

    private func dropStale() {
        let current = now()
        let stale = waiting.filter { current - $0.lastEnqueuedAt > Self.maxWait }
        guard !stale.isEmpty else { return }
        waiting.removeAll { current - $0.lastEnqueuedAt > Self.maxWait }
        for id in stale.flatMap(\.ids) { states[id] = .skipped }
        logger.notice("Live translation behind: \(stale.count, privacy: .public) requests skipped")
    }

    private func startWorker() {
        let generation = generation
        worker = Task { [weak self] in await self?.drain(generation) }
    }

    private func drain(_ generation: Int) async {
        // Every exit clears the worker, so the next segment starts a new one.
        defer { if self.generation == generation { worker = nil } }
        while !Task.isCancelled, self.generation == generation {
            dropStale()
            guard !waiting.isEmpty else { return }
            // ⌥T first (PLAN §24.3): wait while a text request runs.
            while isTextBusy(), !Task.isCancelled { try? await Task.sleep(for: textBusyPoll) }
            // A long ⌥T wait can age the queue: apply the 30 s rule again.
            dropStale()
            guard !Task.isCancelled, self.generation == generation, !waiting.isEmpty else { return }
            let unit = waiting.removeFirst()
            await run(unit, generation: generation)
        }
    }

    private enum Outcome {
        case finished(String)
        case failed(Error)
        /// Cancelled because a ⌥T request started (L06).
        case preempted
        case cancelled
    }

    /// Streams one request. Ollama here serves one request at a time (L06:
    /// a text request behind a Live request waited 4.1–4.2 s for its first
    /// token instead of 0.15 s), so a starting ⌥T request preempts the running
    /// Live request: it is cancelled (Ollama stops it) and put back at the
    /// front of the queue, to run again after the text request.
    private func run(_ unit: Unit, generation: Int) async {
        guard let target = unit.ids.last else { return }
        for id in unit.ids.dropLast() { states[id] = .merged(into: target) }
        states[target] = .translating("")
        requestCount += 1
        let preempted = PreemptFlag()
        let request = Task { [translate] () -> Outcome in
            var output = ""
            do {
                for try await delta in translate(unit.text) {
                    try Task.checkCancellation()
                    output += delta
                    if self.generation == generation { self.states[target] = .translating(output) }
                }
                try Task.checkCancellation()
                return .finished(output)
            } catch {
                if preempted.value { return .preempted }
                if Task.isCancelled || error is CancellationError { return .cancelled }
                return .failed(error)
            }
        }
        let watcher = Task { [isTextBusy, textBusyPoll] in
            while !Task.isCancelled {
                try? await Task.sleep(for: textBusyPoll)
                if isTextBusy() {
                    preempted.value = true
                    request.cancel()
                    return
                }
            }
        }
        let outcome = await withTaskCancellationHandler { await request.value } onCancel: { request.cancel() }
        watcher.cancel()
        guard !Task.isCancelled, self.generation == generation else { return }
        switch outcome {
        case .finished(let output):
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            states[target] = text.isEmpty ? .failed(TranslationError.emptyOutput.message) : .done(text)
            latencies.record(now() - unit.enqueuedAt)
        case .failed(let error):
            let failure = TranslationError(error)
            states[target] = .failed(failure.message)
            logger.notice("Live translation failed: \(failure.logLabel, privacy: .public)")
        case .preempted:
            for id in unit.ids { states[id] = .waiting }
            waiting.insert(unit, at: 0)
            preemptions += 1
            logger.notice("Live translation paused for a text translation")
        case .cancelled:
            break
        }
    }

    var latencySummary: String {
        guard let p50 = latencies.percentile(0.5), let p95 = latencies.percentile(0.95) else { return "no translations" }
        return "translation p50 \(LiveSession.ms(p50)) ms, p95 \(LiveSession.ms(p95)) ms (\(latencies.samples.count) of \(requestCount) requests, \(preemptions) paused for ⌥T)"
    }
}

/// Set before cancelling, read by the cancelled request (both on the main actor
/// or right after the cancel), so a preemption is not reported as an error.
nonisolated final class PreemptFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
