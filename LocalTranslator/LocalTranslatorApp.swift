import SwiftUI

@main
struct LocalTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Local Translator", image: "MenuBarIcon") {
            Text("Local Translator")
            Text("Ollama: \(delegate.coordinator.readiness.runtime.label)")
            Text("Model: \(delegate.coordinator.readiness.modelLabel)")
            if delegate.coordinator.shortcut.status != .registered {
                Text("Phím tắt \(delegate.coordinator.shortcut.combination.display): \(delegate.coordinator.shortcut.status.label)")
            }
            Divider()
            SettingsMenuButton()
            Button("Open Ollama") { OllamaAppLauncher.open() }
                .disabled(OllamaAppLauncher.appURL == nil)
            Divider()
            Button("Quit Local Translator") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        Settings {
            ContentView(coordinator: delegate.coordinator)
        }
    }
}

/// A menu-bar (LSUIElement) app is not frontmost, so SettingsLink can open the
/// window behind other apps. Activate and bring the window forward explicitly.
private struct SettingsMenuButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate()
            openSettings()
            // Next main-actor turn, after SwiftUI has created or shown the window.
            Task { @MainActor in Self.bringSettingsWindowToFront() }
        }
        .keyboardShortcut(",")
    }

    private static func bringSettingsWindowToFront() {
        let window = NSApp.windows.first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
            ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: AppCoordinator = {
        let environment = SystemSelectionEnvironment()
        let readiness = OllamaReadinessService(settings: UserDefaultsModelSettings(), transport: URLSessionTransport())
        let selection = SelectedTextService(
            trust: SystemAccessibilityTrust(),
            environment: environment,
            query: AXFocusedElementQuery()
        )
        let cursorAnchor = {
            SelectionAnchorResolver.resolve(
                axBounds: nil,
                mouseLocation: environment.mouseLocation(),
                layout: environment.screenLayout()
            )
        }
        return AppCoordinator(
            readiness: readiness,
            permission: AccessibilityPermissionService(
                trust: SystemAccessibilityTrust(),
                settings: SystemSettingsOpener()
            ),
            shortcut: GlobalShortcutService(registrar: CarbonHotKeyRegistrar()),
            flow: TranslationCoordinator(
                selection: selection,
                // S20: real local translation. Rollback: PlaceholderTranslationService().
                translator: OllamaTranslationService(readiness: readiness),
                popup: TranslationPanelController.system(),
                cursorAnchor: cursorAnchor
            ),
            // S24. Rollback: turn it off in Settings; ⌥T is unaffected.
            selectionTrigger: SelectionTriggerService(
                selection: selection,
                presenter: SelectionTriggerPanel(),
                events: GlobalMouseEventSource(),
                settings: UserDefaultsSelectionTriggerSettings(),
                cursorAnchor: cursorAnchor
            ),
            launchAtLogin: LaunchAtLoginService(item: MainAppLoginItem())
        )
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
    }
}
