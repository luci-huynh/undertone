import CoreGraphics
import Foundation
import Testing
@testable import Undertone

private let selectionAnchor = SelectionAnchor(
    source: .selectionBounds, rect: CGRect(x: 200, y: 500, width: 120, height: 18), screenIndex: 0, visibleFrame: testScreen
)

private func snapshot(_ text: String, anchor: SelectionAnchor? = selectionAnchor) -> SelectionSnapshot {
    SelectionSnapshot(sourcePID: 42, sourceAppName: "TextEdit", text: text, range: nil, anchor: anchor, capturedAt: Date())
}

/// Lets queued main-actor work (stream iteration) run.
@MainActor
private func settle(until condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        await Task.yield()
    }
}

@MainActor
struct TranslationFlowTests {
    @Test func selectionOpensLoadingThenStreamsThenFinishes() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("Hello world"))]),
            translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        #expect(popup.current?.phase == .loading)
        #expect(popup.shown.last?.anchor == selectionAnchor)
        #expect(translator.inputs == ["Hello world"])

        translator.send("Xin ")
        await settle { popup.current?.body == "Xin " }
        #expect(popup.current?.phase == .streaming)
        #expect(popup.current?.canCopy == false)
        translator.send("chào")
        translator.finish()
        await flow.translationTask?.value
        #expect(popup.current == PopupContent(
            title: "English → Vietnamese", body: "Xin chào", phase: .done, session: flow.state.requestID,
            alternateDirection: .vietnameseToEnglish, offersRetranslate: true
        ))
        #expect(translator.directions == [.englishToVietnamese])
        #expect(flow.state.phase == .success)
    }

    @Test func missingSelectionAnchorUsesTriggerTimeCursor() async {
        let popup = FakePopupPresenter()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("Hi", anchor: nil))]), popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        #expect(popup.shown.last?.anchor == cursorTestAnchor)
    }

    @Test func noSelectionShowsPlanMessageAndAutoDismisses() async {
        let popup = FakePopupPresenter()
        let flow = TranslationCoordinator.fake(popup: popup)
        flow.trigger()
        await flow.captureTask?.value
        // What was shown, not what is still visible: with a zero notice
        // duration the auto-dismiss may already have run (flaky at L08).
        #expect(popup.shown.last?.content.body == "No text selected.")
        #expect(popup.shown.last?.content.phase == .notice)
        #expect(popup.shown.last?.anchor == cursorTestAnchor)
        await flow.noticeTask?.value
        #expect(!popup.isVisible)
    }

    @Test func missingPermissionOffersSystemSettingsAndStays() async {
        let popup = FakePopupPresenter()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.failure(.permissionMissing)]), popup: popup
        )
        var opened = 0
        flow.onOpenAccessibilitySettings = { opened += 1 }
        flow.trigger()
        await flow.captureTask?.value
        #expect(popup.current?.body == "Undertone needs Accessibility permission to read selected text.")
        #expect(popup.current?.action == .openAccessibilitySettings)
        #expect(flow.noticeTask == nil)
        popup.onAction?(.openAccessibilitySettings)
        #expect(opened == 1)
        #expect(!popup.isVisible)
    }

    @Test func silentFailureClosesAnyOldPopup() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("A")), .failure(.focusChanged)]),
            translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        flow.trigger()
        await flow.captureTask?.value
        #expect(!popup.isVisible)
        #expect(flow.state.phase == .idle)
    }

    @Test func newTriggerCancelsOldRequestAndOldOutputNeverAppears() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("A")), .success(snapshot("B"))]),
            translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        translator.send("old partial", request: 0)
        await settle { popup.current?.body == "old partial" }
        let oldTask = flow.translationTask

        flow.trigger()
        #expect(oldTask?.isCancelled == true)
        await flow.captureTask?.value
        translator.send("late old", request: 0)
        translator.finish(request: 0)
        await oldTask?.value
        #expect(popup.current?.phase == .loading)
        translator.send("new", request: 1)
        translator.finish(request: 1)
        await flow.translationTask?.value
        #expect(popup.current?.body == "new")
        #expect(!popup.shown.contains { $0.content.body.contains("late old") })
        #expect(translator.inputs == ["A", "B"])
    }

    @Test func userDismissMidStreamCancelsAndClears() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("A"))]), translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        translator.send("partial")
        await settle { popup.current?.body == "partial" }
        let task = flow.translationTask
        popup.dismissByUser()
        #expect(task?.isCancelled == true)
        #expect(flow.state.phase == .idle)
        #expect(flow.state.output.isEmpty)
        let shownBefore = popup.shown.count
        translator.send(" more")
        translator.finish()
        await task?.value
        #expect(popup.shown.count == shownBefore)
        #expect(!popup.isVisible)
    }

    @Test func streamFailureShowsMessage() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("A"))]), translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        translator.fail(OllamaError.malformedStream)
        await flow.translationTask?.value
        #expect(popup.current?.phase == .failed)
        #expect(popup.current?.body == "")
        // S23: a specific reason instead of the generic “Translation failed.”
        #expect(popup.current?.message == "Ollama sent an unexpected response.")
        #expect(popup.current?.action == .retry)
        #expect(popup.current?.canCopy == false)
    }

    @Test func ollamaStoppingMidStreamKeepsPartialWithPlanMessage() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("A"))]), translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        translator.send("Thanh toán")
        await settle { popup.current?.body == "Thanh toán" }
        translator.fail(OllamaError.runtimeUnavailable)
        await flow.translationTask?.value
        #expect(popup.current?.title == "English → Vietnamese")
        #expect(popup.current?.body == "Thanh toán")
        #expect(popup.current?.phase == .failed)
        #expect(popup.current?.message == "Ollama is not running.")
    }

    @Test(arguments: [
        (OllamaError.inputTooLong, "Selected text is too long to translate at once.", ""),
        (OllamaError.outputTruncated, "Translation stopped early: the text is too long.", "Thanh toán"),
    ])
    func lengthLimitsAreExplained(_ error: OllamaError, _ message: String, _ partial: String) async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("A"))]), translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        await settle { !translator.inputs.isEmpty }
        if !partial.isEmpty {
            translator.send(partial)
            await settle { popup.current?.body == partial }
        }
        translator.fail(error)
        await flow.translationTask?.value
        #expect(popup.current?.phase == .failed)
        #expect(popup.current?.message == message)
        #expect(popup.current?.body == partial)
    }

    @Test func oneRequestKeepsOneSessionAcrossRenders() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("A")), .success(snapshot("B"))]),
            translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        for word in ["Một ", "hai ", "ba"] { translator.send(word) }
        translator.finish()
        await flow.translationTask?.value
        let first = Set(popup.shown.map(\.content.session))
        #expect(first.count == 1)
        #expect(first.first ?? nil != nil)
        flow.trigger()
        await flow.captureTask?.value
        #expect(popup.shown.last?.content.session != first.first ?? nil)
    }

    @Test func missingModelShowsPlanMessage() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("A"))]), translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        translator.fail(OllamaError.modelMissing("translategemma:12b"))
        await flow.translationTask?.value
        #expect(popup.current?.message == "Translation model is not installed.")
    }

    @Test func burstsOfDeltasAreCoalescedButNothingIsLost() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("A"))]),
            translator: translator, popup: popup, renderInterval: .milliseconds(30)
        )
        flow.trigger()
        await flow.captureTask?.value
        let shownAfterLoading = popup.shown.count
        for index in 0..<50 { translator.send("\(index) ") }
        translator.finish()
        await flow.translationTask?.value
        let expected = (0..<50).map { "\($0) " }.joined()
        #expect(popup.current?.body == expected)
        #expect(popup.current?.phase == .done)
        #expect(popup.shown.count - shownAfterLoading < 50)
    }

    @Test func closingOrRetriggeringCancelsTheUnderlyingStream() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("A")), .success(snapshot("B"))]),
            translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        translator.send("a")
        await settle { popup.current?.body == "a" }
        let first = flow.translationTask
        flow.trigger()
        await first?.value
        await settle { translator.terminatedRequests == [0] }
        #expect(translator.terminatedRequests == [0])
        await flow.captureTask?.value
        // The second request must have reached the translator before closing,
        // or there is no stream to cancel (flaky at L08).
        await settle { translator.inputs.count == 2 }
        let second = flow.translationTask
        popup.dismissByUser()
        await second?.value
        await settle { translator.terminatedRequests == [0, 1] }
        #expect(translator.terminatedRequests == [0, 1])
    }

    @Test func repeatedTriggersCancelOlderCaptureBeforeItStarts() async {
        let capturer = FakeSelectionCapturer(results: [.success(snapshot("Hi"))])
        let flow = TranslationCoordinator.fake(selection: capturer)
        flow.trigger()
        let old = flow.captureTask
        flow.trigger()
        #expect(old?.isCancelled == true)
        await old?.value
        await flow.captureTask?.value
        #expect(capturer.captureCount == 1)
    }

    @Test func olderInFlightCaptureCannotOverwriteNewerResult() async {
        let capturer = SuspendedSelectionCapturer()
        var starts = capturer.starts.makeAsyncIterator()
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(selection: capturer, translator: translator, popup: popup)
        flow.trigger()
        _ = await starts.next()
        let old = flow.captureTask
        flow.trigger()
        _ = await starts.next()
        capturer.complete(1, with: .success(snapshot("new")))
        await flow.captureTask?.value
        capturer.complete(0, with: .success(snapshot("old")))
        await old?.value
        #expect(translator.inputs == ["new"])
    }

    @Test func shutdownClosesPopupAndDropsLateCapture() async {
        let popup = FakePopupPresenter()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("A"))]), popup: popup
        )
        flow.trigger()
        flow.shutdown()
        await flow.captureTask?.value
        #expect(!popup.isVisible)
        #expect(popup.shown.isEmpty)
        #expect(flow.state.phase == .idle)
    }

    @Test func shortcutDrivesFlowThroughAppCoordinator() async {
        let registrar = FakeHotKeyRegistrar()
        let capturer = FakeSelectionCapturer(results: [.success(snapshot("Hi"))])
        let flow = TranslationCoordinator.fake(selection: capturer)
        let coordinator = AppCoordinator.fake(shortcut: GlobalShortcutService(registrar: registrar), flow: flow)
        coordinator.start()
        registrar.send(.pressed)
        await flow.captureTask?.value
        #expect(capturer.captureCount == 1)
        coordinator.shutdown()
        #expect(registrar.registered == nil)
    }
}

