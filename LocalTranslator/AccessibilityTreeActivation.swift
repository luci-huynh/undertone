import ApplicationServices
import Foundation
import os

/// Result of asking an app for its focused element.
nonisolated enum FocusedLookup<Element> {
    case found(Element)
    case missing(AXError)
}

/// Chromium browsers and Electron apps build their native accessibility tree
/// only for assistive clients; until then the app reports no focused element.
/// Setting `AXManualAccessibility` on the app asks it to build the tree. It is
/// tried only after a "no focused element" answer, so apps that already
/// expose their tree are never touched. The app keeps the tree until it quits.
nonisolated enum AccessibilityTreeActivation {
    static let attribute = "AXManualAccessibility"
    /// Tree building is asynchronous; poll briefly after activation.
    static let retries = 4
    static let retryDelay: TimeInterval = 0.05

    private static let logger = Logger(subsystem: "local.chienhuynh.Undertone", category: "selection")
    private static let attempted = OSAllocatedUnfairLock(initialState: Set<pid_t>())

    /// Only "nothing there" answers; a timeout or disabled API is a different problem.
    static func mayNeedActivation(_ error: AXError) -> Bool {
        error == .noValue || error == .attributeUnsupported
    }

    static func lookUp<Element>(
        read: () throws -> FocusedLookup<Element>,
        activate: () -> Bool,
        pause: () throws -> Void,
        retries: Int = retries
    ) throws -> FocusedLookup<Element> {
        let first = try read()
        guard case .missing(let error) = first, mayNeedActivation(error), activate() else { return first }
        var last = first
        for _ in 0..<retries {
            try pause()
            last = try read()
            if case .found = last { return last }
        }
        return last
    }

    /// Chromium browsers ignore `AXManualAccessibility` (Chrome 153 answers
    /// attributeUnsupported) but build their tree for `AXEnhancedUserInterface`,
    /// the flag VoiceOver sets. That flag can make an app animate window moves,
    /// so it is limited to these browsers and never sent to other apps.
    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "company.thebrowser.Browser",
    ]

    /// Attributes to try, in order, until one is accepted.
    static func attributes(forBundleID bundleID: String?) -> [String] {
        guard let bundleID, chromiumBrowsers.contains(bundleID) else { return [attribute] }
        return [attribute, enhancedUserInterfaceAttribute]
    }

    static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

    /// True when the app accepted one of the attributes (Electron apps accept
    /// `AXManualAccessibility`; other apps answer attributeUnsupported and are
    /// left unchanged). Tried once per process per launch: afterwards an
    /// activated app's tree exists, so a missing focused element is real and
    /// waiting would only add latency.
    static func activate(app: AXUIElement, pid: pid_t, bundleID: String?) -> Bool {
        guard attempted.withLock({ $0.insert(pid).inserted }) else { return false }
        for name in attributes(forBundleID: bundleID) {
            let error = AXUIElementSetAttributeValue(app, name as CFString, kCFBooleanTrue)
            logger.notice("\(name, privacy: .public) for pid \(pid, privacy: .public): AXError \(error.rawValue, privacy: .public)")
            if error == .success { return true }
        }
        return false
    }
}
