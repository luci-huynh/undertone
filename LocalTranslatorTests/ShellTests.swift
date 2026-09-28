import Foundation
import Testing
@testable import LocalTranslator

@MainActor
struct ShellTests {
    @Test func completionRequiresOutputAndIgnoresLateEvents() {
        let state = TranslationStateMachine()
        #expect(state.phase == .idle)
        let id = state.begin()
        #expect(state.phase == .loading)
        state.receive("Xin ", for: id)
        state.receive("chào", for: id)
        #expect(state.phase == .streaming)
        state.complete(for: id)
        state.receive("late", for: id)
        state.fail(.unavailable, for: id)
        #expect(state.phase == .success)
        #expect(state.output == "Xin chào")
    }

    @Test func supersededRequestCannotMutateNewRequest() {
        let state = TranslationStateMachine()
        let old = state.begin()
        state.receive("old", for: old)
        let current = state.begin()
        #expect(old != current)
        state.receive("stale", for: old)
        state.complete(for: old)
        state.fail(.unavailable, for: old)
        #expect(state.phase == .loading)
        #expect(state.output.isEmpty)
        state.receive("new", for: current)
        state.complete(for: current)
        #expect(state.output == "new")
        #expect(state.phase == .success)
    }

    @Test func cancelAndDismissInvalidateCallbacksAndClearContent() {
        let state = TranslationStateMachine()
        let id = state.begin()
        state.receive("partial", for: id)
        state.cancel()
        state.receive("late", for: id)
        state.complete(for: id)
        #expect(state.phase == .cancelled)
        #expect(state.requestID == nil)
        #expect(state.output.isEmpty)
        state.dismiss()
        state.fail(.unavailable, for: id)
        #expect(state.phase == .idle)
    }

    @Test func failureKeepsPartialUntilRetry() {
        let state = TranslationStateMachine()
        let id = state.begin()
        state.receive("partial", for: id)
        state.fail(.unavailable, for: id)
        state.complete(for: id)
        #expect(state.phase == .error)
        #expect(state.output == "partial")
        #expect(state.failure == .unavailable)
        let retry = state.begin()
        #expect(retry != id)
        #expect(state.failure == nil)
        #expect(state.output.isEmpty)
    }

    @Test func emptyCompletionIsAnError() {
        let state = TranslationStateMachine()
        let id = state.begin()
        state.receive(" \n", for: id)
        state.complete(for: id)
        #expect(state.phase == .error)
        #expect(state.failure == .emptyOutput)
    }

    @Test func shellUsesInjectedReadinessAndShutdownClearsState() {
        let coordinator = AppCoordinator.fake()
        #expect(coordinator.readiness.runtime == .notChecked)
        let id = coordinator.translation.begin()
        coordinator.translation.receive("synthetic", for: id)
        coordinator.shutdown()
        coordinator.translation.receive("late", for: id)
        #expect(coordinator.translation.phase == .idle)
        #expect(coordinator.translation.output.isEmpty)
    }
}
