import ApplicationServices
import Foundation
import Testing
@testable import LocalTranslator

@MainActor
struct SelectionClassifierTests {
    private let source = SourceApp(pid: 42, name: "TextEdit")
    private let now = Date(timeIntervalSince1970: 1_000)

    private func classify(_ reading: FocusedElementReading, after: pid_t? = 42) -> Result<SelectionSnapshot, SelectionFailure> {
        SelectionClassifier.classify(source: source, reading: reading, frontmostAfterRead: after, anchor: nil, capturedAt: now)
    }

    private func reading(_ text: AXRead<String>?, range: NSRange? = nil) -> FocusedElementReading {
        FocusedElementReading(elementPID: 42, selectedText: text, selectedRange: range)
    }

    @Test func keepsExactSelectionWithUnicodeAndNewlines() {
        let text = "  Thanh toán này đã được xử lý.\nSecond line 👋  "
        let result = classify(reading(.value(text), range: NSRange(location: 5, length: text.utf16.count)))
        let snapshot = SelectionSnapshot(
            sourcePID: 42, sourceAppName: "TextEdit", text: text,
            range: NSRange(location: 5, length: text.utf16.count), anchor: nil, capturedAt: now
        )
        #expect(result == .success(snapshot))
    }

    @Test func emptyOrWhitespaceSelectionIsNoSelection() {
        #expect(classify(reading(.value(""))) == .failure(.noSelection))
        #expect(classify(reading(.value(" \n\t"))) == .failure(.noSelection))
        #expect(classify(reading(.failed(.noValue))) == .failure(.noSelection))
        #expect(SelectionFailure.noSelection.label == "No text selected.")
    }

    @Test func secureFieldIsReportedWithoutText() {
        var secure = reading(nil)
        secure.isSecureTextField = true
        #expect(classify(secure) == .failure(.secureInput))
    }

    @Test func unsupportedAndTimeoutAreDistinct() {
        #expect(classify(reading(.failed(.attributeUnsupported))) == .failure(.unsupported))
        #expect(classify(reading(.failed(.notImplemented))) == .failure(.unsupported))
        #expect(classify(reading(.failed(.cannotComplete))) == .failure(.timedOut))
        #expect(classify(reading(.failed(.failure))) == .failure(.axError(AXError.failure.rawValue)))
    }

    @Test func focusedElementErrorsAreClassified() {
        #expect(classify(FocusedElementReading(focusedElementError: .noValue)) == .failure(.noFocusedElement))
        #expect(classify(FocusedElementReading(focusedElementError: .cannotComplete)) == .failure(.timedOut))
        #expect(classify(FocusedElementReading(focusedElementError: .apiDisabled)) == .failure(.permissionMissing))
        #expect(classify(FocusedElementReading()) == .failure(.noFocusedElement))
    }

    @Test func focusChangeDuringReadRejectsSnapshot() {
        #expect(classify(reading(.value("hello")), after: 99) == .failure(.focusChanged))
        #expect(classify(reading(.value("hello")), after: nil) == .failure(.focusChanged))
        var otherElement = reading(.value("hello"))
        otherElement.elementPID = 7
        #expect(classify(otherElement) == .failure(.focusChanged))
    }
}

@MainActor
struct SelectedTextServiceTests {
    private let textEdit = SourceApp(pid: 42, name: "TextEdit")

    private func service(
        trusted: Bool = true,
        environment: FakeSelectionEnvironment,
        query: FakeFocusedElementQuery
    ) -> SelectedTextService {
        SelectedTextService(trust: FakeTrust(trusted: trusted), environment: environment, query: query)
    }

    @Test func readsFrontmostAppSelection() async {
        let environment = FakeSelectionEnvironment(frontmost: [textEdit])
        let query = FakeFocusedElementQuery(reading: FocusedElementReading(elementPID: 42, selectedText: .value("Hello")))
        let result = await service(environment: environment, query: query).capture()
        guard case .success(let snapshot) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(snapshot.text == "Hello")
        #expect(snapshot.sourcePID == 42)
        #expect(query.readPIDs == [42])
    }

    @Test func snapshotUsesSelectionBoundsWhenReported() async {
        let environment = FakeSelectionEnvironment(frontmost: [textEdit])
        let query = FakeFocusedElementQuery(reading: FocusedElementReading(
            elementPID: 42, selectedText: .value("Hello"), selectionBounds: CGRect(x: 200, y: 100, width: 80, height: 20)
        ))
        let result = await service(environment: environment, query: query).capture()
        // AX y 100…120 from the top of a 900 pt primary screen → AppKit y 780.
        #expect((try? result.get())?.anchor == SelectionAnchor(
            source: .selectionBounds, rect: CGRect(x: 200, y: 780, width: 80, height: 20),
            screenIndex: 0, visibleFrame: environment.layout.screens[0].visibleFrame
        ))
    }

    @Test func missingBoundsFallBackToTriggerTimeCursor() async {
        let environment = FakeSelectionEnvironment(frontmost: [textEdit])
        environment.mouse = CGPoint(x: 300, y: 400)
        let query = FakeFocusedElementQuery(reading: FocusedElementReading(elementPID: 42, selectedText: .value("Hello")))
        let result = await service(environment: environment, query: query).capture()
        let anchor = (try? result.get())?.anchor
        #expect(anchor?.source == .mouse)
        #expect(anchor?.rect == CGRect(x: 300, y: 400, width: 0, height: 0))
    }

    @Test func missingPermissionNeverQueriesAX() async {
        let query = FakeFocusedElementQuery(reading: FocusedElementReading(selectedText: .value("x")))
        let result = await service(trusted: false, environment: FakeSelectionEnvironment(frontmost: [textEdit]), query: query).capture()
        #expect(result == .failure(.permissionMissing))
        #expect(query.readPIDs.isEmpty)
    }

    @Test func secureInputNeverQueriesAX() async {
        let environment = FakeSelectionEnvironment(frontmost: [textEdit])
        environment.secureInput = true
        let query = FakeFocusedElementQuery(reading: FocusedElementReading(selectedText: .value("secret")))
        let result = await service(environment: environment, query: query).capture()
        #expect(result == .failure(.secureInput))
        #expect(query.readPIDs.isEmpty)
    }

    @Test func ownAppAndMissingFrontmostAreRejected() async {
        let query = FakeFocusedElementQuery(reading: FocusedElementReading(selectedText: .value("x")))
        let own = await service(environment: FakeSelectionEnvironment(frontmost: [SourceApp(pid: 1, name: "Local Translator")]), query: query).capture()
        #expect(own == .failure(.sourceIsSelf))
        let none = await service(environment: FakeSelectionEnvironment(frontmost: [nil]), query: query).capture()
        #expect(none == .failure(.noFrontmostApp))
        #expect(query.readPIDs.isEmpty)
    }

    @Test func appSwitchDuringReadIsRejected() async {
        let environment = FakeSelectionEnvironment(frontmost: [textEdit, SourceApp(pid: 77, name: "Safari")])
        let query = FakeFocusedElementQuery(reading: FocusedElementReading(elementPID: 42, selectedText: .value("Hello")))
        let result = await service(environment: environment, query: query).capture()
        #expect(result == .failure(.focusChanged))
    }
}