/// S23: recovery actions, incomplete label, cancellation is not an error.
@MainActor
struct RecoveryFlowTests {
    private func failed(
        with error: Error, partial: String = ""
    ) async -> (TranslationCoordinator, ScriptedTranslator, FakePopupPresenter) {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("Hello world"))]),
            translator: translator, popup: popup, detection: .ambiguous(bestGuess: .english)
        )
        flow.trigger()
        await flow.captureTask?.value
        await settle { !translator.inputs.isEmpty }
        if !partial.isEmpty {
            translator.send(partial)
            await settle { popup.current?.body == partial }
        }
        translator.fail(error)
        await flow.translationTask?.value
        return (flow, translator, popup)
    }

    @Test func ollamaNotRunningOffersRetryWhichResendsTheSameRequestOnce() async {
        let (flow, translator, popup) = await failed(with: OllamaError.runtimeUnavailable)
        #expect(popup.current?.message == "Ollama is not running.")
        #expect(popup.current?.action == .retry)
        #expect(popup.current?.isIncomplete == false)

        popup.onAction?(.retry)
        await settle { translator.inputs.count == 2 }
        #expect(translator.inputs == ["Hello world", "Hello world"])
        #expect(translator.directions == [.englishToVietnamese, .englishToVietnamese])
        #expect(popup.current?.phase == .loading)
        // Still a guess: Retry keeps the request as it was.
        #expect(popup.current?.title == "English → Vietnamese (guessed)")

        // A second press while loading does nothing: no duplicate request.
        popup.onAction?(.retry)
        for _ in 0..<20 { await Task.yield() }
        #expect(translator.inputs.count == 2)

        translator.send("Xin chào", request: 1)
        translator.finish(request: 1)
        await flow.translationTask?.value
        #expect(popup.current?.phase == .done)
        #expect(popup.current?.action == nil)
    }

    @Test func partialOutputIsKeptAndLabelledIncomplete() async {
        let (_, _, popup) = await failed(with: OllamaError.streamStalled, partial: "Xin ")
        #expect(popup.current?.body == "Xin ")
        #expect(popup.current?.isIncomplete == true)
        #expect(popup.current?.message == "Ollama stopped responding.")
        #expect(popup.current?.action == .retry)
        #expect(popup.current?.canCopy == false)
    }

    @Test(arguments: [OllamaError.modelMissing("translategemma:12b"), .inputTooLong, .outputTruncated, .cloudModelRejected("x:cloud")])
    func failuresThatWouldRepeatOfferNoRetry(_ error: OllamaError) async {
        let (flow, translator, popup) = await failed(with: error)
        #expect(popup.current?.phase == .failed)
        #expect(popup.current?.action == nil)
        flow.retry()
        for _ in 0..<20 { await Task.yield() }
        #expect(translator.inputs.count == 1)
    }

    @Test func retryThenCloseLeavesNothingRunning() async {
        let (flow, translator, popup) = await failed(with: OllamaError.coldStartTimeout)
        #expect(popup.current?.message == "The model took too long to start.")
        popup.onAction?(.retry)
        await settle { translator.inputs.count == 2 }
        popup.dismissByUser()
        await settle { translator.terminatedRequests == [1] }
        #expect(translator.terminatedRequests == [1])
        #expect(!popup.isVisible)
        #expect(flow.state.phase == .idle)
        flow.retry()
        #expect(translator.inputs.count == 2)
    }

    @Test func userCancellationIsNeverShownAsAnError() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("Hello world")), .success(snapshot("Second"))]),
            translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        await settle { !translator.inputs.isEmpty }
        flow.switchDirection()
        await settle { translator.inputs.count == 2 }
        flow.trigger()
        await flow.captureTask?.value
        await settle { translator.inputs.count == 3 }
        popup.dismissByUser()
        await settle { translator.terminatedRequests.count == 3 }
        #expect(!popup.shown.contains { $0.content.phase == .failed })
    }

    @Test func finishedTranslationOffersTranslateAgainNextToCopy() async {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("Hello world"))]), translator: translator, popup: popup
        )
        flow.trigger()
        await flow.captureTask?.value
        await settle { !translator.inputs.isEmpty }
        translator.send("Xin ")
        await settle { popup.current?.body == "Xin " }
        // Not while streaming.
        #expect(popup.current?.offersRetranslate == false)
        flow.retry()
        for _ in 0..<20 { await Task.yield() }
        #expect(translator.inputs.count == 1)

        translator.send("chào")
        translator.finish()
        await flow.translationTask?.value
        #expect(popup.current?.offersRetranslate == true)
        #expect(popup.current?.canCopy == true)
        popup.onAction?(.retry)
        await settle { translator.inputs.count == 2 }
        #expect(translator.inputs == ["Hello world", "Hello world"])
        #expect(translator.directions == [.englishToVietnamese, .englishToVietnamese])
        #expect(popup.current?.phase == .loading)
        #expect(popup.current?.offersRetranslate == false)
    }

    @Test func failedPopupKeepsItsRetryInsteadOfTheExtraButton() async {
        let (_, _, popup) = await failed(with: OllamaError.runtimeUnavailable)
        #expect(popup.current?.action == .retry)
        #expect(popup.current?.offersRetranslate == false)
    }

    @Test func systemCancelledStreamIsReportedAsInterrupted() async {
        let (_, _, popup) = await failed(with: CancellationError(), partial: "Xin ")
        #expect(popup.current?.message == "The translation was interrupted.")
        #expect(popup.current?.isIncomplete == true)
        #expect(popup.current?.action == .retry)
    }
}

