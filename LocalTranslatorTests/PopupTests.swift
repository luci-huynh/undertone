import CoreGraphics
import SwiftUI
import Testing
@testable import Undertone

private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
private let size = CGSize(width: 300, height: 120)

private func anchor(_ rect: CGRect, _ source: SelectionAnchor.Source = .selectionBounds, visibleFrame: CGRect = visible) -> SelectionAnchor {
    SelectionAnchor(source: source, rect: rect, screenIndex: 0, visibleFrame: visibleFrame)
}

struct PopupPositionerTests {
    @Test func placesBelowSelectionWithLeftEdgesAligned() {
        let frame = PopupPositioner.frame(for: size, anchor: anchor(CGRect(x: 200, y: 500, width: 100, height: 20)))
        #expect(frame == CGRect(x: 200, y: 500 - 6 - 120, width: 300, height: 120))
    }

    @Test func flipsAboveNearBottomEdge() {
        let frame = PopupPositioner.frame(for: size, anchor: anchor(CGRect(x: 200, y: 60, width: 100, height: 20)))
        #expect(frame.minY == CGFloat(86))
    }

    @Test func tallSelectionUsesRoomierSideAndStaysOnScreen() {
        // Selection covers most of the screen: neither side fits.
        let frame = PopupPositioner.frame(for: size, anchor: anchor(CGRect(x: 100, y: 100, width: 800, height: 700)))
        #expect(visible.insetBy(dx: 8, dy: 8).contains(frame))
    }

    @Test func clampsAtRightAndLeftEdges() {
        let right = PopupPositioner.frame(for: size, anchor: anchor(CGRect(x: 1400, y: 500, width: 30, height: 20)))
        #expect(right.maxX == CGFloat(1432))
        let left = PopupPositioner.frame(for: size, anchor: anchor(CGRect(x: -50, y: 500, width: 30, height: 20)))
        #expect(left.minX == CGFloat(8))
    }

    @Test func cursorAnchorLeavesRoomForPointer() {
        let frame = PopupPositioner.frame(for: size, anchor: anchor(CGRect(x: 400, y: 400, width: 0, height: 0), .mouse))
        #expect(frame.maxY == CGFloat(380))
        #expect(frame.minX == CGFloat(400))
    }

    @Test func worksOnSecondaryScreenWithNegativeCoordinates() {
        let secondary = CGRect(x: 1440, y: -180, width: 1920, height: 1055)
        let frame = PopupPositioner.frame(for: size, anchor: anchor(CGRect(x: 1500, y: -150, width: 60, height: 20), visibleFrame: secondary))
        #expect(secondary.insetBy(dx: 8, dy: 8).contains(frame))
        #expect(frame.minY == CGFloat(-124))
    }

    @Test func oversizedPopupIsPinnedTopLeft() {
        let small = CGRect(x: 0, y: 0, width: 200, height: 100)
        let frame = PopupPositioner.frame(for: size, anchor: anchor(CGRect(x: 50, y: 50, width: 10, height: 10), visibleFrame: small))
        #expect(frame.minX == CGFloat(8))
        #expect(frame.maxY == CGFloat(92))
    }
}

@MainActor
struct PopupMetricsTests {
    private let screen = CGSize(width: 1424, height: 859)

    @Test func shortTextUsesMinimumWidthAndOneLine() {
        let layout = PopupMetrics.layout(for: "Xin chào", maxSize: screen)
        #expect(layout.width == PopupMetrics.minWidth)
        // One 14 pt line (≈ 17 pt + slack), no empty gap below it (S25).
        #expect(layout.bodyHeight >= PopupMetrics.minBodyHeight && layout.bodyHeight < 26)
    }

    @Test func lineSpacingIsPartOfTheMeasuredHeight() {
        let threeLines = "Ỹ ỹ Ậ ậ\nỮ ữ Ặ ặ\nNgười dùng"
        let layout = PopupMetrics.layout(for: threeLines, maxSize: screen)
        // Three lines of 14 pt text plus two line gaps.
        #expect(layout.bodyHeight >= 3 * 16 + 2 * PopupMetrics.lineSpacing)
    }

