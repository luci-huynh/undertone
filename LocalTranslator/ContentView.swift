import SwiftUI

/// Settings: runtime/model status and selection, permission, shortcut.
struct ContentView: View {
    let coordinator: AppCoordinator

    var body: some View {
        Form {
            OllamaSection(readiness: coordinator.readiness)
            AccessibilityPermissionSection(permission: coordinator.permission)
            ShortcutSection(shortcut: coordinator.shortcut)
            SelectionTriggerSection(trigger: coordinator.selectionTrigger)
            LaunchAtLoginSection(launchAtLogin: coordinator.launchAtLogin)
            Section {
                Text("⌥T dịch văn bản đã chọn qua Ollama trên máy. Tự nhận diện: English → Vietnamese, Vietnamese → English, ngôn ngữ khác → Vietnamese; nút ⇄ trong popup đổi chiều cho lần dịch đó.")
                    .foregroundStyle(.secondary)
                Text("Nội dung dịch sẽ được xử lý trên máy qua Ollama.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 720)
        .onAppear {
            coordinator.permission.refresh()
            Task { await coordinator.readiness.refresh() }
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

private struct ShortcutSection: View {
    let shortcut: GlobalShortcutService

    var body: some View {
        Section("Phím tắt") {
            LabeledContent(shortcut.combination.display, value: shortcut.status.label)
            switch shortcut.status {
            case .registered:
                LabeledContent("Đã nhận trong phiên này", value: "\(shortcut.triggerCount) lần")
            case .conflict, .failed:
                Text("\(shortcut.combination.display) đang được app khác dùng hoặc không đăng ký được. Hãy đóng app đang dùng phím tắt này rồi thử lại.")
                    .foregroundStyle(.secondary)
                Button("Thử lại") { shortcut.start() }
            case .inactive:
                EmptyView()
            }
        }
    }
}

private struct SelectionTriggerSection: View {
    let trigger: SelectionTriggerService

    var body: some View {
        Section("Nút dịch khi bôi đen") {
            Toggle("Hiện nút dịch cạnh con trỏ", isOn: Binding(get: { trigger.isEnabled }, set: { trigger.setEnabled($0) }))
            Text("Kéo chuột hoặc nhấp đúp để bôi đen → bấm biểu tượng dịch. Chỉ theo dõi chuột, không theo dõi bàn phím; ⌥T luôn dùng được.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct LaunchAtLoginSection: View {
    let launchAtLogin: LaunchAtLoginService

    var body: some View {
        Section("Khởi động") {
            Toggle("Mở cùng macOS (Launch at Login)", isOn: Binding(get: { launchAtLogin.isOn }, set: { launchAtLogin.setOn($0) }))
            if launchAtLogin.needsApproval {
                Text("macOS cần bạn cho phép trong Login Items.")
                    .foregroundStyle(.secondary)
                Button("Mở Login Items") { launchAtLogin.openSystemSettings() }
            }
            if let error = launchAtLogin.lastError {
                Text(error).foregroundStyle(.red)
            }
        }
        // The user may change it in System Settings while this window is open.
        .onAppear { launchAtLogin.refresh() }
    }
}

private struct OllamaSection: View {
    let readiness: OllamaReadinessService
    #if DEBUG
    @State private var sampleResult: String?
    @State private var isTranslatingSample = false
    #endif

    var body: some View {
        Section("Ollama") {
            LabeledContent("Ollama", value: runtimeText)
            switch readiness.runtime {
            case .notRunning:
                Text("Ollama is not running.")
                HStack {
                    Button("Retry") { Task { await readiness.refresh() } }
                    if OllamaAppLauncher.appURL != nil {
                        Button("Open Ollama") { OllamaAppLauncher.open() }
                    }
                }
            case .endpointRejected:
                Text("Địa chỉ Ollama đã cấu hình không phải localhost nên bị chặn; không gửi gì ra ngoài máy.")
                    .foregroundStyle(.secondary)
            case .invalidResponse:
                Text("Cổng 11434 trả lời nhưng không phải Ollama API.")
                    .foregroundStyle(.secondary)
            case .notChecked, .connected:
                EmptyView()
            }
            modelRow
            switch readiness.model {
            case .missing:
                Text("Translation model is not installed.")
                Text("Tải thủ công trong Terminal: ollama pull \(readiness.configuration.tag)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            case .cloudRejected:
                Text("Model cloud chạy trên server của Ollama nên bị từ chối; chọn model local.")
                    .foregroundStyle(.secondary)
            case .unknown, .installed:
                EmptyView()
            }
            Button("Kiểm tra lại") { Task { await readiness.refresh() } }
            #if DEBUG
            HStack {
                Button("Dịch thử câu mẫu (Debug)") { translateSample() }
                    .disabled(!readiness.isReady || isTranslatingSample)
                if isTranslatingSample { ProgressView().controlSize(.small) }
            }
            if let sampleResult {
                Text(sampleResult)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            #endif
        }
    }

    private var runtimeText: String {
        if case .connected(let version) = readiness.runtime { return "Connected (\(version))" }
        return readiness.runtime.label
    }

    @ViewBuilder
    private var modelRow: some View {
        let options = Array(Set(readiness.installedLocalModels + [readiness.configuration.tag])).sorted()
        if readiness.installedLocalModels.isEmpty {
            LabeledContent("Model", value: readiness.modelLabel)
        } else {
            Picker("Model", selection: Binding(
                get: { readiness.configuration.tag },
                set: { readiness.selectModel($0) }
            )) {
                ForEach(options, id: \.self) { tag in
                    Text(readiness.installedLocalModels.contains(tag) ? tag : "\(tag) (not installed)").tag(tag)
                }
            }
        }
    }

    #if DEBUG
    private func translateSample() {
        isTranslatingSample = true
        sampleResult = nil
        Task {
            let result = await readiness.translateSample()
            isTranslatingSample = false
            switch result {
            case .success(let output):
                sampleResult = "“\(OllamaReadinessService.sampleSentence)” → “\(output.text)” (\(output.milliseconds) ms)"
            case .failure(let error):
                sampleResult = "Lỗi: \(error)"
            }
        }
    }
    #endif
}
