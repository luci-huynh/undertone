import Foundation

/// Wire types for the subset of the Ollama HTTP API this app uses.
nonisolated enum Ollama {
    struct VersionResponse: Decodable, Sendable {
        let version: String
    }

    struct TagsResponse: Decodable, Sendable {
        let models: [ModelEntry]
    }

    struct ModelEntry: Decodable, Equatable, Sendable {
        let name: String
        let digest: String?
        let size: Int64?
        /// Present for models that run on Ollama's servers.
        let remoteHost: String?

        enum CodingKeys: String, CodingKey {
            case name, digest, size
            case remoteHost = "remote_host"
        }

        init(name: String, digest: String? = nil, size: Int64? = nil, remoteHost: String? = nil) {
            self.name = name
            self.digest = digest
            self.size = size
            self.remoteHost = remoteHost
        }

        /// Runs on this Mac: not a cloud tag and no remote host.
        var isLocal: Bool { remoteHost == nil && !ModelTag.isCloud(name) }
    }

    struct ChatMessage: Codable, Equatable, Sendable {
        let role: String
        let content: String
    }

    struct ChatRequest: Encodable, Sendable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        /// How long Ollama keeps the model loaded after this request (e.g. "30m");
        /// nil keeps Ollama's default (5 minutes).
        var keepAlive: String?
        var options: ChatOptions?

        enum CodingKeys: String, CodingKey {
            case model, messages, stream, options
            case keepAlive = "keep_alive"
        }
    }

    struct ChatOptions: Encodable, Equatable, Sendable {
        /// Context window in tokens (prompt + output). A different value than
        /// the loaded one makes Ollama reload the model.
        var numCtx: Int?

        enum CodingKeys: String, CodingKey {
            case numCtx = "num_ctx"
        }
    }

    struct ChatResponse: Decodable, Sendable {
        let model: String?
        let message: ChatMessage?
        let done: Bool?
        let doneReason: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case model, message, done, error
            case doneReason = "done_reason"
        }
    }

    struct ErrorResponse: Decodable, Sendable {
        let error: String
    }
}

nonisolated enum ModelTag {
    /// `name:cloud`, `name:20b-cloud` and similar run remotely (docs/OLLAMA.md).
    static func isCloud(_ tag: String) -> Bool {
        let lowered = tag.lowercased()
        guard let variant = lowered.split(separator: ":", maxSplits: 1).dropFirst().first else { return false }
        return variant == "cloud" || variant.hasSuffix("-cloud")
    }

    /// Ollama resolves a tag without a variant to `:latest`.
    static func normalized(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains(":") ? trimmed : trimmed + ":latest"
    }
}
