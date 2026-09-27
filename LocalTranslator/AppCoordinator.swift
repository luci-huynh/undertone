import Foundation

@MainActor
protocol RuntimeReadinessProviding {
    var status: RuntimeReadiness { get }
}

enum RuntimeReadiness: Equatable {
    case notChecked
    case available
    case unavailable

    var label: String {
        switch self {
        case .notChecked: "Chưa kiểm tra"
        case .available: "Sẵn sàng"
        case .unavailable: "Không khả dụng"
        }
    }
}

/// Inert dependency for the shell: does not inspect processes or use the network.
struct UnconfiguredReadinessService: RuntimeReadinessProviding {
    let status: RuntimeReadiness = .notChecked
}

@MainActor
final class AppCoordinator {
    private let readiness: any RuntimeReadinessProviding
    let permission: AccessibilityPermissionService
    let translation = TranslationStateMachine()

    init(readiness: any RuntimeReadinessProviding, permission: AccessibilityPermissionService) {
        self.readiness = readiness
        self.permission = permission
    }

    var runtimeStatus: String { readiness.status.label }

    func shutdown() {
        translation.dismiss()
    }
}
