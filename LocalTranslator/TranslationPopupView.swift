import AppKit
import SwiftUI

/// What the popup shows. Lives only while the popup is open.
struct PopupContent: Equatable {
    enum Phase: Equatable {
        /// Request started, nothing received yet (PLAN F03 loading state).
        case loading
        /// Output arriving; body is the partial text.
        case streaming
        /// Output complete; Copy is enabled.
        case done
        /// A short message instead of output (e.g. “No text selected.”).
        case notice
        /// Request failed; `body` keeps any partial output, `message` says why.
        case failed
    }

    enum Action: Equatable {
        case openAccessibilitySettings
        /// ⇄: translate the same text in `alternateDirection`.
        case switchDirection
        /// PLAN §14 [Retry]: the same request once more (S23).
        case retry

        var label: String {
            switch self {
            case .openAccessibilitySettings: "Open System Settings"
            case .switchDirection: "Switch direction"
            case .retry: "Retry"
            }
        }
    }

    /// Direction line, e.g. “English → Vietnamese”.
    let title: String
    let body: String
    var phase: Phase = .done
    var action: Action? = nil
    /// Secondary line under the body (failure reason).
    var message: String? = nil
    /// Same value for every update of one request, so the view (scroll
    /// position, “Copied”) survives streaming renders; a new value starts fresh.
    var session: UUID? = nil
    /// Where ⇄ would translate instead; nil hides the button.
    var alternateDirection: TranslationDirection? = nil
    /// ↻ next to Copy: translate the same text again (S25, user request).
    var offersRetranslate = false

    var canCopy: Bool { phase == .done && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// A failure that kept partial output: labelled so it is not taken as complete.
    var isIncomplete: Bool { phase == .failed && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Size rules for the popup (PLAN F03: resize to content within a max
/// width/height; long text scrolls).
enum PopupMetrics {
    static let bodyFont = NSFont.systemFont(ofSize: 14)
    static let padding: CGFloat = 14
    static let minWidth: CGFloat = 260
    static let maxWidth: CGFloat = 440
    static let maxBodyHeight: CGFloat = 320
    /// One line; a short translation does not leave an empty gap (S25).
    static let minBodyHeight: CGFloat = 20
    /// Extra space between lines so stacked Vietnamese marks (Ỹ, Ậ, Ữ) do
    /// not touch the line above (S25 render review).
    static let lineSpacing: CGFloat = 3
    /// SwiftUI and AppKit measure the same font slightly differently.
    private static let slack: CGFloat = 4

    /// Popup width and body height for `body`, limited by `maxSize` (the
    /// usable screen area).
    static func layout(for body: String, maxSize: CGSize) -> (width: CGFloat, bodyHeight: CGFloat) {
        let widthLimit = min(maxWidth, maxSize.width)
        // Text that has to wrap uses the full width; shorter text shrinks to fit.
        let natural = ceil(measure(body, width: .greatestFiniteMagnitude).width) + 2 * padding + slack
        let width = min(widthLimit, max(minWidth, natural))
        let height = ceil(measure(body, width: width - 2 * padding).height) + slack
        return (width, min(max(height, minBodyHeight), maxBodyHeight))
    }

    private static func measure(_ text: String, width: CGFloat) -> CGSize {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return NSAttributedString(string: text, attributes: [.font: bodyFont, .paragraphStyle: paragraph]).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
    }
}

struct TranslationPopupView: View {
    let content: PopupContent
    let width: CGFloat
    let bodyHeight: CGFloat
    let onCopy: () -> Void
    let onAction: (PopupContent.Action) -> Void
    let onClose: () -> Void

    @State private var copied = false
    /// Keep the newest streamed text in view while the reader is at the
    /// bottom; scrolling up stops it, scrolling back to the bottom resumes it.
    @State private var followsOutput = true
    private static let bottomID = "bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !content.title.isEmpty {
                HStack {
                    Text(content.title)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if content.isIncomplete {
                        Text("Incomplete")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Incomplete translation")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
            }
            if content.phase == .loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                        .accessibilityHidden(true)
                    Text("Translating…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: bodyHeight, alignment: .leading)
            } else if !content.body.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(content.body)
                                .font(Font(PopupMetrics.bodyFont))
                                .lineSpacing(PopupMetrics.lineSpacing)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(height: 1).id(Self.bottomID)
                        }
                    }
                    .frame(height: bodyHeight)
                    .onChange(of: content.body) {
                        guard content.phase == .streaming, followsOutput else { return }
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                    .modifier(BottomFollowTracker(followsOutput: $followsOutput))
                }
            }
            if let message = content.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(content.phase == .failed ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let action = content.action {
                    Button(action.label) { onAction(action) }
                } else if content.phase != .notice && content.phase != .failed {
                    Button {
                        onCopy()
                        copied = true
                    } label: {
                        // ✓ in the space of “Copy”: the row keeps its width, so
                        // ↻ and ⇄ never shift and the narrowest popup still fits.
                        ZStack {
                            Text("Copy").opacity(copied ? 0 : 1)
                            Image(systemName: "checkmark").opacity(copied ? 1 : 0)
                        }
                    }
                    .help(copied ? "Copied" : "Copy the translation")
                    .accessibilityLabel(copied ? "Copied" : "Copy")
                    .disabled(!content.canCopy)
                }
                if content.offersRetranslate {
                    Button {
                        onAction(.retry)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Translate again")
                    .accessibilityLabel("Translate again")
                }
                if let alternate = content.alternateDirection {
                    Button {
                        onAction(.switchDirection)
                    } label: {
                        Label(alternate.shortTitle, systemImage: "arrow.left.arrow.right")
                    }
                    .help("Translate \(alternate.title) instead")
                    .accessibilityLabel("Translate \(alternate.title) instead")
                }
                if content.phase == .streaming {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Translating")
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close (Esc)")
                .accessibilityLabel("Close")
            }
        }
        .padding(PopupMetrics.padding)
        .frame(width: width)
        // Empty areas move the popup; text keeps its selection drag, buttons their clicks.
        .background(WindowDragArea())
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

/// Decides auto-follow from scroll geometry, so it works the same for mouse
/// wheels, trackpads and scroll-bar drags. Only offset changes count: when the
/// content grows (a streamed delta) the decision is kept, otherwise a new line
/// would look like “the reader left the bottom”. Needs macOS 15; on macOS 14
/// the popup keeps following while streaming.
/// Also used by the Live window (L05).
struct BottomFollowTracker: ViewModifier {
    @Binding var followsOutput: Bool
    /// How close to the bottom counts as “at the bottom”.
    var tolerance: CGFloat = 4

    private struct Metrics: Equatable {
        let distanceFromBottom: CGFloat
        let contentHeight: CGFloat
    }

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: Metrics.self) { geometry in
                Metrics(
                    distanceFromBottom: geometry.contentSize.height - geometry.visibleRect.maxY,
                    contentHeight: geometry.contentSize.height
                )
            } action: { old, new in
                guard new.contentHeight == old.contentHeight else { return }
                followsOutput = new.distanceFromBottom <= tolerance
            }
        } else {
            content
        }
    }
}

/// Drag handle behind the popup content (S25): moves the panel without
/// activating the app. Works on the first click although the panel is not key.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
