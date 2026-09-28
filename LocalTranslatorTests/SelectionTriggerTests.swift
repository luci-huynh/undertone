import CoreGraphics
import Foundation
import Testing
@testable import LocalTranslator

private func snapshot(_ text: String) -> SelectionSnapshot {
    SelectionSnapshot(sourcePID: 42, sourceAppName: "TextEdit", text: text, range: nil, anchor: nil, capturedAt: Date())
}

private let start = CGPoint(x: 100, y: 100)
private let far = CGPoint(x: 160, y: 100)

/// S24 lifecycle: when the button appears and disappears, one read per
/// gesture, nothing when disabled, shortcut path unchanged.
@MainActor
struct SelectionTriggerTests {
    private func make(
        _ results: [Result<SelectionSnapshot, SelectionFailure>] = [.success(snapshot("Hello world"))],
        enabled: Bool = true,
        visibleDuration: Duration = .seconds(60)
    ) -> (SelectionTriggerService, FakeSelectionEvents, FakeTriggerPresenter, FakeSelectionCapturer) {
        let events = FakeSelectionEvents()
        let presenter = FakeTriggerPresenter()
        let selection = FakeSelectionCapturer(results: results)
        let trigger = SelectionTriggerService.fake(
            selection: selection, presenter: presenter, events: events,
            settings: MemoryTriggerSettings(enabled), visibleDuration: visibleDuration
        )
        trigger.start()
        return (trigger, events, presenter, selection)
    }

    @Test func dragSelectionShowsTheButtonNearThePointer() async {
        let (trigger, events, presenter, selection) = make()
        events.send(.down(start), .dragged(far), .up(clickCount: 1))
        await trigger.pendingTask?.value
        #expect(selection.captureCount == 1)
        #expect(presenter.isVisible)
        #expect(presenter.shownAt == [cursorTestAnchor])
    }

    @Test func doubleClickShowsTheButton() async {
        let (trigger, events, presenter, _) = make()
        events.send(.down(start), .up(clickCount: 1), .down(start), .up(clickCount: 2))
        await trigger.pendingTask?.value
        #expect(presenter.isVisible)
    }

    @Test func plainClickOrTinyDragReadsNothing() async {
        let (trigger, events, presenter, selection) = make()
        events.send(.down(start), .up(clickCount: 1))
        events.send(.down(start), .dragged(CGPoint(x: 102, y: 101)), .up(clickCount: 1))
        await trigger.pendingTask?.value
        #expect(selection.captureCount == 0)
        #expect(!presenter.isVisible)
    }

    @Test func tripleClickReadsOnceAfterTheClicksSettle() async {
        let events = FakeSelectionEvents()
        let presenter = FakeTriggerPresenter()
        let selection = FakeSelectionCapturer(results: [.success(snapshot("A whole line"))])
        let trigger = SelectionTriggerService(
            selection: selection, presenter: presenter, events: events, settings: MemoryTriggerSettings(),
            cursorAnchor: { cursorTestAnchor }, settleDelay: .milliseconds(100), visibleDuration: .seconds(60)
        )
        trigger.start()
        events.send(.down(start), .up(clickCount: 1), .down(start), .up(clickCount: 2), .down(start), .up(clickCount: 3))
        await trigger.pendingTask?.value
        #expect(selection.captureCount == 1)
        #expect(presenter.isVisible)
    }

    @Test(arguments: [SelectionFailure.secureInput, .unsupported, .noSelection, .noFocusedElement, .permissionMissing, .sourceIsSelf, .timedOut])
    func unreadableSelectionShowsNothing(_ failure: SelectionFailure) async {
        let (trigger, events, presenter, _) = make([.failure(failure)])
        events.send(.down(start), .dragged(far), .up(clickCount: 1))
        await trigger.pendingTask?.value
        #expect(!presenter.isVisible)
    }

    @Test func whitespaceOnlySelectionShowsNothing() async {
        let (trigger, events, presenter, _) = make([.success(snapshot("  \n "))])
        events.send(.down(start), .dragged(far), .up(clickCount: 1))
        await trigger.pendingTask?.value
        #expect(!presenter.isVisible)
    }

    @Test(arguments: [SelectionMouseEvent.down(far), .scroll, .appSwitched])
    func clickElsewhereScrollOrAppSwitchHides(_ event: SelectionMouseEvent) async {
        let (trigger, events, presenter, _) = make()
        events.send(.down(start), .dragged(far), .up(clickCount: 1))
        await trigger.pendingTask?.value
        #expect(presenter.isVisible)
        events.send(event)
        #expect(!presenter.isVisible)
    }

    @Test func hidesByItselfAfterTheVisibleDuration() async {
        let (trigger, events, presenter, _) = make(visibleDuration: .milliseconds(50))
        events.send(.down(start), .dragged(far), .up(clickCount: 1))
        await trigger.pendingTask?.value
        #expect(presenter.isVisible)
        await trigger.hideTask?.value
        #expect(!presenter.isVisible)
    }

