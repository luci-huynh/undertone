import Foundation
import ApplicationServices

/// AX has no atomic selection snapshot. Re-read the selection around the
/// bounds query and verify element identity before accepting the result.
nonisolated enum ConsistentSelectionReader {
    static func read(
        initial: FocusedElementReading,
        text: () throws -> AXRead<String>,
        range: () throws -> AXRead<NSRange>,
        bounds: (NSRange) throws -> CGRect?,
        stillFocused: () throws -> Bool
    ) throws -> FocusedElementReading {
        var reading = initial
        // Range brackets the first text read, catching a change between text
        // and range even when two different selections contain identical text.
        let rangeBefore = try range()
        let textBefore = try text()
        reading.selectedText = textBefore
        guard case .value = textBefore else { return reading }
        if case .value(let selectedRange) = rangeBefore {
            reading.selectedRange = selectedRange
            reading.selectionBounds = try bounds(selectedRange)
        }
        let textAfter = try text()
        let rangeAfter = try range()
        guard try stillFocused() else { return FocusedElementReading(failure: .focusChanged) }
        guard textBefore == textAfter, rangeBefore == rangeAfter else {
            return FocusedElementReading(failure: .selectionChanged)
        }
        // Unsupported ranges are legitimate (cursor fallback). A timeout or
        // other transient range failure cannot establish a consistent capture.
        if case .failed(let error) = rangeBefore {
            switch error {
            case .attributeUnsupported, .notImplemented, .noValue: break
            case .cannotComplete: return FocusedElementReading(failure: .timedOut)
            default: return FocusedElementReading(failure: .selectionChanged)
            }
        }
        return reading
    }
}
