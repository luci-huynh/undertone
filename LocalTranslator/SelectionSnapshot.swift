import ApplicationServices
import Foundation

/// Immutable capture of the user's selection at trigger time. Lives in memory
/// only; never logged or persisted.
nonisolated struct SelectionSnapshot: Equatable, Sendable {
    let sourcePID: pid_t
    let sourceAppName: String?
    let text: String
    /// UTF-16 based range as reported by the source app, when exposed.
    let range: NSRange?
    /// Popup anchor from the selection bounds or the trigger-time cursor;
    /// nil only when no screen is available.
    let anchor: SelectionAnchor?
    let capturedAt: Date
}

nonisolated enum SelectionFailure: Error, Equatable, Sendable {
    case permissionMissing
    case noFrontmostApp
    case sourceIsSelf
    case secureInput
    case noFocusedElement
    /// The focused element does not expose selected text through Accessibility.
    case unsupported
    case noSelection
    /// The source app did not answer within the AX messaging timeout.
    case timedOut
    /// Frontmost app or focused element changed while reading.
    case focusChanged
    case selectionChanged
    case cancelled
    case axError(Int32)

    var label: String {
        switch self {
        case .permissionMissing: "Chưa cấp quyền Accessibility"
        case .noFrontmostApp: "Không xác định được app đang dùng"
        case .sourceIsSelf: "Đang ở chính Undertone"
        case .secureInput: "Ô nhập bảo mật, không đọc"
        case .noFocusedElement: "Không có thành phần đang focus"
        case .unsupported: "App không hỗ trợ đọc vùng chọn"
        case .noSelection: "No text selected."
        case .timedOut: "App nguồn không phản hồi kịp"
        case .focusChanged: "Focus đã đổi trong lúc đọc"
        case .selectionChanged: "Vùng chọn đã đổi trong lúc đọc"
        case .cancelled: "Đã hủy lượt đọc"
        case .axError(let code): "Lỗi Accessibility (\(code))"
        }
    }
}

nonisolated struct SourceApp: Equatable, Sendable {
    let pid: pid_t
    let name: String?
}

/// Result of one AX attribute read, reduced to what classification needs.
nonisolated enum AXRead<Value: Equatable & Sendable>: Equatable, Sendable {
    case value(Value)
    case failed(AXError)
}

/// Raw facts read from the focused element. `selectedText` is nil when it was
/// deliberately not read (secure field) or the focused element was unavailable.
nonisolated struct FocusedElementReading: Equatable, Sendable {
    var failure: SelectionFailure?
    var focusedElementError: AXError?
    var elementPID: pid_t?
    var isSecureTextField = false
    var selectedText: AXRead<String>?
    var selectedRange: NSRange?
    /// Bounds of `selectedRange` in AX coordinates, when the element exposes them.
    var selectionBounds: CGRect?
}

nonisolated enum SelectionClassifier {
    /// - Parameter isRegularApp: whether a pid is an ordinary app (Dock
    ///   presence). The focused element comes from the source app's own AX tree,
    ///   so a different pid usually means content served by a helper process —
    ///   Safari/WKWebView pages (WebContent), remote view services — not another
    ///   app. Only another regular app's element counts as a focus change.
    static func classify(
        source: SourceApp,
        reading: FocusedElementReading,
        frontmostAfterRead: pid_t?,
        anchor: SelectionAnchor?,
        capturedAt: Date,
        isRegularApp: (pid_t) -> Bool = { _ in false }
    ) -> Result<SelectionSnapshot, SelectionFailure> {
        if let failure = reading.failure { return .failure(failure) }
        if let error = reading.focusedElementError {
            return .failure(failure(forFocusedElementError: error))
        }
        if let elementPID = reading.elementPID, elementPID != source.pid, isRegularApp(elementPID) {
            return .failure(.focusChanged)
        }
        if reading.isSecureTextField {
            return .failure(.secureInput)
        }
        guard let selectedText = reading.selectedText else {
            return .failure(.noFocusedElement)
        }
        let text: String
        switch selectedText {
        case .value(let value):
            text = value
        case .failed(let error):
            return .failure(failure(forSelectedTextError: error))
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(.noSelection)
        }
        guard frontmostAfterRead == source.pid else {
            return .failure(.focusChanged)
        }
        return .success(SelectionSnapshot(
            sourcePID: source.pid,
            sourceAppName: source.name,
            text: text,
            range: reading.selectedRange,
            anchor: anchor,
            capturedAt: capturedAt
        ))
    }

    private static func failure(forFocusedElementError error: AXError) -> SelectionFailure {
        switch error {
        case .noValue, .attributeUnsupported, .invalidUIElement: .noFocusedElement
        case .cannotComplete: .timedOut
        case .apiDisabled: .permissionMissing
        case .notImplemented: .unsupported
        default: .axError(error.rawValue)
        }
    }

    private static func failure(forSelectedTextError error: AXError) -> SelectionFailure {
        switch error {
        case .attributeUnsupported, .notImplemented: .unsupported
        case .noValue: .noSelection
        case .cannotComplete: .timedOut
        case .invalidUIElement: .focusChanged
        case .apiDisabled: .permissionMissing
        default: .axError(error.rawValue)
        }
    }
}