    @Test func aReadFinishingAfterTheNextClickIsDropped() async {
        let events = FakeSelectionEvents()
        let presenter = FakeTriggerPresenter()
        let selection = SlowCapturer()
        let trigger = SelectionTriggerService(
            selection: selection, presenter: presenter, events: events, settings: MemoryTriggerSettings(),
            cursorAnchor: { cursorTestAnchor }, settleDelay: .zero, visibleDuration: .seconds(60)
        )
        trigger.start()
        events.send(.down(start), .dragged(far), .up(clickCount: 1))
        for _ in 0..<50 where !selection.started { await Task.yield() }
        // The user clicked somewhere else while the read was in flight.
        events.send(.down(far))
        selection.finish(.success(snapshot("Old")))
        for _ in 0..<50 { await Task.yield() }
        #expect(!presenter.isVisible)
    }

    @Test func clickingTheButtonStartsTheTranslationFlowAndHides() async {
        let (trigger, events, presenter, _) = make()
        var triggered = 0
        trigger.onTrigger = { triggered += 1 }
        events.send(.down(start), .dragged(far), .up(clickCount: 1))
        await trigger.pendingTask?.value
        presenter.click()
        #expect(triggered == 1)
        #expect(!presenter.isVisible)
    }

    @Test func disabledInstallsNoMonitorAndReadsNothing() async {
        let (trigger, events, presenter, selection) = make(enabled: false)
        #expect(!events.isRunning)
        events.send(.down(start), .dragged(far), .up(clickCount: 1))
        await trigger.pendingTask?.value
        #expect(selection.captureCount == 0)
        #expect(!presenter.isVisible)
    }

    @Test func toggleStoresTheChoiceAndStartsOrStopsTheMonitor() {
        let settings = MemoryTriggerSettings(true)
        let events = FakeSelectionEvents()
        let trigger = SelectionTriggerService.fake(events: events, settings: settings)
        trigger.start()
        #expect(events.isRunning)
        trigger.setEnabled(false)
        #expect(!events.isRunning && !settings.showsSelectionTrigger && !trigger.isEnabled)
        trigger.setEnabled(true)
        #expect(events.isRunning && settings.showsSelectionTrigger)
        trigger.stop()
        #expect(!events.isRunning)
    }

    @Test func defaultSettingIsOn() {
        // One fixed suite, emptied afterwards: macOS keeps an empty plist for
        // it, so runs do not pile up files (S26).
        let suite = "local.chienhuynh.LocalTranslator.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = UserDefaultsSelectionTriggerSettings(defaults: defaults)
        #expect(settings.showsSelectionTrigger)
        settings.showsSelectionTrigger = false
        #expect(!UserDefaultsSelectionTriggerSettings(defaults: defaults).showsSelectionTrigger)
    }

    @Test func shortcutStillWorksAndRemovesTheButton() async {
        let shortcut = GlobalShortcutService.fake()
        let popup = FakePopupPresenter()
        let flow = TranslationCoordinator.fake(popup: popup)
        let events = FakeSelectionEvents()
        let presenter = FakeTriggerPresenter()
        let trigger = SelectionTriggerService.fake(
            selection: FakeSelectionCapturer(results: [.success(snapshot("Hello world"))]), presenter: presenter, events: events
        )
        let app = AppCoordinator.fake(shortcut: shortcut, flow: flow, selectionTrigger: trigger)
        app.start()
        events.send(.down(start), .dragged(far), .up(clickCount: 1))
        await trigger.pendingTask?.value
        #expect(presenter.isVisible)
        shortcut.onTrigger?()
        #expect(!presenter.isVisible)
        await flow.captureTask?.value
        #expect(popup.current?.body == "No text selected.")
        app.shutdown()
        #expect(!events.isRunning)
    }
}

/// A capture the test completes by hand.
@MainActor
private final class SlowCapturer: SelectionCapturing {
    private var continuation: CheckedContinuation<Result<SelectionSnapshot, SelectionFailure>, Never>?
    var started: Bool { continuation != nil }

    func capture() async -> Result<SelectionSnapshot, SelectionFailure> {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ result: Result<SelectionSnapshot, SelectionFailure>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

struct SelectionTriggerPlacementTests {
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func anchor(_ point: CGPoint) -> SelectionAnchor {
        SelectionAnchor(source: .mouse, rect: CGRect(origin: point, size: .zero), screenIndex: 0, visibleFrame: visible)
    }

    @Test func belowRightOfThePointer() {
        #expect(SelectionTriggerPlacement.frame(near: anchor(CGPoint(x: 500, y: 400))) == CGRect(x: 510, y: 360, width: 30, height: 30))
    }

    @Test func flipsAtTheRightAndBottomEdges() {
        let frame = SelectionTriggerPlacement.frame(near: anchor(CGPoint(x: 995, y: 5)))
        #expect(frame == CGRect(x: 955, y: 15, width: 30, height: 30))
    }

    @Test func staysOnASecondScreenWithNegativeCoordinates() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let frame = SelectionTriggerPlacement.frame(near: SelectionAnchor(source: .mouse, rect: CGRect(x: -1435, y: 890, width: 0, height: 0), screenIndex: 1, visibleFrame: left))
        #expect(left.contains(frame))
    }
}
