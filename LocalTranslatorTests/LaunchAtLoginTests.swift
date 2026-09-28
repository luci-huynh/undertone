import ServiceManagement
import Testing
@testable import LocalTranslator

/// PLAN F07 Launch at Login: off by default, macOS keeps the state.
@MainActor
struct LaunchAtLoginTests {
    @Test func offUntilTheUserTurnsItOn() {
        let service = LaunchAtLoginService(item: FakeLoginItem())
        #expect(!service.isOn)
        #expect(!service.needsApproval)
    }

    @Test func turningOnAndOff() {
        let item = FakeLoginItem()
        let service = LaunchAtLoginService(item: item)
        service.setOn(true)
        #expect(service.isOn && item.status == .enabled)
        service.setOn(false)
        #expect(!service.isOn && item.status == .notRegistered)
        #expect(service.lastError == nil)
    }

    @Test func approvalPendingCountsAsOnAndOffersSystemSettings() {
        let item = FakeLoginItem()
        item.registerResult = .requiresApproval
        let service = LaunchAtLoginService(item: item)
        service.setOn(true)
        #expect(service.isOn && service.needsApproval)
        service.openSystemSettings()
        #expect(item.openedSettings == 1)
    }

    @Test func failureIsShownAndStateReread() {
        let item = FakeLoginItem()
        item.failure = NSError(domain: "SMAppServiceErrorDomain", code: 1)
        let service = LaunchAtLoginService(item: item)
        service.setOn(true)
        #expect(!service.isOn)
        #expect(service.lastError == "Không bật được mở cùng macOS.")
    }

    @Test func refreshPicksUpChangesMadeInSystemSettings() {
        let item = FakeLoginItem()
        let service = LaunchAtLoginService(item: item)
        item.status = .enabled
        service.refresh()
        #expect(service.isOn)
    }
}
