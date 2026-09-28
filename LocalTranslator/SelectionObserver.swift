import AppKit
import Observation
import os

/// Input the selection trigger reacts to (S24, user decision A): mouse
/// buttons, drags, scrolling and app switches. Never the keyboard — no key
/// monitor is installed (runbook S24: not a keylogger).
enum SelectionMouseEvent: Equatable {
    case down(CGPoint)
    case dragged(CGPoint)
    case up(clickCount: Int)
    case scroll
    case appSwitched
}

@MainActor
protocol SelectionEventSource: AnyObject {
    func start(_ handler: @escaping (SelectionMouseEvent) -> Void)
    func stop()
}

@MainActor
protocol SelectionTriggerPresenting: AnyObject {
    var onClick: (() -> Void)? { get set }
    var isVisible: Bool { get }
    func show(at anchor: SelectionAnchor)
    func hide()
}

/// Stores the on/off switch only.
protocol SelectionTriggerSettingsStoring: AnyObject {
    var showsSelectionTrigger: Bool { get set }
}

final class UserDefaultsSelectionTriggerSettings: SelectionTriggerSettingsStoring {
    private let defaults: UserDefaults
    private static let key = "ShowSelectionTrigger"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// User decision S24: on by default.
    var showsSelectionTrigger: Bool {
        get { defaults.object(forKey: Self.key) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// Small translate button next to the pointer after a mouse selection (PLAN
/// §1 “small translate trigger”; S24 decisions: mouse-based, on by default,
/// icon). A drag or a double/triple click reads the selection once, through
/// the same capture as ⌥T, after the clicks settle. Nothing is sent until
/// the button is clicked; the text read here is only checked for being
/// non-empty and then dropped. No polling.
@Observable
final class SelectionTriggerService {
    /// Drags shorter than this are clicks (window focus, buttons).
    static let minimumDragDistance: CGFloat = 4

    private(set) var isEnabled: Bool
    /// Clicking the button; wired to the ⌥T flow.
    @ObservationIgnored var onTrigger: (() -> Void)?

    @ObservationIgnored private let selection: any SelectionCapturing
    @ObservationIgnored private let presenter: any SelectionTriggerPresenting
    @ObservationIgnored private let events: any SelectionEventSource
    @ObservationIgnored private let settings: any SelectionTriggerSettingsStoring
    @ObservationIgnored private let cursorAnchor: () -> SelectionAnchor?
    @ObservationIgnored private let settleDelay: Duration
    @ObservationIgnored private let visibleDuration: Duration
    @ObservationIgnored private let logger = Logger(subsystem: "local.chienhuynh.LocalTranslator", category: "trigger")

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var downLocation: CGPoint?
    @ObservationIgnored private var didDrag = false
    /// Exposed so tests can await them.
    @ObservationIgnored private(set) var pendingTask: Task<Void, Never>?
    @ObservationIgnored private(set) var hideTask: Task<Void, Never>?
    /// Selection reads started (tests; also shows reads are one per gesture).
    @ObservationIgnored private(set) var captureCount = 0

    init(
        selection: any SelectionCapturing,
        presenter: any SelectionTriggerPresenting,
        events: any SelectionEventSource,
        settings: any SelectionTriggerSettingsStoring,
        cursorAnchor: @escaping () -> SelectionAnchor?,
        settleDelay: Duration = .milliseconds(200),
        visibleDuration: Duration = .seconds(4)
    ) {
        self.selection = selection
        self.presenter = presenter
        self.events = events
        self.settings = settings
        self.cursorAnchor = cursorAnchor
        self.settleDelay = settleDelay
        self.visibleDuration = visibleDuration
        isEnabled = settings.showsSelectionTrigger
        presenter.onClick = { [weak self] in
            guard let self else { return }
            hide()
            logger.notice("Selection trigger clicked")
            onTrigger?()
        }
    }

    /// Installs the mouse monitor when enabled; off means no monitor at all.
    func start() {
        guard isEnabled, !isRunning else { return }
        isRunning = true
        events.start { [weak self] event in self?.handle(event) }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        events.stop()
        hide()
    }

    func setEnabled(_ enabled: Bool) {
        settings.showsSelectionTrigger = enabled
        isEnabled = enabled
        enabled ? start() : stop()
    }

    /// Cancels a pending read and removes the button (also when ⌥T opens the popup).
    func hide() {
        sequence += 1
        pendingTask?.cancel()
        hideTask?.cancel()
        pendingTask = nil
        hideTask = nil
        if presenter.isVisible { presenter.hide() }
    }

    func handle(_ event: SelectionMouseEvent) {
        guard isRunning else { return }
        switch event {
        case .down(let location):
            hide()
            downLocation = location
            didDrag = false
        case .dragged(let location):
            if let start = downLocation, hypot(location.x - start.x, location.y - start.y) >= Self.minimumDragDistance {
                didDrag = true
            }
        case .up(let clickCount):
            let selecting = didDrag || clickCount >= 2
            downLocation = nil
            didDrag = false
            guard selecting else { return }
            scheduleRead(anchor: cursorAnchor())
        case .scroll, .appSwitched:
            hide()
        }
    }

    /// Waits for a possible further click (double → triple), then reads once.
    private func scheduleRead(anchor: SelectionAnchor?) {
        guard let anchor else { return }
        let current = sequence
        pendingTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: settleDelay)
            guard current == sequence, !Task.isCancelled else { return }
            captureCount += 1
            let result = await selection.capture()
            guard current == sequence, !Task.isCancelled, isRunning else { return }
            // Any failure (secure field, unsupported app, no selection) shows nothing.
            guard case .success(let snapshot) = result,
                  !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            presenter.show(at: anchor)
            scheduleAutoHide(for: current)
        }
    }

    private func scheduleAutoHide(for current: Int) {
        let duration = visibleDuration
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled, current == sequence else { return }
            hide()
        }
    }
}

