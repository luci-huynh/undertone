import Observation
import os
import ServiceManagement

/// PLAN F07 “Launch at Login”. macOS keeps the state (System Settings →
/// General → Login Items); the app stores nothing. Off unless the user turns
/// it on.
@MainActor
protocol LoginItemControlling {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

struct MainAppLoginItem: LoginItemControlling {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@Observable
final class LaunchAtLoginService {
    private(set) var status: SMAppService.Status
    /// Last register/unregister error, short, for Settings.
    private(set) var lastError: String?

    @ObservationIgnored private let item: any LoginItemControlling
    @ObservationIgnored private let logger = Logger(subsystem: "local.chienhuynh.LocalTranslator", category: "login")

    init(item: any LoginItemControlling) {
        self.item = item
        status = item.status
    }

    /// On, or waiting for the user's approval in System Settings.
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = item.status
    }

    func setOn(_ on: Bool) {
        do {
            if on { try item.register() } else { try item.unregister() }
            lastError = nil
        } catch {
            lastError = on ? "Không bật được mở cùng macOS." : "Không tắt được mở cùng macOS."
            logger.notice("Login item \(on ? "register" : "unregister", privacy: .public) failed: \((error as NSError).code, privacy: .public)")
        }
        refresh()
    }

    func openSystemSettings() {
        item.openSystemSettings()
    }
}
