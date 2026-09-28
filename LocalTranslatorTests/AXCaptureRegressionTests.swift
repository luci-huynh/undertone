import ApplicationServices
import Foundation
import Testing
@testable import Undertone

struct AXCaptureRegressionTests {
    @Test func cancelledActiveReadStopsBeforeNextAttributeAndNewestRuns() async {
        let executor = AXReadExecutor()
        let gate = DispatchSemaphore(value: 0)
        let (started, signal) = AsyncStream<Void>.makeStream()
        let old = Task {
            await executor.read { cancellation in
                signal.yield(())
                gate.wait()
                try cancellation.check()
                Issue.record("Cancelled read must not query the next attribute")
                return FocusedElementReading(selectedText: .value("old"))
            }
        }
        for await _ in started { break }
        old.cancel()
        let newest = Task {
            await executor.read { _ in FocusedElementReading(selectedText: .value("new")) }
        }
        gate.signal()
        #expect(await old.value.failure == .cancelled)
        #expect(await newest.value.selectedText == .value("new"))
        signal.finish()
    }

    @Test func cancelledQueuedReadNeverInvokesOperation() async {
        let queue = DispatchQueue(label: "test.ax.cancelled")
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() }
        let executor = AXReadExecutor(queue: queue)
        let task = Task {
            await executor.read { _ in
                Issue.record("Cancelled queued work must not invoke AX")
                return FocusedElementReading()
            }
        }
        task.cancel()
        gate.signal()
        #expect(await task.value.failure == .cancelled)
    }

    private func sample(
        texts: [AXRead<String>] = [.value("hello"), .value("hello")],
        ranges: [AXRead<NSRange>] = [.value(NSRange(location: 1, length: 5)), .value(NSRange(location: 1, length: 5))],
        focused: AXRead<Bool> = .value(true),
        boundsRequests: BoundsLog? = nil
    ) throws -> FocusedElementReading {
        var textIndex = 0
        var rangeIndex = 0
        return try ConsistentSelectionReader.read(
            initial: FocusedElementReading(elementPID: 42),
            text: { defer { textIndex += 1 }; return texts[textIndex] },
            range: { defer { rangeIndex += 1 }; return ranges[rangeIndex] },
            bounds: { range in
                boundsRequests?.ranges.append(range)
                return CGRect(x: 10, y: 20, width: 30, height: 40)
            },
            stillFocused: { focused }
        )
    }

    @Test func stableSelectionKeepsTextRangeAndBounds() throws {
        let reading = try sample()
        #expect(reading.failure == nil)
        #expect(reading.selectedText == .value("hello"))
        #expect(reading.selectedRange == NSRange(location: 1, length: 5))
        #expect(reading.selectionBounds == CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    @Test func changedTextWithSameRangeIsRejected() throws {
        let reading = try sample(texts: [.value("hello"), .value("world")])
        #expect(reading.failure == .selectionChanged)
        #expect(reading.selectedText == nil)
        #expect(reading.selectionBounds == nil)
    }

    @Test func changedRangeWithIdenticalTextIsRejected() throws {
        let reading = try sample(ranges: [.value(NSRange(location: 1, length: 5)), .value(NSRange(location: 8, length: 5))])
        #expect(reading.failure == .selectionChanged)
    }

    @Test func changedElementInSameAppIsRejected() throws {
        #expect(try sample(focused: .value(false)).failure == .focusChanged)
        #expect(try sample(focused: .failed(.invalidUIElement)).failure == .focusChanged)
    }

    /// L08 review: a slow app is a timeout, not a silent focus change.
    @Test func timeoutsAreReportedAsTimeouts() throws {
        #expect(try sample(focused: .failed(.cannotComplete)).failure == .timedOut)
        #expect(try sample(texts: [.value("hello"), .failed(.cannotComplete)]).failure == .timedOut)
        #expect(try sample(ranges: [.value(NSRange(location: 1, length: 5)), .failed(.cannotComplete)]).failure == .timedOut)
    }

    @Test func boundsAreReadLastOnlyForAVerifiedSelectionAndCapped() throws {
        let log = BoundsLog()
        _ = try sample(texts: [.value("hello"), .value("world")], boundsRequests: log)
        #expect(log.ranges.isEmpty)
        let huge = NSRange(location: 3, length: 50_000)
        let reading = try sample(ranges: [.value(huge), .value(huge)], boundsRequests: log)
        #expect(reading.selectedRange == huge)
        #expect(log.ranges == [NSRange(location: 3, length: ConsistentSelectionReader.maxBoundsLength)])
    }

    @Test func consistentlyUnsupportedRangeStillAllowsCursorFallback() throws {
        let reading = try sample(ranges: [.failed(.attributeUnsupported), .failed(.attributeUnsupported)])
        #expect(reading.failure == nil)
        #expect(reading.selectedText == .value("hello"))
        #expect(reading.selectedRange == nil)
        #expect(reading.selectionBounds == nil)
    }

    @Test func lostRangeOrValidationFailureRejectsCapture() throws {
        #expect(try sample(ranges: [.value(NSRange(location: 1, length: 5)), .failed(.noValue)]).failure == .selectionChanged)
        #expect(try sample(texts: [.value("hello"), .failed(.noValue)]).failure == .selectionChanged)
        #expect(try sample(ranges: [.failed(.cannotComplete), .failed(.cannotComplete)]).failure == .timedOut)
    }
}

final class BoundsLog {
    var ranges: [NSRange] = []
}
