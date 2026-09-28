import Foundation
import Testing
@testable import LocalTranslator

/// Synthetic fixture (Fixtures/TranslationCases.json). Checks are invariants
/// only — direction, language, kept names/numbers, line structure, no
/// commentary — never exact wording. Wording is judged by hand from the
/// `EVAL` lines this prints (fixture text only, never user text).
private struct TranslationCase: Decodable, Sendable, CustomTestStringConvertible {
    let id: String
    let source: String
    let text: String
    var keep: [String]?
    var keepDigits: [String]?
    var lines: Int?
    /// Outputs that would mean an instruction inside the text was obeyed.
    var mustNotBe: [String]?

    var testDescription: String { id }

    static let all: [TranslationCase] = {
        guard let url = Bundle(for: FixtureBundle.self).url(forResource: "TranslationCases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cases = try? JSONDecoder().decode([TranslationCase].self, from: data)
        else { return [] }
        return cases
    }()
}

private final class FixtureBundle {}

@Test func translationFixturesLoad() {
    #expect(TranslationCase.all.count == 15)
    #expect(Set(TranslationCase.all.map(\.id)).count == TranslationCase.all.count)
}

/// Runs only with TEST_RUNNER_LT_LIVE_OLLAMA=1 against the local Ollama.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LT_LIVE_OLLAMA"] == "1"), .serialized)
struct TranslationQualityLiveTests {
    @Test(arguments: TranslationCase.all)
    fileprivate func fixtureKeepsMeaningMarkers(_ item: TranslationCase) async throws {
        let readiness = OllamaReadinessService(settings: MemoryModelSettings(), transport: URLSessionTransport())
        await readiness.refresh()
        try #require(readiness.isReady, "Ollama \(readiness.runtime.label), \(readiness.modelLabel)")

        guard case .translate(let direction, _) = TranslationRoute(LanguageRouter.detect(item.text)) else {
            Issue.record("\(item.id) not routed")
            return
        }
        #expect(direction.source.code == item.source, "routed \(direction.shortTitle)")

        var output = ""
        for try await delta in OllamaTranslationService(readiness: readiness).translate(item.text, direction: direction) {
            output += delta
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        print("EVAL\t\(item.id)\t\(direction.shortTitle)\t\(trimmed.replacingOccurrences(of: "\n", with: "⏎"))")

        #expect(!trimmed.isEmpty)
        let detected = LanguageRouter.detect(trimmed)
        let target = direction.target
        #expect(detected == (target == .english ? .english : .vietnamese) || detected == .ambiguous(bestGuess: target), "output read as \(detected)")
        for word in item.keep ?? [] {
            #expect(trimmed.contains(word), "lost “\(word)”")
        }
        let digits = trimmed.filter(\.isNumber)
        for number in item.keepDigits ?? [] {
            #expect(digits.contains(number), "lost number \(number)")
        }
        for obeyed in item.mustNotBe ?? [] {
            #expect(trimmed.caseInsensitiveCompare(obeyed) != .orderedSame, "followed an instruction in the text")
        }
        if let lines = item.lines {
            #expect(trimmed.split(separator: "\n").count == lines, "line structure changed")
        }
        for preamble in ["Here is", "Here's", "Sure", "Translation:", "Bản dịch", "Dưới đây"] {
            #expect(!trimmed.hasPrefix(preamble), "commentary: \(preamble)")
        }
    }
}
