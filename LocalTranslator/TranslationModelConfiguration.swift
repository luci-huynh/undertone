import Foundation

/// A language as the prompt names it: BCP-47 code and English name.
nonisolated struct TranslationLanguage: Hashable, Sendable {
    let code: String
    let name: String

    static let english = TranslationLanguage(code: "en", name: "English")
    static let vietnamese = TranslationLanguage(code: "vi", name: "Vietnamese")

    /// Another language NaturalLanguage recognized, e.g. "fr" → “French”.
    init(code: String) {
        self.init(code: code, name: Locale(identifier: "en").localizedString(forIdentifier: code) ?? code)
    }

    private init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

/// Which model translates, kept apart from the client (PLAN F01: model
/// configurable, no single hard-coded architecture).
nonisolated struct TranslationModelConfiguration: Equatable, Sendable {
    /// Approved at S17 (docs/OLLAMA.md).
    static let defaultTag = "translategemma:12b"

    let tag: String

    init(tag: String?) {
        let trimmed = tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.tag = trimmed.isEmpty ? Self.defaultTag : trimmed
    }

    var isCloud: Bool { ModelTag.isCloud(tag) }

    /// Prompt messages for this model (adapter per model, runbook S22).
    func messages(translating text: String, direction: TranslationDirection) -> [Ollama.ChatMessage] {
        TranslationPromptBuilder.messages(for: text, direction: direction, model: tag)
    }
}

/// Stores configuration only (model tag, optional endpoint override) — never text.
protocol ModelSettingsStoring: AnyObject {
    var modelTag: String? { get set }
    /// Optional `http://127.0.0.1:<port>` override; anything non-loopback is rejected.
    var baseURLString: String? { get }
}

final class UserDefaultsModelSettings: ModelSettingsStoring {
    private let defaults: UserDefaults
    private static let modelKey = "TranslationModelTag"
    private static let baseURLKey = "OllamaBaseURL"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var modelTag: String? {
        get { defaults.string(forKey: Self.modelKey) }
        set { defaults.set(newValue, forKey: Self.modelKey) }
    }

    var baseURLString: String? { defaults.string(forKey: Self.baseURLKey) }
}
