import Foundation
import Observation
import Testing
@testable import Undertone

/// Hand-driven Ollama stand-in for Live translation requests.
@MainActor
final class ScriptedLiveTranslate {
    private(set) var inputs: [String] = []
    private var continuations: [AsyncThrowingStream<String, Error>.Continuation] = []
    private let terminations = TerminationLog()
    var terminated: [Int] { terminations.values }

    func translate(_ text: String) -> AsyncThrowingStream<String, Error> {
        inputs.append(text)
        let index = inputs.count - 1
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let log = terminations
        continuation.onTermination = { termination in
            if case .cancelled = termination { log.append(index) }
        }
        continuations.append(continuation)
        return stream
    }

    func send(_ delta: String, request: Int) { continuations[request].yield(delta) }
    func finish(request: Int) { continuations[request].finish() }
    func fail(_ error: Error, request: Int) { continuations[request].finish(throwing: error) }
}

/// L04: segment/translation pairing, bounded queue, text priority, Stop.
@MainActor
struct LiveTranslationQueueTests {
    private func segment(_ text: String) -> LiveTranscript.Segment { .init(id: UUID(), text: text) }

    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { await Task.yield() }
    }

    private func make(textBusy: @escaping () -> Bool = { false }, clock: ManualClock = ManualClock()) -> (LiveTranslationQueue, ScriptedLiveTranslate) {
        let ollama = ScriptedLiveTranslate()
        let queue = LiveTranslationQueue(translate: { ollama.translate($0) }, isTextBusy: textBusy, textBusyPoll: .milliseconds(5), now: { clock.now })
        return (queue, ollama)
    }

    @Test func translationStreamsIntoTheSameSegment() async {
        let (queue, ollama) = make()
        let first = segment("We expect the migration to finish next week.")
        queue.enqueue(first)
        await settle { ollama.inputs.count == 1 }
        #expect(ollama.inputs == [first.text])
        ollama.send("Chúng tôi ", request: 0)
        await settle { queue.states[first.id] == .translating("Chúng tôi ") }
        ollama.send("dự kiến…", request: 0)
        ollama.finish(request: 0)
        await settle { queue.states[first.id] == .done("Chúng tôi dự kiến…") }
        #expect(queue.states[first.id] == .done("Chúng tôi dự kiến…"))
        #expect(queue.latencies.samples.count == 1)
    }

    @Test func oneRequestAtATimeInOrder() async {
        let (queue, ollama) = make()
        let a = segment("First."), b = segment("Second.")
        queue.enqueue(a)
        queue.enqueue(b)
        await settle { ollama.inputs.count == 1 }
        #expect(queue.states[b.id] == .waiting)
        ollama.send("Một.", request: 0)
        ollama.finish(request: 0)
        await settle { ollama.inputs.count == 2 }
        #expect(ollama.inputs == ["First.", "Second."])
        ollama.send("Hai.", request: 1)
        ollama.finish(request: 1)
        await settle { queue.states[b.id] == .done("Hai.") }
        #expect(queue.states[a.id] == .done("Một."))
    }

    @Test func aFullQueueMergesInsteadOfGrowingAndLosesNothing() async {
        let (queue, ollama) = make()
        let running = segment("Running.")
        queue.enqueue(running)
        await settle { ollama.inputs.count == 1 }
        let fast = (1...5).map { segment("Fast \($0).") }
        for s in fast {
            queue.enqueue(s)
            #expect(queue.waitingCount <= LiveTranslationQueue.maxWaiting)
        }
        ollama.finish(request: 0)
        await settle { ollama.inputs.count == 2 }
        // The 4th waiting segment merged Fast 1–4 into one request (oldest
        // first); Fast 5 arrived after the merge and waits on its own.
        #expect(ollama.inputs[1] == fast.prefix(4).map(\.text).joined(separator: " "))
        let group = fast[3].id
        for s in fast.prefix(3) { #expect(queue.states[s.id] == .merged(into: group)) }
        ollama.send("Nhanh 1–4.", request: 1)
        ollama.finish(request: 1)
        await settle { ollama.inputs.count == 3 }
        #expect(queue.states[group] == .done("Nhanh 1–4."))
        #expect(ollama.inputs[2] == "Fast 5.")
        ollama.send("Nhanh 5.", request: 2)
        ollama.finish(request: 2)
        await settle { queue.states[fast[4].id] == .done("Nhanh 5.") }
        // No segment lost: each is done or merged into a done group.
        for s in fast { #expect(queue.states[s.id] != nil && queue.states[s.id] != .waiting) }
    }

    @Test func segmentsWaitingTooLongAreMarkedSkipped() async {
        let clock = ManualClock()
        let (queue, ollama) = make(clock: clock)
        let running = segment("Long answer.")
        let old = segment("Old.")
        queue.enqueue(running)
        await settle { ollama.inputs.count == 1 }
        queue.enqueue(old)
        clock.advance(.seconds(31))
        let fresh = segment("Fresh.")
        queue.enqueue(fresh)
        #expect(queue.states[old.id] == .skipped)
        ollama.finish(request: 0)
        await settle { ollama.inputs.count == 2 }
        #expect(ollama.inputs[1] == "Fresh.")
    }

    @Test func aMergedRequestIsJudgedByItsNewestSegment() async {
        let clock = ManualClock()
        let (queue, ollama) = make(clock: clock)
        queue.enqueue(segment("Running."))
        await settle { ollama.inputs.count == 1 }
        let old = segment("Old.")
        queue.enqueue(old)
        clock.advance(.seconds(25))
        let rest = [segment("A."), segment("B."), segment("C.")]
        for s in rest { queue.enqueue(s) }
        // The oldest waited 35 s, the newest only 10 s: the merged request runs.
        clock.advance(.seconds(10))
        ollama.finish(request: 0)
        await settle { ollama.inputs.count == 2 }
        #expect(ollama.inputs.last == "Old. A. B. C.")
        #expect(queue.states[old.id] == .merged(into: rest[2].id))
    }

    @Test func aLongWaitBehindTextStillAppliesThe30SecondRule() async {
        let clock = ManualClock()
        var busy = true
        let (queue, ollama) = make(textBusy: { busy }, clock: clock)
        let waited = segment("Waited behind a text request.")
        queue.enqueue(waited)
        try? await Task.sleep(for: .milliseconds(20))
        clock.advance(.seconds(31))
        busy = false
        for _ in 0..<100 where queue.states[waited.id] != .skipped { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(queue.states[waited.id] == .skipped)
        #expect(ollama.inputs.isEmpty)
    }

    @Test func resetStartsTheNextSessionsMetricsFromZero() async {
        let (queue, ollama) = make()
        let one = segment("One.")
        queue.enqueue(one)
        await settle { ollama.inputs.count == 1 }
        ollama.send("Một.", request: 0)
        ollama.finish(request: 0)
        await settle { queue.states[one.id] == .done("Một.") }
        #expect(queue.requestCount == 1)
        #expect(queue.latencies.samples.count == 1)
        queue.reset()
        #expect(queue.requestCount == 0)
        #expect(queue.latencies.samples.isEmpty)
        #expect(queue.preemptions == 0)
    }

    @Test func theWaitingCountIsObserved() async {
        let (queue, ollama) = make()
        queue.enqueue(segment("Running."))
        await settle { ollama.inputs.count == 1 }
        let changed = PreemptFlag()
        withObservationTracking { _ = queue.waitingCount } onChange: { changed.value = true }
        queue.enqueue(segment("Next."))
        #expect(changed.value)
        #expect(queue.waitingCount == 1)
    }

    @Test func aRunningTextRequestGoesFirst() async {
        var busy = true
        let (queue, ollama) = make(textBusy: { busy })
        let s = segment("Wait for the popup.")
        queue.enqueue(s)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(ollama.inputs.isEmpty)
        #expect(queue.states[s.id] == .waiting)
        busy = false
        await settle { ollama.inputs.count == 1 }
        #expect(ollama.inputs == ["Wait for the popup."])
    }

    @Test func aStartingTextRequestPreemptsTheRunningLiveRequestWhichRunsAgainAfter() async {
        var busy = false
        let (queue, ollama) = make(textBusy: { busy })
        let s = segment("A long sentence that is being translated right now.")
        queue.enqueue(s)
        await settle { ollama.inputs.count == 1 }
        ollama.send("Một câu dài", request: 0)
        await settle { queue.states[s.id] == .translating("Một câu dài") }
        // ⌥T starts: the Live request is cancelled (Ollama stops it) and waits again.
        busy = true
        try? await Task.sleep(for: .milliseconds(40))
        #expect(ollama.terminated == [0])
        #expect(queue.states[s.id] == .waiting)
        #expect(queue.preemptions == 1)
        #expect(ollama.inputs.count == 1)
        // ⌥T done: the same sentence is translated again and completes.
        busy = false
        await settle { ollama.inputs.count == 2 }
        #expect(ollama.inputs[1] == s.text)
        ollama.send("Một câu dài đang được dịch.", request: 1)
        ollama.finish(request: 1)
        await settle { queue.states[s.id] == .done("Một câu dài đang được dịch.") }
        #expect(queue.states[s.id] == .done("Một câu dài đang được dịch."))
    }

    @Test func resetCancelsTheRequestAndIgnoresLateText() async {
        let (queue, ollama) = make()
        let s = segment("Stop me.")
        queue.enqueue(s)
        await settle { ollama.inputs.count == 1 }
        queue.reset()
        await settle { ollama.terminated == [0] }
        #expect(ollama.terminated == [0])
        ollama.send("muộn", request: 0)
        for _ in 0..<20 { await Task.yield() }
        #expect(queue.states.isEmpty)
        // A new session starts cleanly.
        let next = segment("Next session.")
        queue.enqueue(next)
        await settle { ollama.inputs.count == 2 }
        #expect(ollama.inputs[1] == "Next session.")
    }

    @Test func anOllamaErrorIsShownAndTheNextSegmentStillTranslates() async {
        let (queue, ollama) = make()
        let a = segment("First."), b = segment("Second.")
        queue.enqueue(a)
        queue.enqueue(b)
        await settle { ollama.inputs.count == 1 }
        ollama.fail(OllamaError.runtimeUnavailable, request: 0)
        await settle { ollama.inputs.count == 2 }
        #expect(queue.states[a.id] == .failed("Ollama is not running."))
        ollama.send("Hai.", request: 1)
        ollama.finish(request: 1)
        await settle { queue.states[b.id] == .done("Hai.") }
    }

    @Test func pruneForgetsSegmentsNoLongerShown() async {
        let (queue, ollama) = make()
        let a = segment("A."), b = segment("B.")
        queue.enqueue(a)
        queue.enqueue(b)
        await settle { ollama.inputs.count == 1 }
        queue.prune(keeping: [a.id])
        #expect(queue.states[b.id] == nil)
        ollama.finish(request: 0)
        for _ in 0..<30 { await Task.yield() }
        #expect(ollama.inputs.count == 1)
    }
}

@MainActor
struct LiveSessionTranslationTests {
    @Test func settledSegmentsAreTranslatedAndPartialsAreNot() async {
        let ollama = ScriptedLiveTranslate()
        let queue = LiveTranslationQueue(translate: { ollama.translate($0) }, isTextBusy: { false })
        let transcriber = FakeTranscriber()
        let session = LiveSession.fake(transcriber: transcriber, translations: queue)
        session.start()
        await session.startTask?.value
        transcriber.send(.volatile("Good", latency: nil))
        transcriber.send(.volatile("Good morning", latency: nil))
        transcriber.send(.final("Good morning, everyone.", latency: nil))
        for _ in 0..<200 where ollama.inputs.isEmpty { await Task.yield() }
        #expect(ollama.inputs == ["Good morning, everyone."])
        let id = session.transcript.segments.first?.id
        ollama.send("Chào buổi sáng mọi người.", request: 0)
        ollama.finish(request: 0)
        for _ in 0..<200 where id.flatMap({ queue.states[$0] }) != .done("Chào buổi sáng mọi người.") { await Task.yield() }
        #expect(id.flatMap { queue.states[$0] } == .done("Chào buổi sáng mọi người."))

        session.stop()
        #expect(queue.states.isEmpty)
    }
}
