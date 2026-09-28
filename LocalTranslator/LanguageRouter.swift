import Foundation
import NaturalLanguage

/// What the selection is written in, decided on-device (PLAN F05).
nonisolated enum LanguageDetection: Equatable, Sendable {
    case english
    case vietnamese
    /// Clearly another language (BCP-47 code from NaturalLanguage, e.g. "fr").
    case other(String)
    /// Too short or mixed to decide; `bestGuess` is the likelier of EN/VI.
    case ambiguous(bestGuess: TranslationLanguage)
    /// No words left after removing URLs, e-mail addresses, numbers and symbols.
    case notText
}

/// Confidence policy, calibrated on synthetic samples with the macOS 27
/// recognizer (docs/PROGRESS.md S21). The unconstrained dominant language
/// decides first; constraining to EN/VI alone is misleading (French scores
/// “en 0.59”, a date/amount string “vi 0.93”, “cam on” “en 0.92”).
nonisolated enum LanguageRouter {
    /// Dominant-language probability needed to call a text English.
    static let englishThreshold = 0.8
    /// Unaccented Vietnamese scores lower (≈ 0.75 for a full sentence).
    static let vietnameseThreshold = 0.7
    static let otherLanguageThreshold = 0.8
    /// Fewer letters than this is never decided (“OK”, “Hi”).
    static let minimumLetters = 3

    static func detect(_ text: String) -> LanguageDetection {
        // Some apps hand over decomposed (NFD) text; tone marks must still match.
        let words = strippedForDetection(text.precomposedStringWithCanonicalMapping)
        let letters = words.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters > 0 else { return .notText }
        let guess = bestGuess(words)
        guard letters >= minimumLetters else { return .ambiguous(bestGuess: guess) }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(words)
        guard let (language, probability) = recognizer.languageHypotheses(withMaximum: 1).first else {
            return .ambiguous(bestGuess: guess)
        }
        switch language {
        case .english where probability >= englishThreshold:
            return .english
        case .vietnamese where probability >= vietnameseThreshold:
            return .vietnamese
        case .english, .vietnamese, .undetermined:
            return .ambiguous(bestGuess: guess)
        default:
            return probability >= otherLanguageThreshold ? .other(language.rawValue) : .ambiguous(bestGuess: guess)
        }
    }

    /// Removes parts that carry no language: URLs (also scheme-less ones as
    /// chat apps show them, “app.example.com/p/…”), e-mail addresses, digits.
    static func strippedForDetection(_ text: String) -> String {
        var result = text
        for pattern in [#"(?i)\b(?:https?://|www\.)\S+"#, #"\S+@\S+\.\S+"#, schemelessLinkPattern, #"[0-9]+"#] {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return result
    }

    /// A host (labels, then a 2+ letter TLD) not glued to a preceding word,
    /// plus any port and path. “e.g.” and “U.S.” do not match.
    private static let schemelessLinkPattern = #"(?i)(?<![\w@.-])(?:[a-z0-9-]+\.)+[a-z]{2,}(?::[0-9]+)?(?:/\S*)?"#

    /// EN vs VI only, for ambiguous texts; Vietnamese-only letters win outright.
    private static func bestGuess(_ text: String) -> TranslationLanguage {
        if text.unicodeScalars.contains(where: vietnameseOnly.contains) { return .vietnamese }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .vietnamese]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        return (hypotheses[.vietnamese] ?? 0) > (hypotheses[.english] ?? 0) ? .vietnamese : .english
    }

    /// Letters used by Vietnamese and (practically) by no other Latin-script
    /// language this app meets: ă, đ, ơ, ư and the dot-below/hook-above tones.
    private static let vietnameseOnly: Set<Unicode.Scalar> = {
        let letters = "ăắằẳẵặđơớờởỡợưứừửữựạảấầẩẫậẹẻẽếềểễệỉịọỏốồổỗộụủỳỵỷỹ"
        return Set((letters + letters.uppercased()).unicodeScalars)
    }()
}

/// Source and target of one request.
nonisolated struct TranslationDirection: Equatable, Sendable {
    let source: TranslationLanguage
    let target: TranslationLanguage

    static let englishToVietnamese = TranslationDirection(source: .english, target: .vietnamese)
    static let vietnameseToEnglish = TranslationDirection(source: .vietnamese, target: .english)

    /// “English → Vietnamese”.
    var title: String { "\(source.name) → \(target.name)" }
    /// “EN → VI”, for the ⇄ button; the primary subtag only (“zh-Hans” → “ZH”)
    /// so the button row fits the narrowest popup (S25 render review).
    var shortTitle: String { "\(Self.short(source.code)) → \(Self.short(target.code))" }

    private static func short(_ code: String) -> String {
        (code.split(separator: "-").first.map(String.init) ?? code).uppercased()
    }

    /// The popup's ⇄ (user decision S21): English and Vietnamese swap; another
    /// source language keeps its source and switches the target VI ↔ EN.
    var switched: TranslationDirection {
        switch source {
        case .english: .vietnameseToEnglish
        case .vietnamese: .englishToVietnamese
        default: TranslationDirection(source: source, target: target == .vietnamese ? .english : .vietnamese)
        }
    }
}

/// What ⌥T does with a selection: PLAN F05 rules plus the S21 user decisions
/// (ambiguous → best guess, marked and switchable; other languages →
/// Vietnamese; EN → VI stays the default when nothing points to Vietnamese).
nonisolated enum TranslationRoute: Equatable, Sendable {
    /// `guessed`: detection was not confident, and the popup says so.
    case translate(TranslationDirection, guessed: Bool)
    case nothingToTranslate

    init(_ detection: LanguageDetection) {
        switch detection {
        case .english: self = .translate(.englishToVietnamese, guessed: false)
        case .vietnamese: self = .translate(.vietnameseToEnglish, guessed: false)
        case .other(let code): self = .translate(TranslationDirection(source: TranslationLanguage(code: code), target: .vietnamese), guessed: false)
        case .ambiguous(let guess):
            self = .translate(guess == .vietnamese ? .vietnameseToEnglish : .englishToVietnamese, guessed: true)
        case .notText: self = .nothingToTranslate
        }
    }
}
