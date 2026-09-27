import AppKit
import ApplicationServices
import Observation

/// Reads this process's Accessibility trust. `prompt` asks macOS to show its
/// permission dialog; it must only be true for an explicit user action.
protocol AccessibilityTrustChecking {
    func isTrusted(prompt: Bool) -> Bool
}

protocol SystemSettingsOpening {
    func openAccessibilityPrivacy()
}

struct SystemAccessibilityTrust: AccessibilityTrustChecking {
    func isTrusted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

struct SystemSettingsOpener: SystemSettingsOpening {
    private static let accessibilityPane = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    func openAccessibilityPrivacy() {
        NSWorkspace.shared.open(Self.accessibilityPane)
    }
}

/// macOS does not distinguish "denied" from "never granted"; both are `.notGranted`.
enum AccessibilityPermissionState: Equatable {
    case notChecked
    case granted
    case notGranted

    var label: String {
        switch self {
        case .notChecked: "Chưa kiểm tra"
        case .granted: "Đã cấp quyền"
        case .notGranted: "Chưa cấp quyền"
        }
    }
}

@Observable
final class AccessibilityPermissionService {
    private let trust: any AccessibilityTrustChecking
    private let settings: any SystemSettingsOpening

    private(set) var state: AccessibilityPermissionState = .notChecked
    /// Limits the system prompt to one explicit request per launch.
    private(set) var hasRequestedThisLaunch = false

    init(trust: any AccessibilityTrustChecking, settings: any SystemSettingsOpening) {
        self.trust = trust
        self.settings = settings
    }

    var canRequestAccess: Bool { state == .notGranted && !hasRequestedThisLaunch }

    func refresh() {
        state = trust.isTrusted(prompt: false) ? .granted : .notGranted
    }

    func requestAccess() {
        refresh()
        guard canRequestAccess else { return }
        hasRequestedThisLaunch = true
        state = trust.isTrusted(prompt: true) ? .granted : .notGranted
    }

    func openSystemSettings() {
        settings.openAccessibilityPrivacy()
    }
}