/// Where the button goes: below-right of the pointer, flipped to stay on
/// the pointer's screen.
nonisolated enum SelectionTriggerPlacement {
    static let size = CGSize(width: 30, height: 30)
    static let offset: CGFloat = 10

    static func frame(near anchor: SelectionAnchor, size: CGSize = size) -> CGRect {
        let point = anchor.rect.origin
        let visible = anchor.visibleFrame
        var x = point.x + offset
        if x + size.width > visible.maxX { x = point.x - offset - size.width }
        var y = point.y - offset - size.height
        if y < visible.minY { y = point.y + offset }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        y = min(max(y, visible.minY), visible.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

/// Global mouse monitor (events of other apps only; our own panels'
/// clicks never arrive here) plus app-activation notifications.
final class GlobalMouseEventSource: SelectionEventSource {
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?

    func start(_ handler: @escaping (SelectionMouseEvent) -> Void) {
        guard monitors.isEmpty else { return }
        let add: (NSEvent.EventTypeMask, @escaping (NSEvent) -> SelectionMouseEvent) -> Void = { [weak self] mask, map in
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
                let mapped = map(event)
                MainActor.assumeIsolated { handler(mapped) }
            }
            if let monitor { self?.monitors.append(monitor) }
        }
        add([.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in .down(NSEvent.mouseLocation) }
        add(.leftMouseDragged) { _ in .dragged(NSEvent.mouseLocation) }
        add(.leftMouseUp) { event in .up(clickCount: event.clickCount) }
        add(.scrollWheel) { _ in .scroll }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler(.appSwitched) }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }
}

/// The button: a tiny non-activating panel, so the source app keeps focus
/// and its selection when it is clicked.
final class SelectionTriggerPanel: SelectionTriggerPresenting {
    var onClick: (() -> Void)?
    private lazy var panel = makePanel()

    var isVisible: Bool { panel.isVisible }

    func show(at anchor: SelectionAnchor) {
        panel.setFrame(SelectionTriggerPlacement.frame(near: anchor), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let size = SelectionTriggerPlacement.size
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]

        let button = FirstClickButton(frame: background.bounds)
        button.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Translate")
            ?? NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Translate")
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .controlAccentColor
        button.toolTip = "Translate selection (⌥T)"
        button.autoresizingMask = [.width, .height]
        button.target = self
        button.action = #selector(clicked)
        background.addSubview(button)
        panel.contentView = background
        return panel
    }

    @objc private func clicked() {
        onClick?()
    }
}

/// Acts on the first click even though its window is never key.
private final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
