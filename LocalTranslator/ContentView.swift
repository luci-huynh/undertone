import SwiftUI

/// Settings shell. Model and runtime controls belong to later steps.
struct ContentView: View {
    let coordinator: AppCoordinator

    var body: some View {
        Form {
            Section("Local Translator") {
                LabeledContent("Ollama", value: coordinator.runtimeStatus)
                LabeledContent("Model", value: "Chưa chọn")
            }
            AccessibilityPermissionSection(permission: coordinator.permission)
            Section {
                Text("Dịch văn bản chưa sẵn sàng. Phím tắt ⌥T sẽ được bật khi thiết lập hoàn tất.")
                    .foregroundStyle(.secondary)
                Text("Nội dung dịch sẽ được xử lý trên máy qua Ollama.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
        .onAppear {
            coordinator.permission.refresh()
            NSApp.activate()
        }
        // Reopening an existing Settings window, or returning from System Settings,
        // does not re-run onAppear; the window becoming key does.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            coordinator.permission.refresh()
        }
    }
}

private struct AccessibilityPermissionSection: View {
    let permission: AccessibilityPermissionService

    private static let hint = "Mở System Settings › Privacy & Security › Accessibility (macOS mới: Device Control and Data Access), bật LocalTranslator rồi quay lại đây."
    private static let afterRequestHint = "Nếu đã từ chối hoặc không thấy hộp thoại, bật LocalTranslator trực tiếp trong System Settings › Privacy & Security › Accessibility (macOS mới: Device Control and Data Access)."
    private static let staleGrantHint = "Nếu công tắc LocalTranslator đã bật mà vẫn báo chưa cấp quyền (thường gặp sau khi build lại app), xóa LocalTranslator khỏi danh sách bằng nút − rồi thêm lại, hoặc tắt rồi bật lại công tắc."

    var body: some View {
        Section("Accessibility") {
            LabeledContent("Trạng thái", value: permission.state.label)
            if permission.state == .notGranted {
                Text("Local Translator needs Accessibility permission to read selected text.")
                Text(permission.hasRequestedThisLaunch ? Self.afterRequestHint : Self.hint)
                    .foregroundStyle(.secondary)
                Text(Self.staleGrantHint)
                    .foregroundStyle(.secondary)
                HStack {
                    if permission.canRequestAccess {
                        Button("Request Access…") { permission.requestAccess() }
                    }
                    Button("Open System Settings") { permission.openSystemSettings() }
                    Spacer()
                    Button("Refresh") { permission.refresh() }
                }
            }
        }
    }
}
