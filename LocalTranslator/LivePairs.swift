import Foundation

/// One EN/VI pair as the Live window shows it (PLAN §24.2 mockup). Segments
/// that were translated together (queue merge) form one pair, so a
/// translation is never shown under the wrong sentence.
nonisolated struct LivePair: Equatable, Identifiable, Sendable {
    enum Vietnamese: Equatable, Sendable {
        case waiting
        case translating(String)
        case done(String)
        case skipped
        case failed(String)
    }

    /// The last segment's ID (the one carrying the translation).
    let id: UUID
    let english: String
    let vietnamese: Vietnamese
}

nonisolated enum LivePairs {
    /// Groups settled segments with their translation state, oldest first.
    static func make(segments: [LiveTranscript.Segment], states: [UUID: LiveTranslationState]) -> [LivePair] {
        var pairs: [LivePair] = []
        var pending: [String] = []
        for segment in segments {
            pending.append(segment.text)
            let vietnamese: LivePair.Vietnamese
            switch states[segment.id] {
            case .merged:
                continue // its text joins the next pair
            case .waiting, nil: vietnamese = .waiting
            case .translating(let text): vietnamese = .translating(text)
            case .done(let text): vietnamese = .done(text)
            case .skipped: vietnamese = .skipped
            case .failed(let message): vietnamese = .failed(message)
            }
            pairs.append(LivePair(id: segment.id, english: pending.joined(separator: " "), vietnamese: vietnamese))
            pending = []
        }
        // A merge group whose last segment is no longer kept still shows its English.
        if !pending.isEmpty, let last = segments.last {
            pairs.append(LivePair(id: last.id, english: pending.joined(separator: " "), vietnamese: .waiting))
        }
        return pairs
    }
}
