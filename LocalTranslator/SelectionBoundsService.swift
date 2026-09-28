import ApplicationServices
import CoreGraphics

/// Where the popup should attach, in AppKit global coordinates (points).
nonisolated struct SelectionAnchor: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// Bounds of the selected range reported by the source app.
        case selectionBounds
        /// Cursor position captured at trigger time (bounds missing or unusable).
        case mouse
    }

    let source: Source
    /// Selection rect clipped to the screen's visible frame, or a zero-size
    /// rect at the clamped cursor position.
    let rect: CGRect
    let screenIndex: Int
    /// Usable area of the anchor's screen; the popup must stay inside it.
    let visibleFrame: CGRect
}

nonisolated enum SelectionAnchorResolver {
    /// Largest plausible rect edge in points; larger values are treated as garbage.
    private static let maxDimension: CGFloat = 100_000

    /// - Parameters:
    ///   - axBounds: `kAXBoundsForRangeParameterizedAttribute` result in AX
    ///     coordinates; for a multi-line selection usually the union rect.
    ///   - mouseLocation: `NSEvent.mouseLocation` captured at trigger.
    /// - Returns: nil only when there is no screen at all.
    static func resolve(axBounds: CGRect?, mouseLocation: CGPoint, layout: ScreenLayout) -> SelectionAnchor? {
        guard let primary = layout.screens.first else { return nil }
        if let axBounds, isUsable(axBounds) {
            let rect = ScreenGeometry.appKitRect(fromAX: axBounds, primaryFrame: primary.frame)
            if let index = ScreenGeometry.screenIndex(for: rect, in: layout) {
                let visible = layout.screens[index].visibleFrame
                let clipped = rect.intersection(visible)
                if !clipped.isNull {
                    return SelectionAnchor(source: .selectionBounds, rect: clipped, screenIndex: index, visibleFrame: visible)
                }
            }
        }
        guard let index = ScreenGeometry.screenIndex(containing: mouseLocation, in: layout) else { return nil }
        let visible = layout.screens[index].visibleFrame
        let point = ScreenGeometry.clamp(mouseLocation, to: visible)
        return SelectionAnchor(source: .mouse, rect: CGRect(origin: point, size: .zero), screenIndex: index, visibleFrame: visible)
    }

    /// Rejects the zero rect some apps return for "unknown", negative sizes,
    /// NaN/infinite and absurd values.
    private static func isUsable(_ rect: CGRect) -> Bool {
        // `size`, not `width`/`height`: those standardize and hide negative sizes.
        let size = rect.size
        let values = [rect.origin.x, rect.origin.y, size.width, size.height]
        guard values.allSatisfy({ $0.isFinite && abs($0) < maxDimension }) else { return false }
        guard size.width >= 0, size.height >= 0 else { return false }
        return size.width > 0 || size.height > 0
    }
}

/// Reads the bounds of a selected range. Called on the AX queue as part of
/// the focused-element read; the element is never kept afterwards.
nonisolated enum AXSelectionBounds {
    static func read(element: AXUIElement, range: NSRange) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success,
            let boundsValue,
            CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }
}
