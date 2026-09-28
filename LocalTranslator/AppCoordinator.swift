import Foundation
import os

@MainActor
final class AppCoordinator {
    let readiness: OllamaReadinessService
    let permission: AccessibilityPermissionService
    let shortcut: GlobalShortcutService
    let flow: TranslationCoordinator
    let selectionTrigger: SelectionTriggerService
    let launchAtLogin: LaunchAtLoginService
    /// Feature 2 (PLAN §24): separate session; ⌥T and the popup never touch it.
    let live: LiveSession

    init(
        readiness: OllamaReadinessService,
        permission: AccessibilityPermissionService,
        shortcut: GlobalShortcutService,
        flow: TranslationCoordinator,
        selectionTrigger: SelectionTriggerService,
        launchAtLogin: LaunchAtLoginService,
        live: LiveSession
    ) {
        self.readiness = readiness
        self.permission = permission
        self.shortcut = shortcut
        self.flow = flow
        self.selectionTrigger = selectionTrigger
        self.launchAtLogin = launchAtLogin
        self.live = live
        flow.onOpenAccessibilitySettings = { [permission] in permission.openSystemSettings() }
    }

    var translation: TranslationStateMachine { flow.state }

    func start() {
        permission.refresh()
        readiness.start()
        // ⌥T and the selection button start the same flow; either removes the button.
        shortcut.onTrigger = { [weak self] in
            self?.selectionTrigger.hide()
            self?.flow.trigger()
        }
        selectionTrigger.onTrigger = { [weak self] in self?.flow.trigger() }
        shortcut.start()
        selectionTrigger.start()
    }

    func shutdown() {
        live.stop()
        selectionTrigger.stop()
        shortcut.stop()
        readiness.stop()
        flow.shutdown()
    }
}
