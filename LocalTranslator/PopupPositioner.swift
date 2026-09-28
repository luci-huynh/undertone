import CoreGraphics

/// Places the popup next to its anchor, inside the anchor screen's visible
/// frame. All values are AppKit global points.
nonisolated enum PopupPositioner {
    /// Distance kept from the visible frame's edges.
    static let screenMargin: CGFloat = 8
    /// Gap between the selection and the popup.
    static let selectionGap: CGFloat = 6
    /// A cursor anchor is the pointer tip; leave room for the pointer itself.
    static let cursorGap: CGFloat = 20

    /// Largest popup size that fits the visible frame with margins.
    static func maxSize(in visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: max(0, visibleFrame.width - 2 * screenMargin),
            height: max(0, visibleFrame.height - 2 * screenMargin)
        )
    }

    /// Prefers below the anchor, left edges aligned; flips above when below
    /// does not fit; otherwise uses the roomier side. The result is always
    /// clamped into the visible frame (a popup larger than the frame is
    /// pinned to its top-left).
    static func frame(for size: CGSize, anchor: SelectionAnchor) -> CGRect {
        let visible = anchor.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let gap = anchor.source == .mouse ? cursorGap : selectionGap
        let target = anchor.rect

        let belowY = target.minY - gap - size.height
        let aboveY = target.maxY + gap
        let fitsBelow = belowY >= visible.minY
        let fitsAbove = aboveY + size.height <= visible.maxY
        let y: CGFloat
        if fitsBelow {
            y = belowY
        } else if fitsAbove {
            y = aboveY
        } else {
            let spaceBelow = target.minY - visible.minY
            let spaceAbove = visible.maxY - target.maxY
            y = spaceBelow >= spaceAbove ? belowY : aboveY
        }

        let x = min(max(target.minX, visible.minX), visible.maxX - size.width)
        let clampedY = min(max(y, visible.minY), visible.maxY - size.height)
        // When the popup is wider/taller than the frame, pin to the top-left.
        return CGRect(
            x: size.width > visible.width ? visible.minX : x,
            y: size.height > visible.height ? visible.maxY - size.height : clampedY,
            width: size.width,
            height: size.height
        )
    }

    /// After the user dragged the popup (S25): keep its top-left corner while
    /// it grows or shrinks, clamped into the visible frame it was dropped on.
    static func frame(for size: CGSize, keepingTopLeft topLeft: CGPoint, in visibleFrame: CGRect) -> CGRect {
        let visible = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let x = min(max(topLeft.x, visible.minX), visible.maxX - size.width)
        let y = min(max(topLeft.y - size.height, visible.minY), visible.maxY - size.height)
        return CGRect(
            x: size.width > visible.width ? visible.minX : x,
            y: size.height > visible.height ? visible.maxY - size.height : y,
            width: size.width,
            height: size.height
        )
    }
}
