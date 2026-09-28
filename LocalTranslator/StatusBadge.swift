import SwiftUI

/// One status style for Settings and the Live window (L08 review): an SF
/// Symbol and a colour with a fixed meaning, the text itself in the primary
/// colour so it stays readable whatever the state.
struct StatusBadge: View {
    enum Kind {
        case ok, warning, error, neutral
    }

    let kind: Kind
    let text: String
    /// Replaces the kind's symbol (neutral states: stopped, preparing, quiet).
    var symbol: String?

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol ?? Self.symbol(for: kind))
                .foregroundStyle(Self.color(for: kind))
        }
    }

    static func symbol(for kind: Kind) -> String {
        switch kind {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .neutral: "circle.dotted"
        }
    }

    static func color(for kind: Kind) -> Color {
        switch kind {
        case .ok: .green
        case .warning: .orange
        case .error: .red
        case .neutral: .secondary
        }
    }
}
