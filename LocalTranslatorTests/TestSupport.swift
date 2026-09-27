@testable import LocalTranslator

/// Mirrors the real API: a prompt returns the current trust immediately;
/// a grant only happens later, when the user toggles System Settings.
final class FakeTrust: AccessibilityTrustChecking {
    var trusted: Bool
    private(set) var promptCount = 0
    private(set) var checkCount = 0

    init(trusted: Bool) { self.trusted = trusted }

    func isTrusted(prompt: Bool) -> Bool {
        checkCount += 1
        if prompt { promptCount += 1 }
        return trusted
    }
}

final class FakeSettingsOpener: SystemSettingsOpening {
    private(set) var openCount = 0
    func openAccessibilityPrivacy() { openCount += 1 }
}

extension AccessibilityPermissionService {
    static func fake(trusted: Bool = false) -> AccessibilityPermissionService {
        AccessibilityPermissionService(trust: FakeTrust(trusted: trusted), settings: FakeSettingsOpener())
    }
}