    @Test func longTextWrapsAtMaximumWidthAndIsCapped() {
        let long = String(repeating: "Thanh toán này đã được xử lý. ", count: 200)
        let layout = PopupMetrics.layout(for: long, maxSize: screen)
        #expect(layout.width == PopupMetrics.maxWidth)
        #expect(layout.bodyHeight == PopupMetrics.maxBodyHeight)
    }

    @Test func moreLinesGrowHeight() {
        let two = PopupMetrics.layout(for: "a\nb", maxSize: screen).bodyHeight
        let six = PopupMetrics.layout(for: "a\nb\nc\nd\ne\nf", maxSize: screen).bodyHeight
        #expect(six > two)
    }

    @Test func narrowScreenLimitsWidth() {
        let layout = PopupMetrics.layout(for: String(repeating: "word ", count: 100), maxSize: CGSize(width: 300, height: 500))
        #expect(layout.width == CGFloat(300))
    }
}

private final class FakePopupWindow: PopupWindowing {
    var onCancel: (() -> Void)?
    var onUserMoved: ((CGRect, CGRect) -> Void)?
    var fitting = CGSize(width: 300, height: 120)
    private(set) var presented: [(frame: CGRect, raise: Bool, makeKey: Bool)] = []
    private(set) var dismissCount = 0

    func fittingSize(for view: AnyView) -> CGSize { fitting }

    func present(_ view: AnyView, frame: CGRect, raise: Bool, makeKey: Bool) {
        presented.append((frame, raise, makeKey))
    }

    func dismiss() { dismissCount += 1 }
}

@MainActor
struct TranslationPanelControllerTests {
    private let content = PopupContent(title: "English → Vietnamese", body: "Thanh toán này đã được xử lý.")
    private let selection = anchor(CGRect(x: 200, y: 500, width: 100, height: 20))

    private func make(escapeFailure: HotKeyRegistrationError? = nil) -> (TranslationPanelController, FakePopupWindow, FakeHotKeyRegistrar, Box) {
        let window = FakePopupWindow()
        let escape = FakeHotKeyRegistrar()
        escape.failure = escapeFailure
        let copied = Box()
        let controller = TranslationPanelController(window: window, escape: escape, copyToPasteboard: { copied.values.append($0) })
        return (controller, window, escape, copied)
    }

    final class Box { var values: [String] = [] }

    @Test func aMovedPopupKeepsItsPlaceForTheSameSelection() {
        let (controller, window, _, _) = make()
        controller.show(content, at: selection)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        window.onUserMoved?(CGRect(x: 900, y: 600, width: 300, height: 120), screen)
        // Streaming makes it taller: same top-left corner.
        window.fitting = CGSize(width: 300, height: 200)
        let longer = PopupContent(title: content.title, body: String(repeating: "Thanh toán này đã được xử lý. ", count: 8))
        controller.show(longer, at: selection)
        #expect(window.presented.last?.frame == CGRect(x: 900, y: 520, width: 300, height: 200))

        // Another selection: back next to it.
        let other = anchor(CGRect(x: 100, y: 300, width: 80, height: 20))
        controller.show(longer, at: other)
        #expect(window.presented.last?.frame == PopupPositioner.frame(for: CGSize(width: 300, height: 200), anchor: other))
    }

    @Test func closingForgetsTheMovedPlace() {
        let (controller, window, _, _) = make()
        controller.show(content, at: selection)
        window.onUserMoved?(CGRect(x: 900, y: 600, width: 300, height: 120), CGRect(x: 0, y: 0, width: 1440, height: 875))
        controller.close()
        controller.show(content, at: selection)
        #expect(window.presented.last?.frame == PopupPositioner.frame(for: window.fitting, anchor: selection))
    }

