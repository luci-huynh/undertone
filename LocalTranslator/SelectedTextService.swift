import AppKit
import ApplicationServices
import Carbon.HIToolbox

protocol SelectionEnvironment {
    func frontmostApplication() -> SourceApp?
    var currentPID: pid_t { get }
    /// True while any app has secure keyboard entry on (e.g. a password field).
    func isSecureInputEnabled() -> Bool
    /// Cursor position in AppKit global coordinates.
    func mouseLocation() -> CGPoint
    func screenLayout() -> ScreenLayout
}

protocol FocusedElementQuerying: Sendable {
    func read(pid: pid_t) async -> FocusedElementReading
}

protocol SelectionCapturing {
    func capture() async -> Result<SelectionSnapshot, SelectionFailure>
}

struct SystemSelectionEnvironment: SelectionEnvironment {
    func frontmostApplication() -> SourceApp? {
        NSWorkspace.shared.frontmostApplication.map { SourceApp(pid: $0.processIdentifier, name: $0.localizedName) }
    }

    var currentPID: pid_t { ProcessInfo.processInfo.processIdentifier }

    func isSecureInputEnabled() -> Bool { IsSecureEventInputEnabled() }

    func mouseLocation() -> CGPoint { NSEvent.mouseLocation }

    /// `NSScreen.screens` lists the primary (menu bar) screen first.
    func screenLayout() -> ScreenLayout {
        ScreenLayout(screens: NSScreen.screens.map { .init(frame: $0.frame, visibleFrame: $0.visibleFrame) })
    }
}

/// Reads the focused element of one app off the main thread. Every AX call is
/// bounded by `timeout` so an unresponsive app cannot stall the UI.
nonisolated struct AXFocusedElementQuery: FocusedElementQuerying {
    private static let executor = AXReadExecutor()
    let timeout: Float

    init(timeout: Float = 0.25) {
        self.timeout = timeout
    }

    func read(pid: pid_t) async -> FocusedElementReading {
        let timeout = timeout
        return await Self.executor.read { cancellation in
            try Self.readFocusedElement(pid: pid, timeout: timeout, cancellation: cancellation)
        }
    }

    private static func readFocusedElement(
        pid: pid_t, timeout: Float, cancellation: AXReadCancellation
    ) throws -> FocusedElementReading {
        try cancellation.check()
        var reading = FocusedElementReading()
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)

        let lookup = try AccessibilityTreeActivation.lookUp(
            read: {
                try cancellation.check()
                return focusedElement(of: app)
            },
            activate: {
                AccessibilityTreeActivation.activate(
                    app: app,
                    pid: pid,
                    bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                )
            },
            pause: {
                try cancellation.check()
                Thread.sleep(forTimeInterval: AccessibilityTreeActivation.retryDelay)
            }
        )
        let element: AXUIElement
        switch lookup {
        case .found(let found):
            element = found
        case .missing(let error):
            reading.focusedElementError = error
            return reading
        }
        AXUIElementSetMessagingTimeout(element, timeout)

        var elementPID: pid_t = 0
        try cancellation.check()
        if AXUIElementGetPid(element, &elementPID) == .success {
            reading.elementPID = elementPID
        }

        // Check before touching any text so secure fields are never read.
        try cancellation.check()
        let subrole = stringAttribute(kAXSubroleAttribute, of: element)
        try cancellation.check()
        let role = stringAttribute(kAXRoleAttribute, of: element)
        if subrole == kAXSecureTextFieldSubrole || role == "AXSecureTextField" {
            reading.isSecureTextField = true
            return reading
        }

        return try ConsistentSelectionReader.read(
            initial: reading,
            text: {
                try cancellation.check()
                var value: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
                if error == .success, let text = value as? String { return .value(text) }
                return .failed(error == .success ? .noValue : error)
            },
            range: {
                try cancellation.check()
                var value: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
                guard error == .success else { return .failed(error) }
                guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return .failed(.noValue) }
                var range = CFRange()
                guard AXValueGetValue(value as! AXValue, .cfRange, &range),
                      range.location >= 0, range.length >= 0 else { return .failed(.noValue) }
                return .value(NSRange(location: range.location, length: range.length))
            },
            bounds: { range in
                try cancellation.check()
                return AXSelectionBounds.read(element: element, range: range)
            },
            stillFocused: {
                try cancellation.check()
                var value: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
                guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
                return CFEqual(element, value)
            }
        )
    }

    private static func focusedElement(of app: AXUIElement) -> FocusedLookup<AXUIElement> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
        guard error == .success else { return .missing(error) }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return .missing(.noValue) }
        return .found(value as! AXUIElement)
    }

    private static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

/// Captures the frontmost app's selection without activating this app.
/// No clipboard use; secure input is never read.
final class SelectedTextService: SelectionCapturing {
    private let trust: any AccessibilityTrustChecking
    private let environment: any SelectionEnvironment
    private let query: any FocusedElementQuerying

    init(
        trust: any AccessibilityTrustChecking,
        environment: any SelectionEnvironment,
        query: any FocusedElementQuerying
    ) {
        self.trust = trust
        self.environment = environment
        self.query = query
    }

    func capture() async -> Result<SelectionSnapshot, SelectionFailure> {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        let capturedAt = Date()
        // Taken at trigger, before the async read, so a moving cursor or a
        // display change during the read does not shift the fallback anchor.
        let mouseLocation = environment.mouseLocation()
        let layout = environment.screenLayout()
        guard trust.isTrusted(prompt: false) else { return .failure(.permissionMissing) }
        guard let source = environment.frontmostApplication() else { return .failure(.noFrontmostApp) }
        guard source.pid != environment.currentPID else { return .failure(.sourceIsSelf) }
        guard !environment.isSecureInputEnabled() else { return .failure(.secureInput) }

        let reading = await query.read(pid: source.pid)
        guard !Task.isCancelled else { return .failure(.cancelled) }
        return SelectionClassifier.classify(
            source: source,
            reading: reading,
            frontmostAfterRead: environment.frontmostApplication()?.pid,
            anchor: SelectionAnchorResolver.resolve(
                axBounds: reading.selectionBounds,
                mouseLocation: mouseLocation,
                layout: layout
            ),
            capturedAt: capturedAt
        )
    }
}
