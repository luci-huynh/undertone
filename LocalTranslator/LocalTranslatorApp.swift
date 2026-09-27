import SwiftUI

@main
struct LocalTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Local Translator", systemImage: "character.bubble") {
            Text("Local Translator")
            Text("Ollama: \(delegate.coordinator.runtimeStatus)")
            Text("Model: Chưa chọn")
            Divider()
            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",")
            Button("Open Ollama") {}
                .disabled(true)
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator(
        readiness: UnconfiguredReadinessService(),
        permission: AccessibilityPermissionService(
            trust: SystemAccessibilityTrust(),
            settings: SystemSettingsOpener()
        )
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.permission.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
    }
}