    @Test func moveReportsWhileHiddenAreIgnored() {
        let (controller, window, _, _) = make()
        window.onUserMoved?(CGRect(x: 900, y: 600, width: 300, height: 120), CGRect(x: 0, y: 0, width: 1440, height: 875))
        controller.show(content, at: selection)
        #expect(window.presented.last?.frame == PopupPositioner.frame(for: window.fitting, anchor: selection))
    }

    @Test func showPresentsWithoutKeyAndRegistersEscOnce() {
        let (controller, window, escape, _) = make()
        controller.show(content, at: selection)
        controller.show(content, at: selection)
        #expect(controller.isVisible)
        #expect(escape.registered == .escape)
        #expect(escape.registerCount == 1)
        #expect(window.presented.count == 2)
        #expect(window.presented.allSatisfy { !$0.makeKey })
        #expect(visible.contains(controller.frame ?? .null))
    }

    @Test func escClosesAndReleasesHotKey() {
        let (controller, window, escape, _) = make()
        controller.show(content, at: selection)
        escape.send(.pressed)
        #expect(!controller.isVisible)
        #expect(escape.registered == nil)
        #expect(window.dismissCount == 1)
        escape.send(.pressed)
        #expect(window.dismissCount == 1)
    }

    @Test func repeatedOpenCloseDoesNotLeakRegistrations() {
        let (controller, _, escape, _) = make()
        for _ in 0..<5 {
            controller.show(content, at: selection)
            controller.close()
        }
        controller.close()
        #expect(escape.registerCount == 5)
        #expect(escape.unregisterCount == 5)
        #expect(escape.registered == nil)
    }

    @Test func panelCancelClosesToo() {
        let (controller, window, _, _) = make()
        controller.show(content, at: selection)
        window.onCancel?()
        #expect(!controller.isVisible)
    }

    @Test func aNewRequestComesToTheFrontAndItsStreamingRendersDoNot() {
        let (controller, window, _, _) = make()
        var first = content
        first.session = UUID()
        controller.show(first, at: selection)
        controller.show(first, at: selection)
        var second = content
        second.session = UUID()
        controller.show(second, at: selection)
        #expect(window.presented.map(\.raise) == [true, false, true])
        #expect(window.presented.allSatisfy { !$0.makeKey })
    }

    @Test func withoutTheEscKeyOnlyANewPresentationTakesFocus() {
        let (controller, window, _, _) = make(escapeFailure: .conflict)
        var request = content
        request.session = UUID()
        controller.show(request, at: selection)
        controller.show(request, at: selection)
        #expect(window.presented.map(\.makeKey) == [true, false])
    }

    @Test func escConflictFallsBackToKeyPanel() {
        let (controller, window, escape, _) = make(escapeFailure: .conflict)
        controller.show(content, at: selection)
        #expect(!controller.escapeRegistered)
        #expect(window.presented.last?.makeKey == true)
        controller.close()
        #expect(escape.unregisterCount == 0)
    }

    @Test func copyOnlyWhileShowingAndOnlyOnRequest() {
        let (controller, _, _, copied) = make()
        controller.copyContent()
        controller.show(content, at: selection)
        #expect(copied.values.isEmpty)
        controller.copyContent()
        #expect(copied.values == [content.body])
        controller.close()
        controller.copyContent()
        #expect(copied.values.count == 1)
    }

    @Test func streamingRendersReuseMeasurementWhileSizeIsUnchanged() {
        let (controller, window, _, _) = make()
        let session = UUID()
        controller.show(PopupContent(title: "t", body: "Một", phase: .streaming, session: session), at: selection)
        controller.show(PopupContent(title: "t", body: "Một hai", phase: .streaming, session: session), at: selection)
        controller.show(PopupContent(title: "t", body: "Một hai ba", phase: .streaming, session: session), at: selection)
        #expect(controller.measureCount == 1)
        #expect(window.presented.count == 3)
        // Growing past one line changes the layout, so it is measured again.
        controller.show(PopupContent(title: "t", body: String(repeating: "Một hai ba bốn năm. ", count: 30), phase: .streaming, session: session), at: selection)
        #expect(controller.measureCount == 2)
        // Finishing changes the chrome (Copy enabled), still same size key except phase.
        controller.show(PopupContent(title: "t", body: String(repeating: "Một hai ba bốn năm. ", count: 30), phase: .done, session: session), at: selection)
        #expect(controller.measureCount == 3)
        controller.close()
        controller.show(PopupContent(title: "t", body: "Một", phase: .streaming, session: UUID()), at: selection)
        #expect(controller.measureCount == 4)
    }