/// S21: routed direction, “guessed” marking and ⇄.
@MainActor
struct DirectionFlowTests {
    private func start(
        _ text: String = "Hello world", detection: LanguageDetection? = .english
    ) async -> (TranslationCoordinator, ScriptedTranslator, FakePopupPresenter) {
        let popup = FakePopupPresenter()
        let translator = ScriptedTranslator()
        let flow = TranslationCoordinator.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot(text))]),
            translator: translator, popup: popup, detection: detection
        )
        flow.trigger()
        await flow.captureTask?.value
        await settle { !translator.inputs.isEmpty || popup.current?.phase == .notice }
        return (flow, translator, popup)
    }

    @Test func vietnameseSelectionTranslatesToEnglish() async {
        let (_, translator, popup) = await start("Thanh toán đã được xử lý và hóa đơn đã được gửi đến email của bạn.", detection: nil)
        #expect(translator.directions == [.vietnameseToEnglish])
        #expect(popup.current?.title == "Vietnamese → English")
        #expect(popup.current?.alternateDirection == .englishToVietnamese)
    }

    @Test func ambiguousTextIsTranslatedByGuessAndMarked() async {
        let (_, translator, popup) = await start("OK", detection: nil)
        #expect(translator.directions == [.englishToVietnamese])
        #expect(popup.current?.title == "English → Vietnamese (guessed)")
        #expect(popup.current?.alternateDirection == .vietnameseToEnglish)
    }

    @Test func otherLanguageTranslatesToVietnamese() async {
        let (_, translator, popup) = await start(detection: .other("fr"))
        #expect(translator.directions.first?.source.code == "fr")
        #expect(translator.directions.first?.target == .vietnamese)
        #expect(popup.current?.title == "French → Vietnamese")
        #expect(popup.current?.alternateDirection?.title == "French → English")
    }

    @Test func textWithoutWordsShowsNoticeAndNeverTranslates() async {
        let (flow, translator, popup) = await start("https://example.com", detection: nil)
        #expect(translator.inputs.isEmpty)
        #expect(popup.current?.body == TranslationCoordinator.nothingToTranslateMessage)
        #expect(popup.current?.phase == .notice)
        #expect(popup.current?.alternateDirection == nil)
        await flow.noticeTask?.value
        #expect(!popup.isVisible)
    }

    @Test func switchingMidStreamRestartsAndOldDeltasNeverAppear() async {
        let (flow, translator, popup) = await start(detection: .ambiguous(bestGuess: .english))
        translator.send("Xin ")
        await settle { popup.current?.body == "Xin " }
        let oldSession = popup.current?.session

        popup.onAction?(.switchDirection)
        await settle { translator.inputs.count == 2 }
        #expect(translator.directions == [.englishToVietnamese, .vietnameseToEnglish])
        #expect(translator.inputs == ["Hello world", "Hello world"])
        #expect(popup.current?.phase == .loading)
        #expect(popup.current?.body == "")
        // The user chose it, so it is no longer a guess.
        #expect(popup.current?.title == "Vietnamese → English")
        #expect(popup.current?.session != oldSession)
        await settle { translator.terminatedRequests == [0] }
        #expect(translator.terminatedRequests == [0])

        translator.send("chào", request: 0)
        translator.send("Hello", request: 1)
        translator.finish(request: 1)
        await flow.translationTask?.value
        #expect(popup.current?.body == "Hello")
        #expect(popup.current?.phase == .done)
        #expect(popup.current?.alternateDirection == .englishToVietnamese)
    }

    @Test func switchingAfterDoneAndBackAgain() async {
        let (flow, translator, popup) = await start()
        translator.send("Xin chào")
        translator.finish()
        await flow.translationTask?.value
        flow.switchDirection()
        await settle { translator.inputs.count == 2 }
        flow.switchDirection()
        await settle { translator.inputs.count == 3 }
        #expect(translator.directions == [.englishToVietnamese, .vietnameseToEnglish, .englishToVietnamese])
        #expect(popup.current?.title == "English → Vietnamese")
        #expect(popup.current?.phase == .loading)
    }

    @Test func switchingAfterDismissDoesNothing() async {
        let (flow, translator, popup) = await start()
        await settle { translator.inputs.count == 1 }
        popup.dismissByUser()
        flow.switchDirection()
        await flow.translationTask?.value
        #expect(translator.inputs.count == 1)
        #expect(!popup.isVisible)
    }
}

