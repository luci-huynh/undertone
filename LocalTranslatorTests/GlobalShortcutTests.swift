import Testing
@testable import Undertone

@MainActor
struct GlobalShortcutTests {
    @Test func registersOptionTOnStartAndIsIdempotent() {
        let registrar = FakeHotKeyRegistrar()
        let shortcut = GlobalShortcutService(registrar: registrar)
        #expect(shortcut.status == .inactive)
        shortcut.start()
        shortcut.start()
        #expect(shortcut.status == .registered)
        #expect(registrar.registerCount == 1)
        #expect(registrar.registered == .optionT)
        #expect(shortcut.combination.display == "⌥T")
    }

    @Test func onePressIsOneTriggerEvenWhenHeld() {
        let registrar = FakeHotKeyRegistrar()
        let shortcut = GlobalShortcutService(registrar: registrar)
        shortcut.start()
        registrar.send(.pressed)
        registrar.send(.pressed)
        registrar.send(.pressed)
        #expect(shortcut.triggerCount == 1)
        registrar.send(.released)
        registrar.send(.pressed)
        registrar.send(.released)
        #expect(shortcut.triggerCount == 2)
    }

    @Test func conflictIsReportedAndRetryCanRecover() {
        let registrar = FakeHotKeyRegistrar()
        registrar.failure = .conflict
        let shortcut = GlobalShortcutService(registrar: registrar)
        shortcut.start()
        #expect(shortcut.status == .conflict)
        #expect(shortcut.status.label == "Bị trùng với app khác")
        shortcut.handle(.pressed)
        #expect(shortcut.triggerCount == 0)
        registrar.failure = nil
        shortcut.start()
        #expect(shortcut.status == .registered)
        #expect(registrar.registerCount == 2)
    }

    @Test func otherRegistrationFailureKeepsStatusCode() {
        let registrar = FakeHotKeyRegistrar()
        registrar.failure = .failed(-50)
        let shortcut = GlobalShortcutService(registrar: registrar)
        shortcut.start()
        #expect(shortcut.status == .failed(-50))
    }

    @Test func stopUnregistersAndIgnoresLateEvents() {
        let registrar = FakeHotKeyRegistrar()
        let shortcut = GlobalShortcutService(registrar: registrar)
        shortcut.start()
        registrar.send(.pressed)
        shortcut.stop()
        #expect(shortcut.status == .inactive)
        #expect(registrar.unregisterCount == 1)
        #expect(registrar.registered == nil)
        shortcut.handle(.released)
        shortcut.handle(.pressed)
        #expect(shortcut.triggerCount == 1)
        shortcut.start()
        registrar.send(.pressed)
        #expect(shortcut.triggerCount == 2)
    }

    @Test func coordinatorStartsAndShutsDownShortcut() {
        let registrar = FakeHotKeyRegistrar()
        let coordinator = AppCoordinator.fake(shortcut: GlobalShortcutService(registrar: registrar))
        coordinator.start()
        #expect(coordinator.shortcut.status == .registered)
        #expect(coordinator.permission.state == .notGranted)
        coordinator.shutdown()
        #expect(coordinator.shortcut.status == .inactive)
        #expect(registrar.unregisterCount == 1)
    }
}
