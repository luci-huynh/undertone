import AppKit
import os
import SwiftUI

/// The window side of the popup, separated so the controller can be tested
/// without putting windows on screen.
protocol PopupWindowing: AnyObject {
    /// Called when the panel itself handles Esc (only while it is key).
    var onCancel: (() -> Void)? { get set }
    /// The user dragged the panel: its new frame and that screen's visible frame.
    var onUserMoved: ((CGRect, CGRect) -> Void)? { get set }
    func fittingSize(for view: AnyView) -> CGSize
    /// `makeKey` is used only when the global Esc key is unavailable.
    func present(_ view: AnyView, frame: CGRect, makeKey: Bool)
    func dismiss()
}

@MainActor
protocol PopupPresenting: AnyObject {
    /// Called when the user dismisses the popup (Esc or ×), not on `close()`.
    var onDismiss: (() -> Void)? { get set }
    var onAction: ((PopupContent.Action) -> Void)? { get set }
    var isVisible: Bool { get }
    func show(_ content: PopupContent, at anchor: SelectionAnchor)
    func close()
}

/// Floating popup (PLAN F03). Shown without activating this app, so the
/// source app keeps focus and its selection. Esc is a hot key registered only
/// while the popup is visible; Close and Esc are the only dismissals (PLAN
/// lists no click-outside dismissal).
final class TranslationPanelController: PopupPresenting {
    private let window: any PopupWindowing
    private let escape: any HotKeyRegistering
    private let copyToPasteboard: (String) -> Void
    private let logger = Logger(subsystem: "local.chienhuynh.LocalTranslator", category: "popup")

    var onDismiss: (() -> Void)?
    var onAction: ((PopupContent.Action) -> Void)?
    private(set) var isVisible = false
    private(set) var frame: CGRect?
    private(set) var escapeRegistered = false
    /// Distinguishes presentations so per-popup view state (e.g. “Copied”) resets.
    private var generation = 0
    private var content: PopupContent?
    /// Where the user dropped the popup; kept for this anchor (streaming,
    /// Retry, ⇄) until it closes or another selection is shown.
    private var moved: (anchor: SelectionAnchor, topLeft: CGPoint, visibleFrame: CGRect)?
    private var anchor: SelectionAnchor?

    /// Everything except the body text that decides the popup size. Streaming
    /// renders at the size limit reuse the last measurement instead of laying
    /// out the whole view again every 40 ms.
    private struct SizingKey: Equatable {
        let width: CGFloat
        let bodyHeight: CGFloat
        let title: String
        let phase: PopupContent.Phase
        let hasBody: Bool
        let message: String?
        let action: PopupContent.Action?
        let alternateDirection: TranslationDirection?
        let offersRetranslate: Bool
        let anchor: SelectionAnchor
    }
    private var lastSizing: (key: SizingKey, bodyHeight: CGFloat, size: CGSize)?
    /// Number of full layout measurements (tests).
    private(set) var measureCount = 0

    init(
        window: any PopupWindowing,
        escape: any HotKeyRegistering,
        copyToPasteboard: @escaping (String) -> Void
    ) {
        self.window = window
        self.escape = escape
        self.copyToPasteboard = copyToPasteboard
        window.onCancel = { [weak self] in self?.dismissByUser() }
        window.onUserMoved = { [weak self] frame, visibleFrame in
            guard let self, isVisible, let anchor else { return }
            moved = (anchor, CGPoint(x: frame.minX, y: frame.maxY), visibleFrame)
        }
    }

