import CoreGraphics

/// Screen arrangement in AppKit global coordinates (points, bottom-left origin,
/// y up). The first screen is the primary one (menu bar, frame origin 0,0);
/// AX/Quartz global coordinates are anchored to its top-left corner.
nonisolated struct ScreenLayout: Equatable, Sendable {
    nonisolated struct Screen: Equatable, Sendable {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    let screens: [Screen]
}

nonisolated enum ScreenGeometry {
    /// AX/Quartz global rect (top-left origin of the primary screen, y down)
    /// → AppKit global rect. Only the primary screen defines the flip; every
    /// other screen is already positioned relative to it in both systems.
    static func appKitRect(fromAX rect: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Screen showing the largest part of `rect`; nil when it is on no screen.
    static func screenIndex(for rect: CGRect, in layout: ScreenLayout) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in layout.screens.enumerated() {
            let overlap = rect.intersection(screen.frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? -1) { best = (index, area) }
        }
        return best?.index
    }

    /// Screen containing `point` (edges inclusive, so the top row of pixels
    /// counts), otherwise the nearest screen; nil only without screens.
    static func screenIndex(containing point: CGPoint, in layout: ScreenLayout) -> Int? {
        if let index = layout.screens.firstIndex(where: { contains($0.frame, point) }) {
            return index
        }
        return layout.screens.indices.min { distance(point, to: layout.screens[$0].frame) < distance(point, to: layout.screens[$1].frame) }
    }

    static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
    }

    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    private static func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let clamped = clamp(point, to: rect)
        return hypot(point.x - clamped.x, point.y - clamped.y)
    }
}
