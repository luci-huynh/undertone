import ApplicationServices
import Testing
@testable import LocalTranslator

struct AccessibilityTreeActivationTests {
    private final class Script {
        var answers: [FocusedLookup<String>]
        var reads = 0
        var activations = 0
        var pauses = 0
        let accepts: Bool

        init(_ answers: [FocusedLookup<String>], accepts: Bool = true) {
            self.answers = answers
            self.accepts = accepts
        }

        func run(retries: Int = 4) throws -> FocusedLookup<String> {
            try AccessibilityTreeActivation.lookUp(
                read: { defer { reads += 1 }; return answers[min(reads, answers.count - 1)] },
                activate: { activations += 1; return accepts },
                pause: { pauses += 1 },
                retries: retries
            )
        }
    }

    private func isFound(_ lookup: FocusedLookup<String>, _ value: String) -> Bool {
        if case .found(let found) = lookup { return found == value }
        return false
    }

    @Test func appExposingItsTreeIsNeverActivated() throws {
        let script = Script([.found("field")])
        #expect(isFound(try script.run(), "field"))
        #expect(script.activations == 0)
        #expect(script.reads == 1)
    }

    @Test func missingTreeIsActivatedThenFoundOnRetry() throws {
        let script = Script([.missing(.noValue), .missing(.noValue), .found("web area")])
        #expect(isFound(try script.run(), "web area"))
        #expect(script.activations == 1)
        #expect(script.reads == 3)
        #expect(script.pauses == 2)
    }

    @Test func appRefusingActivationIsNotPolled() throws {
        let script = Script([.missing(.attributeUnsupported)], accepts: false)
        guard case .missing(.attributeUnsupported) = try script.run() else {
            Issue.record("expected original failure")
            return
        }
        #expect(script.activations == 1)
        #expect(script.reads == 1)
        #expect(script.pauses == 0)
    }

    @Test func timeoutOrDisabledApiDoesNotActivate() throws {
        for error in [AXError.cannotComplete, .apiDisabled, .invalidUIElement] {
            let script = Script([.missing(error)])
            _ = try script.run()
            #expect(script.activations == 0)
        }
    }

    @Test func retriesAreBoundedWhenTreeNeverAppears() throws {
        let script = Script([.missing(.noValue)])
        guard case .missing(.noValue) = try script.run(retries: 3) else {
            Issue.record("expected missing")
            return
        }
        #expect(script.reads == 4)
        #expect(script.pauses == 3)
    }

    @Test func cancellationDuringPauseStopsPolling() {
        var reads = 0
        #expect(throws: CancellationError.self) {
            try AccessibilityTreeActivation.lookUp(
                read: { reads += 1; return FocusedLookup<String>.missing(.noValue) },
                activate: { true },
                pause: { throw CancellationError() }
            )
        }
        #expect(reads == 1)
    }
}

struct AccessibilityTreeAttributeTests {
    @Test func chromiumBrowsersAlsoGetEnhancedUserInterface() {
        #expect(AccessibilityTreeActivation.attributes(forBundleID: "com.google.Chrome") == ["AXManualAccessibility", "AXEnhancedUserInterface"])
        #expect(AccessibilityTreeActivation.attributes(forBundleID: "com.microsoft.edgemac").count == 2)
    }

    @Test func otherAppsOnlyGetManualAccessibility() {
        for bundleID in ["com.microsoft.VSCode", "com.tinyspeck.slackmacgap", "notion.id", "com.apple.Safari", "com.apple.TextEdit"] {
            #expect(AccessibilityTreeActivation.attributes(forBundleID: bundleID) == ["AXManualAccessibility"])
        }
        #expect(AccessibilityTreeActivation.attributes(forBundleID: nil) == ["AXManualAccessibility"])
    }
}