    /// Shows or replaces the popup at `anchor`.
    func show(_ content: PopupContent, at anchor: SelectionAnchor) {
        if !isVisible { registerEscape() }
        generation += 1
        self.content = content
        if let moved, moved.anchor != anchor { self.moved = nil }
        self.anchor = anchor

        let maxSize = PopupPositioner.maxSize(in: moved?.visibleFrame ?? anchor.visibleFrame)
        let layout = PopupMetrics.layout(for: content.body, maxSize: maxSize)
        let key = SizingKey(
            width: layout.width, bodyHeight: layout.bodyHeight, title: content.title, phase: content.phase,
            hasBody: !content.body.isEmpty, message: content.message, action: content.action,
            alternateDirection: content.alternateDirection, offersRetranslate: content.offersRetranslate, anchor: anchor
        )
        let view: AnyView
        let size: CGSize
        if let lastSizing, lastSizing.key == key {
            view = makeView(content, width: layout.width, bodyHeight: lastSizing.bodyHeight)
            size = lastSizing.size
        } else {
            var bodyHeight = layout.bodyHeight
            var measuredView = makeView(content, width: layout.width, bodyHeight: bodyHeight)
            var measured = window.fittingSize(for: measuredView)
            measureCount += 1
            if measured.height > maxSize.height {
                bodyHeight = max(PopupMetrics.minBodyHeight, bodyHeight - (measured.height - maxSize.height))
                measuredView = makeView(content, width: layout.width, bodyHeight: bodyHeight)
                measured = window.fittingSize(for: measuredView)
                measureCount += 1
            }
            lastSizing = (key, bodyHeight, measured)
            view = measuredView
            size = measured
        }
        let frame = moved.map { PopupPositioner.frame(for: size, keepingTopLeft: $0.topLeft, in: $0.visibleFrame) }
            ?? PopupPositioner.frame(for: size, anchor: anchor)
        window.present(view, frame: frame, makeKey: !escapeRegistered)
        self.frame = frame
        isVisible = true
    }

    func close() {
        guard isVisible else { return }
        if escapeRegistered { escape.unregister() }
        escapeRegistered = false
        window.dismiss()
        isVisible = false
        frame = nil
        content = nil
        lastSizing = nil
        moved = nil
        anchor = nil
    }

    /// Esc or ×: close and tell the owner so it can cancel its work.
    func dismissByUser() {
        guard isVisible else { return }
        close()
        onDismiss?()
    }

    /// Copy is user-initiated only (the button) and only for finished output.
    func copyContent() {
        guard let content, content.canCopy else { return }
        copyToPasteboard(content.body)
    }

    private func registerEscape() {
        do {
            try escape.register(.escape) { [weak self] phase in
                if phase == .pressed { self?.dismissByUser() }
            }
            escapeRegistered = true
        } catch {
            // Fall back to making the panel key so it receives Esc itself.
            escapeRegistered = false
            logger.notice("Esc hot key unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    private func makeView(_ content: PopupContent, width: CGFloat, bodyHeight: CGFloat) -> AnyView {
        AnyView(
            TranslationPopupView(
                content: content,
                width: width,
                bodyHeight: bodyHeight,
                onCopy: { [weak self] in self?.copyContent() },
                onAction: { [weak self] action in self?.onAction?(action) },
                onClose: { [weak self] in self?.dismissByUser() }
            )
            // A request keeps one identity across streaming renders; otherwise
            // every render rebuilt the ScrollView and jumped back to the top.
            .id(content.session.map(AnyHashable.init) ?? AnyHashable(generation))
        )
    }
}

extension TranslationPanelController {
    static func system() -> TranslationPanelController {
        TranslationPanelController(
            window: PopupPanelWindow(),
            escape: CarbonHotKeyRegistrar(),
            copyToPasteboard: { text in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        )
    }
}

/// Borderless, non-activating floating panel hosting the SwiftUI popup.
final class PopupPanelWindow: PopupWindowing {
    var onCancel: (() -> Void)?
    var onUserMoved: ((CGRect, CGRect) -> Void)?
    /// True while this class moves the panel, so only user drags are reported.
    private var isPlacing = false
    private var moveObserver: NSObjectProtocol?
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private lazy var panel = makePanel()

    func fittingSize(for view: AnyView) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
    }

    func present(_ view: AnyView, frame: CGRect, makeKey: Bool) {
        hostingView.rootView = view
        // Streaming updates usually keep the frame; avoid window work then.
        if panel.frame != frame {
            isPlacing = true
            panel.setFrame(frame, display: true)
            isPlacing = false
            panel.invalidateShadow()
        }
        if makeKey {
            // Keyboard focus only; a non-activating panel does not activate the app.
            if !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func dismiss() {
        panel.orderOut(nil)
        hostingView.rootView = AnyView(EmptyView())
    }

    private func makePanel() -> PopupPanel {
        let panel = PopupPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        // Appear on the current Space, including over full-screen apps.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.onCancel = { [weak self] in self?.onCancel?() }
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPlacing, self.panel.isVisible else { return }
                let visible = self.panel.screen?.visibleFrame ?? self.panel.frame
                self.onUserMoved?(self.panel.frame, visible)
            }
        }
        return panel
    }
}

final class PopupPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc while the panel is key.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