    @Test func tallContentIsShrunkToFitScreen() {
        let (controller, window, _, _) = make()
        window.fitting = CGSize(width: 300, height: 2000)
        let small = anchor(CGRect(x: 10, y: 10, width: 10, height: 10), visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 400))
        controller.show(content, at: small)
        // Fake window reports a fixed size, so the controller re-measured once.
        #expect(window.presented.count == 1)
        #expect(controller.frame != nil)
    }
}

@MainActor
struct PopupPhaseTests {
    @Test func copyOnlyForFinishedOutput() {
        #expect(!PopupContent(title: "t", body: "", phase: .loading).canCopy)
        #expect(!PopupContent(title: "t", body: "partial", phase: .streaming).canCopy)
        #expect(!PopupContent(title: "", body: "No text selected.", phase: .notice).canCopy)
        #expect(!PopupContent(title: "t", body: " \n", phase: .done).canCopy)
        #expect(PopupContent(title: "t", body: "Xin chào", phase: .done).canCopy)
    }

    @Test func userDismissNotifiesOwnerButProgrammaticCloseDoesNot() {
        let window = FakeWindowForDismiss()
        let escape = FakeHotKeyRegistrar()
        let controller = TranslationPanelController(window: window, escape: escape, copyToPasteboard: { _ in })
        var dismissed = 0
        controller.onDismiss = { dismissed += 1 }
        let anchor = SelectionAnchor(source: .mouse, rect: CGRect(x: 10, y: 10, width: 0, height: 0), screenIndex: 0, visibleFrame: testScreen)
        controller.show(PopupContent(title: "t", body: "b"), at: anchor)
        controller.close()
        #expect(dismissed == 0)
        controller.show(PopupContent(title: "t", body: "b"), at: anchor)
        escape.send(.pressed)
        #expect(dismissed == 1)
        controller.show(PopupContent(title: "t", body: "b"), at: anchor)
        window.onCancel?()
        #expect(dismissed == 2)
    }
}

private final class FakeWindowForDismiss: PopupWindowing {
    var onCancel: (() -> Void)?
    var onUserMoved: ((CGRect, CGRect) -> Void)?
    func fittingSize(for view: AnyView) -> CGSize { CGSize(width: 300, height: 100) }
    func present(_ view: AnyView, frame: CGRect, raise: Bool, makeKey: Bool) {}
    func dismiss() {}
}

struct MovedPopupPositionTests {
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func keepsTheTopLeftCorner() {
        let frame = PopupPositioner.frame(for: CGSize(width: 300, height: 100), keepingTopLeft: CGPoint(x: 200, y: 600), in: visible)
        #expect(frame == CGRect(x: 200, y: 500, width: 300, height: 100))
    }

    @Test func growingPastTheBottomStaysOnScreen() {
        let frame = PopupPositioner.frame(for: CGSize(width: 300, height: 300), keepingTopLeft: CGPoint(x: 900, y: 100), in: visible)
        #expect(visible.insetBy(dx: PopupPositioner.screenMargin, dy: PopupPositioner.screenMargin).contains(frame))
    }

    @Test func droppedOnASecondScreenStaysThere() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let frame = PopupPositioner.frame(for: CGSize(width: 300, height: 120), keepingTopLeft: CGPoint(x: -1500, y: 950), in: left)
        #expect(left.contains(frame))
    }
}
