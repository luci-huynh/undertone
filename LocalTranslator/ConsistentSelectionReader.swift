import Foundation
import ApplicationServices

/// AX has no atomic selection snapshot. Re-read the selection and verify
/// element identity before accepting the result. A timeout anywhere is
/// reported as a timeout (“The app didn't respond”), never as a focus or
/// selection change (L08 review). Bounds are read last, only for a verified
/// selection, and are optional: the popup falls back to the pointer.
nonisolated enum ConsistentSelectionReader {
    /// Longest range sent to AXBoundsForRange; huge ranges (select-all in a
    /// long document) can keep the source app busy past the timeout.
    static let maxBoundsLength = 2_000

    static func read(
        initial: FocusedElementReading,
        text: () throws -> AXRead<String>,
        range: () throws -> AXRead<NSRange>,
        bounds: (NSRange) throws -> CGRect?,
        stillFocused: () throws -> AXRead<Bool>
    ) throws -> FocusedElementReading {
        var reading = initial
        // Range brackets the first text read, catching a change between text
        // and range even when two different selections contain identical text.
        let rangeBefore = try range()
        let textBefore = try text()
        reading.selectedText = textBefore
        guard case .value = textBefore else { return reading }
        let textAfter = try text()
        let rangeAfter = try range()
        switch try stillFocused() {
        case .value(true): break
        case .failed(.cannotComplete): return FocusedElementReading(failure: .timedOut)
        case .value(false), .failed: return FocusedElementReading(failure: .focusChanged)
        }
        // A re-read that timed out says nothing about the selection.
        if case .failed(.cannotComplete) = textAfter { return FocusedElementReading(failure: .timedOut) }
        if case .value = rangeBefore, case .failed(.cannotComplete) = rangeAfter { return FocusedElementReading(failure: .timedOut) }
        guard textBefore == textAfter, rangeBefore == rangeAfter else {
            return FocusedElementReading(failure: .selectionChanged)
        }
        // Unsupported ranges are legitimate (cursor fallback). A timeout or
        // other transient range failure cannot establish a consistent capture.
        switch rangeBefore {
        case .failed(let error):
            switch error {
            case .attributeUnsupported, .notImplemented, .noValue: break
            case .cannotComplete: return FocusedElementReading(failure: .timedOut)
            default: return FocusedElementReading(failure: .selectionChanged)
            }
        case .value(let selectedRange):
            reading.selectedRange = selectedRange
            let measured = NSRange(location: selectedRange.location, length: min(selectedRange.length, maxBoundsLength))
            reading.selectionBounds = try bounds(measured)
        }
        return reading
    }
}
