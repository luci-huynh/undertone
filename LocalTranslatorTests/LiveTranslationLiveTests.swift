import Foundation
import Testing
@testable import Undertone

/// Live translation through the real local Ollama (L04). Runs only with
/// TEST_RUNNER_LT_LIVE_OLLAMA=1; synthetic meeting sentences (the L03 ASR
/// output of the synthetic sample); prints `LIVE-VI` lines.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LT_LIVE_OLLAMA"] == "1"))
struct LiveTranslationLiveTests {
    @Test func meetingSegmentsGetVietnameseInOrder() async throws {
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: URLSessionTransport())
        await readiness.refresh()
        try #require(readiness.isReady, "Ollama \(readiness.runtime.label)")
        let service = OllamaTranslationService(readiness: readiness)
        let queue = LiveTranslationQueue(translate: { service.translate($0, direction: .englishToVietnamese) }, isTextBusy: { false })
        let sentences = [
            "Good morning, everyone.",
            "Let's start with the status update.",
            "The payment service migration is almost done, and we expect to finish it sometime next week.",
            "However, the reporting dashboard still has 2 open bugs.",
            "Sarah will look into the currency conversion issue, and Minh will handle the timeout errors.",
            "Any questions before we move on?",
        ]
        let segments = sentences.map { LiveTranscript.Segment(id: UUID(), text: $0) }
        // Sentences arrive about as fast as someone speaks them.
        for segment in segments {
            queue.enqueue(segment)
            try await Task.sleep(for: .seconds(2))
        }
        for _ in 0..<600 {
            let pending = segments.contains { segment in
                switch queue.states[segment.id] {
                case .waiting, .translating, nil: true
                default: false
                }
            }
            guard pending else { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        for segment in segments {
            let state = queue.states[segment.id]
            print("LIVE-VI\t\(segment.text)\t\(String(describing: state))")
            switch state {
            case .done(let vietnamese):
                let detected = LanguageRouter.detect(vietnamese)
                #expect(detected == .vietnamese || detected == .ambiguous(bestGuess: .vietnamese), "\(segment.text) → \(detected)")
            case .merged:
                break
            default:
                Issue.record("\(segment.text): \(String(describing: state))")
            }
        }
        print("LIVE-VI\tstats\t\(queue.latencySummary)")
    }

    /// L06 contention: a text request while Live is translating.
    @Test func textRequestIsNotStuckBehindALiveRequest() async throws {
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: URLSessionTransport())
        await readiness.refresh()
        try #require(readiness.isReady, "Ollama \(readiness.runtime.label)")
        let service = OllamaTranslationService(readiness: readiness)
        var textBusy = false
        let queue = LiveTranslationQueue(translate: { service.translate($0, direction: .englishToVietnamese) }, isTextBusy: { textBusy }, textBusyPoll: .milliseconds(50))
        // Warm up.
        for try await _ in service.translate("Hello.", direction: .englishToVietnamese) {}
        var firsts: [Duration] = []
        for round in 0..<3 {
            let live = LiveTranscript.Segment(id: UUID(), text: "The payment service migration is almost done, and we expect to finish it sometime next week, but the reporting dashboard still has two open bugs that Sarah and Minh will handle.")
            queue.enqueue(live)
            try await Task.sleep(for: .milliseconds(400))
            // What TranslationCoordinator does on ⌥T: its state becomes loading, then it requests.
            textBusy = true
            let start = ContinuousClock.now
            var first: Duration?
            for try await _ in service.translate("Please review the pull request before Friday.", direction: .englishToVietnamese) where first == nil {
                first = ContinuousClock.now - start
            }
            textBusy = false
            firsts.append(first ?? .seconds(99))
            for _ in 0..<200 {
                if case .done = queue.states[live.id] { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            print("LIVE-VI\tcontention \(round)\ttext first \(LiveSession.ms(first ?? .zero)) ms, live \(String(describing: queue.states[live.id]).prefix(40))")
            if case .done = queue.states[live.id] {} else { Issue.record("Live segment not finished after preemption") }
        }
        print("LIVE-VI\tcontention\t\(queue.latencySummary)")
        #expect(firsts.allSatisfy { $0 < .seconds(1.5) }, "text first tokens: \(firsts.map(LiveSession.ms))")
    }
}

