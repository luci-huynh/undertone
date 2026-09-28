import SwiftUI

/// Settings: runtime/model status and selection, permission, shortcut.
/// Vietnamese throughout (L08 review: one language per surface; the popup,
/// menu and Live window follow PLAN's English wording).
struct ContentView: View {
    let coordinator: AppCoordinator

    var body: some View {
        Form {
            OllamaSection(readiness: coordinator.readiness)
            AccessibilityPermissionSection(permission: coordinator.permission)
            ShortcutSection(shortcut: coordinator.shortcut)
            SelectionTriggerSection(trigger: coordinator.selectionTrigger)
            LaunchAtLoginSection(launchAtLogin: coordinator.launchAtLogin)
            Section("Cách dùng") {
                Text("⌥T dịch văn bản đang bôi đen. Tự nhận diện: tiếng Anh → tiếng Việt, tiếng Việt → tiếng Anh, ngôn ngữ khác → tiếng Việt; nút ⇄ trong popup đổi chiều cho lần dịch đó.")
                Text("Dịch cuộc họp trực tiếp (tiếng Anh → tiếng Việt): menu Undertone ▸ Live Meeting Translation… — cần macOS 26 trở lên.")
            }
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 480, idealHeight: 680)
        .onAppear {
            coordinator.permission.refresh()
            Task { await coordinator.readiness.refresh() }
        }
        // Reopening an existing Settings window, or returning from System Settings,
        // does not re-run onAppear; the window becoming key does.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            coordinator.permission.refresh()
            coordinator.launchAtLogin.refresh()
        }
    }
}

private struct AccessibilityPermissionSection: View {
    let permission: AccessibilityPermissionService
    /// The stale-grant hint only helps after the user has tried to grant.
    @State private var openedSystemSettings = false

    private static let hint = "Mở System Settings › Privacy & Security › Accessibility (macOS mới: Device Control and Data Access), bật Undertone rồi quay lại đây."
    private static let afterRequestHint = "Nếu đã từ chối hoặc không thấy hộp thoại, bật Undertone trực tiếp trong System Settings › Privacy & Security › Accessibility (macOS mới: Device Control and Data Access)."
    private static let staleGrantHint = "Công tắc đã bật mà vẫn báo chưa cấp quyền (thường gặp sau khi build lại app)? Xoá Undertone khỏi danh sách bằng nút − rồi thêm lại, hoặc tắt rồi bật lại công tắc."

    var body: some View {
        Section {
            LabeledContent("Trạng thái") { badge }
            if permission.state == .notGranted {
                Text("Cần quyền này để đọc văn bản bạn bôi đen.")
                Text(permission.hasRequestedThisLaunch ? Self.afterRequestHint : Self.hint)
                    .foregroundStyle(.secondary)
                if permission.hasRequestedThisLaunch || openedSystemSettings {
                    Text(Self.staleGrantHint)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if permission.canRequestAccess {
                        Button("Xin quyền…") { permission.requestAccess() }
                    }
                    Button("Mở System Settings") {
                        openedSystemSettings = true
                        permission.openSystemSettings()
                    }
                }
            }
        } header: {
            Text("Quyền Accessibility")
        }
    }

    private var badge: StatusBadge {
        switch permission.state {
        case .notChecked: StatusBadge(kind: .neutral, text: permission.state.label)
        case .granted: StatusBadge(kind: .ok, text: permission.state.label)
        case .notGranted: StatusBadge(kind: .error, text: permission.state.label)
        }
    }
}

private struct ShortcutSection: View {
    let shortcut: GlobalShortcutService

    var body: some View {
        Section("Phím tắt") {
            LabeledContent("Dịch văn bản đã chọn") {
                StatusBadge(kind: kind, text: "\(shortcut.combination.display) · \(shortcut.status.label)")
            }
            switch shortcut.status {
            case .conflict, .failed:
                Text("\(shortcut.combination.display) đang được app khác dùng hoặc không đăng ký được. Hãy đóng app đang dùng phím tắt này rồi thử lại.")
                    .foregroundStyle(.secondary)
                Button("Thử lại") { shortcut.start() }
            case .registered, .inactive:
                EmptyView()
            }
            #if DEBUG
            LabeledContent("Đã nhận trong phiên này (Debug)", value: "\(shortcut.triggerCount) lần")
            #endif
        }
    }

    private var kind: StatusBadge.Kind {
        switch shortcut.status {
        case .registered: .ok
        case .conflict: .warning
        case .failed: .error
        case .inactive: .neutral
        }
    }
}

