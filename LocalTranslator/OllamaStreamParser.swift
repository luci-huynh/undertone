import Foundation

/// Splits a byte stream into newline-terminated lines. Network chunks can end
/// anywhere, including inside a JSON object or a multi-byte UTF-8 character;
/// splitting on the byte 0x0A is safe because it never occurs inside a UTF-8
/// multi-byte sequence, so each complete line is decoded only once whole.
nonisolated struct NDJSONLineSplitter {
    private var buffer = Data()

    mutating func append(_ bytes: Data) -> [Data] {
        buffer.append(bytes)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(Self.trimCR(buffer[buffer.startIndex..<newline]))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }

    /// The unterminated tail at end of stream, if any.
    mutating func finish() -> Data? {
        defer { buffer.removeAll() }
        let tail = Self.trimCR(buffer)
        return tail.isEmpty ? nil : tail
    }

    private static func trimCR(_ line: Data) -> Data {
        line.last == 0x0D ? Data(line.dropLast()) : Data(line)
    }
}

nonisolated enum OllamaStreamEvent: Equatable, Sendable {
    /// New output text (`message.content`); never thinking or tool payloads.
    case delta(String)
    case done(reason: String?)
}

/// Parses Ollama's streaming `/api/chat` response (NDJSON: one JSON object
/// per line; the last has `"done": true`).
nonisolated struct OllamaChatStreamParser {
    private struct Frame: Decodable {
        struct Message: Decodable {
            let content: String?
            // `thinking` and `tool_calls` exist in the API but are not output; not decoded.
        }

        let message: Message?
        let done: Bool?
        let doneReason: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case message, done, error
            case doneReason = "done_reason"
        }
    }

    private var splitter = NDJSONLineSplitter()
    private(set) var isComplete = false

    mutating func consume(_ bytes: Data) throws -> [OllamaStreamEvent] {
        var events: [OllamaStreamEvent] = []
        for line in splitter.append(bytes) {
            events += try parse(line)
        }
        return events
    }

    /// Call at end of stream. A stream that ends before its `done` frame is
    /// an error, never a success.
    mutating func finish() throws -> [OllamaStreamEvent] {
        let events = try splitter.finish().map { try parse($0) } ?? []
        guard isComplete else { throw OllamaError.incompleteStream }
        return events
    }

    private mutating func parse(_ line: Data) throws -> [OllamaStreamEvent] {
        guard !isComplete else { return [] } // Nothing after completion is output.
        guard line.contains(where: { !Self.isWhitespace($0) }) else { return [] }
        let frame: Frame
        do {
            frame = try JSONDecoder().decode(Frame.self, from: line)
        } catch {
            throw OllamaError.malformedStream
        }
        if let error = frame.error { throw OllamaError.http(status: 200, message: error) }
        var events: [OllamaStreamEvent] = []
        if let content = frame.message?.content, !content.isEmpty {
            events.append(.delta(content))
        }
        if frame.done == true {
            isComplete = true
            events.append(.done(reason: frame.doneReason))
        }
        return events
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
    }
}
