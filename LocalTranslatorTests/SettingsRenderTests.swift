import AppKit
import SwiftUI
import Testing
@testable import Undertone

/// Renders the Settings window to PNG for visual review (L08 UI pass). Runs
/// only with TEST_RUNNER_LT_RENDER_DIR=<dir>.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LT_RENDER_DIR"] != nil))
struct SettingsRenderTests {
    private func coordinator(ready: Bool) async -> AppCoordinator {
        let transport: MockTransport = ready ? .ollama(models: ["translategemma:12b", "gemma3:12b"]) : .refusing()
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: transport)
        await readiness.refresh()
        let app = AppCoordinator(
            readiness: readiness,
            permission: .fake(trusted: ready),
            shortcut: .fake(),
            flow: .fake(),
            selectionTrigger: .fake(),
            launchAtLogin: LaunchAtLoginService(item: FakeLoginItem()),
            live: .fake()
        )
        app.permission.refresh()
        app.shortcut.start()
        return app
    }

    @Test func renderSettings() async throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LT_RENDER_DIR"]!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for ready in [false, true] {
            let app = await coordinator(ready: ready)
            for scheme in [ColorScheme.light, .dark] {
                let host = NSHostingView(rootView: ContentView(coordinator: app).environment(\.colorScheme, scheme))
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                try png.write(to: dir.appendingPathComponent("settings-\(ready ? "ready" : "notready")-\(scheme == .dark ? "dark" : "light").png"))
            }
            app.shutdown()
        }
    }
}
