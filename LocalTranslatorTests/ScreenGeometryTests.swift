import CoreGraphics
import Testing
@testable import Undertone

/// Layouts in AppKit points. Primary 1440×900 (menu bar 25 pt); a Retina
/// display reports points too, so no scale factor appears anywhere.
private let primary = ScreenLayout.Screen(
    frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
)
private let right = ScreenLayout.Screen(
    frame: CGRect(x: 1440, y: -180, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 1440, y: -180, width: 1920, height: 1055)
)
private let left = ScreenLayout.Screen(
    frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055)
)
private let above = ScreenLayout.Screen(
    frame: CGRect(x: 0, y: 900, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 0, y: 900, width: 2560, height: 1415)
)

struct ScreenGeometryTests {
    @Test func axRectIsFlippedAgainstPrimaryScreenOnly() {
        let ax = CGRect(x: 100, y: 50, width: 200, height: 30)
        #expect(ScreenGeometry.appKitRect(fromAX: ax, primaryFrame: primary.frame) == CGRect(x: 100, y: 820, width: 200, height: 30))
        // Secondary screen below the primary's top edge: AX y > 900.
        let onRight = CGRect(x: 1500, y: 1000, width: 100, height: 20)
        #expect(ScreenGeometry.appKitRect(fromAX: onRight, primaryFrame: primary.frame) == CGRect(x: 1500, y: -120, width: 100, height: 20))
        // Screen above the primary: negative AX y.
        let onAbove = CGRect(x: 10, y: -500, width: 100, height: 20)
        #expect(ScreenGeometry.appKitRect(fromAX: onAbove, primaryFrame: primary.frame) == CGRect(x: 10, y: 1380, width: 100, height: 20))
    }

    @Test func rectPicksScreenWithLargestOverlap() {
        let layout = ScreenLayout(screens: [primary, right])
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 1400, y: 100, width: 100, height: 20), in: layout) == 1)
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 1300, y: 100, width: 200, height: 20), in: layout) == 0)
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 5000, y: 100, width: 10, height: 10), in: layout) == nil)
    }

    @Test func pointOutsideEveryScreenUsesNearest() {
        let layout = ScreenLayout(screens: [primary, left])
        #expect(ScreenGeometry.screenIndex(containing: CGPoint(x: 720, y: 900), in: layout) == 0)
        #expect(ScreenGeometry.screenIndex(containing: CGPoint(x: -10, y: 500), in: layout) == 1)
        #expect(ScreenGeometry.screenIndex(containing: CGPoint(x: -3000, y: 500), in: layout) == 1)
        #expect(ScreenGeometry.screenIndex(containing: .zero, in: ScreenLayout(screens: [])) == nil)
    }
}

struct SelectionAnchorResolverTests {
    private let mouse = CGPoint(x: 700, y: 400)

    private func resolve(_ ax: CGRect?, mouse: CGPoint? = nil, screens: [ScreenLayout.Screen] = [primary, right, left, above]) -> SelectionAnchor? {
        SelectionAnchorResolver.resolve(axBounds: ax, mouseLocation: mouse ?? self.mouse, layout: ScreenLayout(screens: screens))
    }

    @Test func boundsOnEachScreenLandOnThatScreen() {
        #expect(resolve(CGRect(x: 100, y: 100, width: 50, height: 20))?.screenIndex == 0)
        #expect(resolve(CGRect(x: 2000, y: 1000, width: 50, height: 20))?.screenIndex == 1)
        #expect(resolve(CGRect(x: -1000, y: 500, width: 50, height: 20))?.screenIndex == 2)
        #expect(resolve(CGRect(x: 500, y: -700, width: 50, height: 20))?.screenIndex == 3)
        #expect(resolve(CGRect(x: 100, y: 100, width: 50, height: 20))?.source == .selectionBounds)
    }

    @Test func multiLineUnionRectIsKeptWhole() {
        let anchor = resolve(CGRect(x: 80, y: 200, width: 600, height: 60))
        #expect(anchor?.source == .selectionBounds)
        #expect(anchor?.rect == CGRect(x: 80, y: 640, width: 600, height: 60))
    }

    @Test func rectPartlyOffscreenIsClippedToVisibleFrame() {
        // Starts under the menu bar and runs past the right edge of the only screen.
        let anchor = resolve(CGRect(x: 1400, y: 10, width: 200, height: 40), screens: [primary])
        #expect(anchor?.source == .selectionBounds)
        #expect(anchor?.rect == CGRect(x: 1400, y: 850, width: 40, height: 25))
    }

    @Test func zeroOrGarbageBoundsFallBackToMouse() {
        #expect(resolve(nil)?.source == .mouse)
        #expect(resolve(.zero)?.source == .mouse)
        #expect(resolve(CGRect(x: 100, y: 100, width: -5, height: 20))?.source == .mouse)
        #expect(resolve(CGRect(x: CGFloat.nan, y: 100, width: 5, height: 20))?.source == .mouse)
        #expect(resolve(CGRect(x: 1e9, y: 100, width: 5, height: 20))?.source == .mouse)
    }

    @Test func zeroWidthBoundsAreStillUsable() {
        // Some apps report a caret-like rect for a selection end.
        let anchor = resolve(CGRect(x: 300, y: 100, width: 0, height: 18))
        #expect(anchor?.source == .selectionBounds)
        #expect(anchor?.rect == CGRect(x: 300, y: 782, width: 0, height: 18))
    }

    @Test func offscreenBoundsFallBackToMouse() {
        let anchor = resolve(CGRect(x: 9000, y: 100, width: 50, height: 20))
        #expect(anchor == SelectionAnchor(source: .mouse, rect: CGRect(origin: mouse, size: .zero), screenIndex: 0, visibleFrame: primary.visibleFrame))
    }

    @Test func mouseIsClampedIntoVisibleFrameOfItsScreen() {
        // Cursor on the menu bar of the primary screen.
        let menuBar = resolve(nil, mouse: CGPoint(x: 720, y: 890))
        #expect(menuBar?.rect.origin == CGPoint(x: 720, y: 875))
        // Cursor at the bottom-left corner of the right screen (below the primary).
        let corner = resolve(nil, mouse: CGPoint(x: 1440, y: -180), screens: [primary, right])
        #expect(corner?.screenIndex == 1)
        #expect(corner?.visibleFrame == right.visibleFrame)
    }

    @Test func noScreensGivesNoAnchor() {
        #expect(resolve(CGRect(x: 1, y: 1, width: 1, height: 1), screens: []) == nil)
    }
}