@MainActor
struct PlaceholderTranslationTests {
    @Test func chunksRejoinToTheExactText() {
        let text = "  Xin  chào\nbạn 👋 nhé\t"
        let chunks = PlaceholderTranslationService.chunks(of: text)
        #expect(chunks.joined() == text)
        // “  ”, “Xin  ”, “chào\n”, “bạn ”, “👋 ”, “nhé\t”
        #expect(chunks.count == 6)
    }

    @Test func streamEchoesTheSelection() async throws {
        let service = PlaceholderTranslationService(initialDelay: .zero, totalDuration: .zero)
        var output = ""
        for try await delta in service.translate("Hello world", direction: .englishToVietnamese) { output += delta }
        #expect(output == "Hello world")
    }

    @Test func failureMessagesFollowPlanAndCompatibility() {
        #expect(SelectionFailure.noSelection.popupMessage == "No text selected.")
        #expect(SelectionFailure.permissionMissing.popupMessage == "Undertone needs Accessibility permission to read selected text.")
        #expect(SelectionFailure.secureInput.popupMessage != nil)
        #expect(SelectionFailure.focusChanged.popupMessage == nil)
        #expect(SelectionFailure.cancelled.popupMessage == nil)
    }

    /// S26: every capture failure has a decided popup (or none) and only the
    /// permission case offers System Settings.
    @Test(arguments: [
        (SelectionFailure.noSelection, "No text selected." as String?),
        (.permissionMissing, "Undertone needs Accessibility permission to read selected text."),
        (.unsupported, "Can't read selected text in this app."),
        (.noFocusedElement, "Can't read selected text in this app."),
        (.axError(-25204), "Can't read selected text in this app."),
        (.secureInput, "Secure input is on. Selected text isn't read."),
        (.timedOut, "The app didn't respond. Try again."),
        (.selectionChanged, "The selection changed. Try again."),
        (.focusChanged, nil),
        (.cancelled, nil),
        (.sourceIsSelf, nil),
        (.noFrontmostApp, nil),
    ])
    func everySelectionFailureHasADecidedPopup(_ failure: SelectionFailure, _ message: String?) {
        #expect(failure.popupMessage == message)
        #expect((failure.popupAction == .openAccessibilitySettings) == (failure == .permissionMissing))
    }
}

