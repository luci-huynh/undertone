import SwiftUI

@main
struct UndertoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Undertone", image: "MenuBarIcon") {
            Text("Undertone")
            Text("Ollama: \(delegate.coordinator.readiness.runtime.label)")
            Text("Model: \(delegate.coordinator.readiness.modelLabel)")
            if delegate.coordinator.shortcut.status != .registered {
                Text("Shortcut \(delegate.coordinator.shortcut.combination.display): \(delegate.coordinator.shortcut.status.menuLabel)")
            }
            // A minimized or hidden Live session is not forgotten (L08 review).
            if delegate.coordinator.live.status.isRunning {
                Text("Live: On — \(delegate.coordinator.live.source.title)")
            }
            Divider()
            LiveMenuButton { delegate.liveWindow.show() }
            SettingsMenuButton()
            Button("Open Ollama") { OllamaAppLauncher.open() }
                .disabled(OllamaAppLauncher.appURL == nil)
            Divider()
            Button("Quit Undertone") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        Settings {
            ContentView(coordinator: delegate.coordinator)
        }
    }
}

/// Opens the floating Live window (Feature 2). Live needs macOS 26 (L01).
private struct LiveMenuButton: View {
    let open: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            Button("Live Meeting Translation…", action: open)
        } else {
            Text("Live Meeting Translation needs macOS 26")
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
        let translator = OllamaTranslationService(readiness: readiness)
        let flow = TranslationCoordinator(
            selection: selection,
            // S20: real local translation. Rollback: PlaceholderTranslationService().
            translator: translator,
            popup: TranslationPanelController.system(),
            cursorAnchor: cursorAnchor
        )
        return AppCoordinator(
            readiness: readiness,
            permission: AccessibilityPermissionService(
                trust: SystemAccessibilityTrust(),
                settings: SystemSettingsOpener()
            ),
            shortcut: GlobalShortcutService(registrar: CarbonHotKeyRegistrar()),
            flow: flow,
            // S24. Rollback: turn it off in Settings; ⌥T is unaffected.
            selectionTrigger: SelectionTriggerService(
                selection: selection,
                presenter: SelectionTriggerPanel(),
                events: GlobalMouseEventSource(),
                settings: UserDefaultsSelectionTriggerSettings(),
                cursorAnchor: cursorAnchor
            ),
            launchAtLogin: LaunchAtLoginService(item: MainAppLoginItem()),
            live: LiveSession(
                capture: AppDelegate.liveCapture(),
                transcriber: { AppDelegate.liveTranscriber() },
                // L04: EN → VI only (user decision), same local client as ⌥T;
                // a running ⌥T request goes first.
                translations: LiveTranslationQueue(
                    translate: { translator.translate($0, direction: .englishToVietnamese) },
                    isTextBusy: { [weak flow] in flow.map { $0.state.phase == .loading || $0.state.phase == .streaming } ?? false }
                ),
                processes: CoreAudioProcessList(),
                systemEvents: AppDelegate.liveSystemEvents(),
                settings: UserDefaultsLiveSettings()
            )
        )
    }()

    /// Floating Live panel (L05); created on first use.
    lazy var liveWindow = LiveWindowController(session: coordinator.live)

    private static func liveCapture() -> any LiveAudioCapturing {
        if #available(macOS 26.0, *) { CoreAudioTapCapture() } else { UnsupportedLiveCapture() }
    }

    private static func liveSystemEvents() -> any LiveSystemEventSource {
        if #available(macOS 26.0, *) { CoreAudioSystemEvents() } else { NoLiveSystemEvents() }
    }

    private static func liveTranscriber() -> any LiveTranscribing {
        if #available(macOS 26.0, *) { SpeechAnalyzerTranscriber() } else { UnsupportedLiveTranscriber() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
        #if DEBUG || LIVE_QA_HOOK
        // QA hook (Debug builds, or a local QA build with -D LIVE_QA_HOOK):
        // `-LiveDebugAutoStart chrome` starts Live at launch so capture can be
        // checked with synthetic audio. Shipped builds capture only after Start.
        if let raw = UserDefaults.standard.string(forKey: "LiveDebugAutoStart"), let source = LiveSource(rawValue: raw) {
            coordinator.live.source = source
            coordinator.live.start()
            let seconds = UserDefaults.standard.integer(forKey: "LiveDebugAutoStopAfter")
            if seconds > 0 {
                Task { @MainActor [coordinator] in
                    try? await Task.sleep(for: .seconds(seconds))
                    coordinator.live.stop()
                }
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
    }
}
