import Foundation
import Testing
@testable import Undertone

/// Synthetic bilingual fixtures. Expectations state intent (clear cases route,
/// unclear cases are never decided with confidence); they were calibrated on
/// the macOS 27 NaturalLanguage model and may need review on other versions.
struct LanguageRouterTests {
    @Test(arguments: [
        "The payment has been processed and the receipt was sent to your email.",
        "We expect the migration to finish sometime next week.",
        "Deploy failed",
        "Thanks!",
    ])
    func clearEnglish(_ text: String) {
        #expect(LanguageRouter.detect(text) == .english)
    }

    @Test(arguments: [
        "Thanh toán đã được xử lý và hóa đơn đã được gửi đến email của bạn.",
        "Chúng tôi dự kiến quá trình migration sẽ hoàn tất vào khoảng tuần sau.",
        "Thanh toan da duoc xu ly va hoa don da duoc gui den email cua ban.",
        "Xin chào",
        "Cảm ơn",
        "Ngày mai",
        // Vietnamese with English terms routes VI → EN.
        "Họp lúc 3pm với team về migration plan nhé",
        "Please review the PR trước khi merge nhé anh",
    ])
    func clearVietnamese(_ text: String) {
        #expect(LanguageRouter.detect(text) == .vietnamese)
    }

    @Test func decomposedVietnameseStillDetected() {
        let nfd = "Thanh toán đã được xử lý.".decomposedStringWithCanonicalMapping
        #expect(nfd.unicodeScalars.count > "Thanh toán đã được xử lý.".unicodeScalars.count)
        #expect(LanguageRouter.detect(nfd) == .vietnamese)
    }

    @Test func otherLanguagesAreNotForcedIntoEnglishOrVietnamese() {
        #expect(LanguageRouter.detect("Bonjour, comment allez-vous aujourd'hui ?") == .other("fr"))
        #expect(LanguageRouter.detect("Das ist ein sehr schönes Haus.") == .other("de"))
        #expect(LanguageRouter.detect("こんにちは、元気ですか") == .other("ja"))
    }

    @Test func shortOrUnclearTextIsAmbiguousWithAGuess() {
        #expect(LanguageRouter.detect("OK") == .ambiguous(bestGuess: .english))
        #expect(LanguageRouter.detect("ok") == .ambiguous(bestGuess: .english))
        #expect(LanguageRouter.detect("Hello") == .ambiguous(bestGuess: .english))
        #expect(LanguageRouter.detect("toi di hoc") == .ambiguous(bestGuess: .vietnamese))
        // Vietnamese-only letters decide the guess even when too short to route.
        #expect(LanguageRouter.detect("ơi") == .ambiguous(bestGuess: .vietnamese))
    }

    @Test func codeAndNumbersAreNeverRoutedConfidently() {
        for text in ["let x = foo(bar) // TODO", "12/10/2026 - 500.000 VND"] {
            let detection = LanguageRouter.detect(text)
            #expect(detection != .english && detection != .vietnamese, "\(text) → \(detection)")
        }
    }

    @Test func textWithoutWordsIsNotText() {
        #expect(LanguageRouter.detect("https://github.com/chienhuynh-dev/local-ai-translator") == .notText)
        #expect(LanguageRouter.detect("someone@example.com 2026-09-28 42%") == .notText)
        #expect(LanguageRouter.detect("  \n ") == .notText)
    }

    /// L08 review: detection runs on the main actor before the size check, so
    /// a long run without spaces (minified code, base64, CJK) must stay instant.
    @Test func longTextWithoutSpacesIsDetectedInstantly() {
        let start = ContinuousClock.now
        _ = LanguageRouter.detect(String(repeating: "x@y", count: 500))
        _ = LanguageRouter.detect(String(repeating: "a", count: 200_000))
        _ = LanguageRouter.detect(String(repeating: "The meeting starts at nine. ", count: 20_000))
        #expect(ContinuousClock.now - start < .milliseconds(500))
        #expect(LanguageRouter.detect("Mail john@example.com about the payment receipt that was sent yesterday.") == .english)
    }

    /// Chat apps show links without a scheme, often shortened with “…” (S21a).
    @Test(arguments: [
        "app.example.com/p/team/…/Admin-Portal-Enable-Platform-functionality-per-merchant-currency…?source=copy_link",
        "docs.example.org/guides/getting-started",
        "example.com",
        "(app.example.com/p/Enable-Platform-functionality)",
    ])
    func schemelessLinksAreNotText(_ text: String) {
        #expect(LanguageRouter.detect(text) == .notText)
    }

    @Test func linkInsideASentenceLeavesTheSentence() {
        #expect(LanguageRouter.detect("The payment receipt was sent yesterday, see billing.example.com/invoices for all the details.") == .english)
        #expect(LanguageRouter.detect("Hóa đơn đã được gửi hôm qua, xem chi tiết ở billing.example.com/invoices nhé.") == .vietnamese)
    }

    @Test func accentsAloneDoNotMeanVietnamese() {
        #expect(LanguageRouter.detect("café au lait") != .vietnamese)
        #expect(LanguageRouter.detect("Déjà vu, naïve résumé") != .vietnamese)
    }

    @Test func routesFollowPlanAndUserDecisions() {
        #expect(TranslationRoute(.english) == .translate(.englishToVietnamese, guessed: false))
        #expect(TranslationRoute(.vietnamese) == .translate(.vietnameseToEnglish, guessed: false))
        #expect(TranslationRoute(.ambiguous(bestGuess: .english)) == .translate(.englishToVietnamese, guessed: true))
        #expect(TranslationRoute(.ambiguous(bestGuess: .vietnamese)) == .translate(.vietnameseToEnglish, guessed: true))
        #expect(TranslationRoute(.other("ja")) == .translate(TranslationDirection(source: TranslationLanguage(code: "ja"), target: .vietnamese), guessed: false))
        #expect(TranslationRoute(.notText) == .nothingToTranslate)
    }

    @Test func switchedSwapsEnglishAndVietnameseAndTogglesTargetOtherwise() {
        #expect(TranslationDirection.englishToVietnamese.switched == .vietnameseToEnglish)
        #expect(TranslationDirection.vietnameseToEnglish.switched == .englishToVietnamese)
        let french = TranslationDirection(source: TranslationLanguage(code: "fr"), target: .vietnamese)
        #expect(french.switched.source.code == "fr")
        #expect(french.switched.target == .english)
        #expect(french.switched.switched == french)
    }

    @Test func languageNamesForPromptAndPopup() {
        #expect(TranslationLanguage(code: "fr").name == "French")
        #expect(TranslationLanguage(code: "ja").name == "Japanese")
        #expect(TranslationLanguage(code: "en") == .english)
        #expect(TranslationDirection.vietnameseToEnglish.shortTitle == "VI → EN")
        #expect(TranslationDirection(source: TranslationLanguage(code: "zh-Hans"), target: .english).shortTitle == "ZH → EN")
    }
}