@MainActor
private final class SuspendedSelectionCapturer: SelectionCapturing {
    let starts: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private var pending: [CheckedContinuation<Result<SelectionSnapshot, SelectionFailure>, Never>] = []

    init() {
        (starts, signal) = AsyncStream<Void>.makeStream()
    }

    func capture() async -> Result<SelectionSnapshot, SelectionFailure> {
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            signal.yield(())
        }
    }

    func complete(_ index: Int, with result: Result<SelectionSnapshot, SelectionFailure>) {
        pending[index].resume(returning: result)
    }
}

@MainActor
struct OllamaTranslationServiceTests {
    @Test func streamsFromConfiguredModelWithKeepAliveAndPrompt() async throws {
        let transport = MockTransport.ollama(models: ["translategemma:12b"], reply: "Thanh toán đã được xử lý.")
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: transport)
        let service = OllamaTranslationService(readiness: readiness)
        #expect(service.title(for: .englishToVietnamese) == "English → Vietnamese")
        var output = ""
        var deltas = 0
        for try await delta in service.translate("The payment has been processed.", direction: .englishToVietnamese) {
            output += delta
            deltas += 1
        }
        #expect(output == "Thanh toán đã được xử lý.")
        #expect(deltas > 1)
        let body = try JSONSerialization.jsonObject(with: transport.requests.last?.httpBody ?? Data()) as? [String: Any]
        #expect(body?["keep_alive"] as? String == "30m")
        #expect(body?["stream"] as? Bool == true)
        #expect(body?["model"] as? String == "translategemma:12b")
        let prompt = ((body?["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
        #expect(prompt.hasPrefix("You are a professional English (en) to Vietnamese (vi) translator."))
        #expect(prompt.hasSuffix("\n\n\nThe payment has been processed."))
    }

    @Test func vietnameseToEnglishUsesThatPrompt() async throws {
        let transport = MockTransport.ollama(models: ["translategemma:12b"], reply: "Done.")
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: transport)
        for try await _ in OllamaTranslationService(readiness: readiness).translate("Xong.", direction: .vietnameseToEnglish) {}
        let body = try JSONSerialization.jsonObject(with: transport.requests.last?.httpBody ?? Data()) as? [String: Any]
        let prompt = ((body?["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
        #expect(prompt.hasPrefix("You are a professional Vietnamese (vi) to English (en) translator."))
        #expect(prompt.hasSuffix("Please translate the following Vietnamese text into English:\n\n\nXong."))
    }

    @Test func sendsTheFixedContextWindow() async throws {
        let transport = MockTransport.ollama(models: ["translategemma:12b"])
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: transport)
        for try await _ in OllamaTranslationService(readiness: readiness).translate("Hi", direction: .englishToVietnamese) {}
        let body = try JSONSerialization.jsonObject(with: transport.requests.last?.httpBody ?? Data()) as? [String: Any]
        #expect((body?["options"] as? [String: Any])?["num_ctx"] as? Int == TranslationBudget.contextTokens)
    }

    @Test func tooLongTextIsRefusedBeforeSending() async {
        let transport = MockTransport.ollama(models: ["translategemma:12b"])
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: transport)
        let text = String(repeating: "word ", count: TranslationBudget.maxBytes / 5 + 1)
        await #expect(throws: OllamaError.inputTooLong) {
            for try await _ in OllamaTranslationService(readiness: readiness).translate(text, direction: .englishToVietnamese) {}
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func runtimeFailureRefreshesReadiness() async {
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: MockTransport.refusing())
        let service = OllamaTranslationService(readiness: readiness)
        await #expect(throws: OllamaError.runtimeUnavailable) {
            for try await _ in service.translate("Hi", direction: .englishToVietnamese) {}
        }
        await settle { readiness.runtime == .notRunning }
        #expect(readiness.runtime == .notRunning)
    }

    @Test func nonLocalEndpointNeverSends() async {
        let transport = MockTransport.ollama(models: ["translategemma:12b"])
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(baseURLString: "http://10.0.0.5:11434"), transport: transport)
        await #expect(throws: OllamaError.endpointRejected) {
            for try await _ in OllamaTranslationService(readiness: readiness).translate("secret", direction: .englishToVietnamese) {}
        }
        #expect(transport.requests.isEmpty)
    }
}
