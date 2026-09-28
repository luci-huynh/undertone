import Testing
@testable import Undertone

@MainActor
struct AccessibilityPermissionTests {
    @Test func startsUncheckedWithoutQueryingOrPrompting() {
        let trust = FakeTrust(trusted: true)
        let service = AccessibilityPermissionService(trust: trust, settings: FakeSettingsOpener())
        #expect(service.state == .notChecked)
        #expect(service.state.label == "Chưa kiểm tra")
        #expect(trust.checkCount == 0)
        #expect(!service.canRequestAccess)
    }

    @Test func refreshMapsTrustWithoutPrompting() {
        let trust = FakeTrust(trusted: false)
        let service = AccessibilityPermissionService(trust: trust, settings: FakeSettingsOpener())
        service.refresh()
        #expect(service.state == .notGranted)
        #expect(service.state.label == "Chưa cấp quyền")
        trust.trusted = true
        service.refresh()
        #expect(service.state == .granted)
        #expect(service.state.label == "Đã cấp quyền")
        trust.trusted = false
        service.refresh()
        #expect(service.state == .notGranted)
        #expect(trust.promptCount == 0)
    }

    @Test func requestPromptsOnlyOncePerLaunch() {
        let trust = FakeTrust(trusted: false)
        let service = AccessibilityPermissionService(trust: trust, settings: FakeSettingsOpener())
        service.refresh()
        #expect(service.canRequestAccess)
        service.requestAccess()
        service.requestAccess()
        #expect(trust.promptCount == 1)
        #expect(service.state == .notGranted)
        #expect(service.hasRequestedThisLaunch)
        #expect(!service.canRequestAccess)
    }

    @Test func requestDoesNotPromptWhenAlreadyTrusted() {
        let trust = FakeTrust(trusted: true)
        let service = AccessibilityPermissionService(trust: trust, settings: FakeSettingsOpener())
        service.requestAccess()
        #expect(trust.promptCount == 0)
        #expect(service.state == .granted)
        #expect(!service.hasRequestedThisLaunch)
    }

    @Test func grantInSystemSettingsAfterRequestIsPickedUpByRefresh() {
        let trust = FakeTrust(trusted: false)
        let service = AccessibilityPermissionService(trust: trust, settings: FakeSettingsOpener())
        service.requestAccess()
        #expect(trust.promptCount == 1)
        #expect(service.state == .notGranted)
        trust.trusted = true
        service.refresh()
        #expect(service.state == .granted)
        #expect(!service.canRequestAccess)
        #expect(trust.promptCount == 1)
    }

    @Test func openSystemSettingsDelegatesWithoutChangingState() {
        let trust = FakeTrust(trusted: false)
        let opener = FakeSettingsOpener()
        let service = AccessibilityPermissionService(trust: trust, settings: opener)
        service.openSystemSettings()
        #expect(opener.openCount == 1)
        #expect(service.state == .notChecked)
        #expect(trust.checkCount == 0)
    }
}