private struct SelectionTriggerSection: View {
    let trigger: SelectionTriggerService

    var body: some View {
        Section {
            Toggle("Hiện nút dịch cạnh con trỏ", isOn: Binding(get: { trigger.isEnabled }, set: { trigger.setEnabled($0) }))
        } header: {
            Text("Nút dịch khi bôi đen")
        } footer: {
            Text("Kéo chuột hoặc nhấp đúp để bôi đen → bấm biểu tượng dịch. Chỉ theo dõi chuột, không theo dõi bàn phím; ⌥T luôn dùng được.")
        }
    }
}

private struct LaunchAtLoginSection: View {
    let launchAtLogin: LaunchAtLoginService

    var body: some View {
        Section("Khởi động") {
            Toggle("Mở cùng macOS", isOn: Binding(get: { launchAtLogin.isOn }, set: { launchAtLogin.setOn($0) }))
            if launchAtLogin.needsApproval {
                Text("macOS cần bạn cho phép trong Login Items.")
                    .foregroundStyle(.secondary)
                Button("Mở Login Items") { launchAtLogin.openSystemSettings() }
            }
            if let error = launchAtLogin.lastError {
                StatusBadge(kind: .error, text: error)
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
        Section {
            LabeledContent("Trạng thái") { runtimeBadge }
            if let runtimeDetail {
                Text(runtimeDetail)
                    .foregroundStyle(.secondary)
            }
            modelRow
            switch readiness.model {
            case .missing:
                VStack(alignment: .leading, spacing: 4) {
                    StatusBadge(kind: .error, text: "Chưa cài model dịch. Tải trong Terminal:")
                    Text("ollama pull \(readiness.configuration.tag)")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            case .cloudRejected:
                StatusBadge(kind: .error, text: "Model cloud chạy trên server của Ollama nên bị từ chối; chọn model local.")
            case .unknown, .installed:
                EmptyView()
            }
            HStack {
                // The only refresh button: Settings also re-checks every 20 s.
                Button("Kiểm tra lại") { Task { await readiness.refresh() } }
                if readiness.runtime == .notRunning, OllamaAppLauncher.appURL != nil {
                    Button("Mở Ollama") { OllamaAppLauncher.open() }
                }
            }
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
        } header: {
            Text("Ollama")
        } footer: {
            Text("Văn bản chỉ được gửi tới Ollama trên chính máy này (localhost), không ra ngoài.")
        }
    }

    private var runtimeBadge: StatusBadge {
        switch readiness.runtime {
        case .notChecked: StatusBadge(kind: .neutral, text: "Đang kiểm tra…")
        case .connected(let version): StatusBadge(kind: .ok, text: "Đã kết nối · \(version)")
        case .notRunning: StatusBadge(kind: .error, text: "Chưa chạy")
        case .notResponding: StatusBadge(kind: .warning, text: "Không phản hồi")
        case .invalidResponse: StatusBadge(kind: .warning, text: "Phản hồi không đúng")
        case .endpointRejected: StatusBadge(kind: .error, text: "Bị chặn: không phải localhost")
        }
    }

    private var runtimeDetail: String? {
        switch readiness.runtime {
        case .notRunning: "Mở Ollama rồi bấm Kiểm tra lại."
        case .notResponding: "Ollama không trả lời kịp (đang bận hoặc đang khởi động). Thử lại sau giây lát."
        case .invalidResponse: "Cổng \(readiness.client?.baseURL.port ?? 11434) trả lời nhưng không phải Ollama API."
        case .endpointRejected: "Địa chỉ Ollama đã cấu hình không phải localhost nên bị chặn; không gửi gì ra ngoài máy."
        case .notChecked, .connected: nil
        }
    }

    @ViewBuilder
    private var modelRow: some View {
        let tag = readiness.configuration.tag
        if readiness.installedLocalModels.isEmpty {
            LabeledContent("Model", value: readiness.model == .missing ? "\(tag) (chưa cài)" : tag)
        } else {
            let options = Array(Set(readiness.installedLocalModels + [tag])).sorted()
            Picker("Model", selection: Binding(get: { tag }, set: { readiness.selectModel($0) })) {
                ForEach(options, id: \.self) { option in
                    Text(Self.optionTitle(option, installed: readiness.installedLocalModels.contains(option))).tag(option)
                }
            }
        }
    }

    private static func optionTitle(_ tag: String, installed: Bool) -> String {
        if !installed { return "\(tag) (chưa cài)" }
        return tag == TranslationModelConfiguration.defaultTag ? "\(tag) (khuyên dùng)" : tag
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
