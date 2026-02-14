// ABOUTME: Token usage extracted from Claude Code's session transcript.
// ABOUTME: Parses the last assistant entry in the JSONL to get current API token counts.

import Foundation

struct SessionStatus {
    let modelId: String
    let totalInputTokens: Int
    let outputTokens: Int
    let contextWindowSize: Int

    /// e.g. "claude-opus-4-6" → "Opus 4.6"
    var modelDisplayName: String {
        // Strip "claude-" prefix, then map known families
        let base = modelId
            .replacingOccurrences(of: "claude-", with: "")
            .components(separatedBy: "-")

        // base is e.g. ["opus", "4", "6"] or ["sonnet", "4", "5", "20250514"]
        guard let family = base.first else { return modelId }
        let version = base.dropFirst()
            .prefix(2)  // at most major.minor
            .filter { $0.count <= 2 }  // skip date suffixes like "20250514"
            .joined(separator: ".")

        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version)"
    }

    var remainingTokens: Int {
        max(contextWindowSize - totalInputTokens, 0)
    }

    var usedPercentage: Double {
        guard contextWindowSize > 0 else { return 0 }
        return Double(totalInputTokens) / Double(contextWindowSize) * 100
    }

    /// e.g. "146,000 / 200,000 (73%)"
    var formattedUsage: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.groupingSeparator = ","
        let used = fmt.string(from: totalInputTokens as NSNumber) ?? "\(totalInputTokens)"
        let total = fmt.string(from: contextWindowSize as NSNumber) ?? "\(contextWindowSize)"
        let pct = Int(usedPercentage)
        return "\(used) / \(total) (\(pct)%)"
    }

    /// e.g. 145_200 → "145k", 800 → "800"
    static func shortTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(count / 1000)k"
        }
        return "\(count)"
    }

    /// Parse the last assistant message from a JSONL transcript chunk.
    /// The chunk should be the tail of the file (last ~64KB is sufficient).
    static func fromTranscriptTail(_ data: Data) -> SessionStatus? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\n").reversed()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8) else { continue }

            guard let entry = try? JSONDecoder().decode(TranscriptEntry.self, from: lineData),
                  entry.type == "assistant",
                  let usage = entry.message?.usage,
                  let model = entry.message?.model else {
                continue
            }

            let totalInput = usage.inputTokens
                + usage.cacheCreationInputTokens
                + usage.cacheReadInputTokens

            return SessionStatus(
                modelId: model,
                totalInputTokens: totalInput,
                outputTokens: usage.outputTokens,
                contextWindowSize: contextWindowSize(for: model)
            )
        }
        return nil
    }

    /// Estimate system overhead tokens from the first assistant entry in a transcript.
    /// For continued sessions, cache_read holds the cached system prompt + tools.
    /// For fresh sessions, cache_read is 0 so we use the full total as an approximation.
    static func systemOverheadFromTranscriptHead(_ data: Data) -> Int? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8) else { continue }

            guard let entry = try? JSONDecoder().decode(TranscriptEntry.self, from: lineData),
                  entry.type == "assistant",
                  let usage = entry.message?.usage else {
                continue
            }

            if usage.cacheReadInputTokens > 0 {
                return usage.cacheReadInputTokens
            }

            // Fresh session — total is mostly system overhead
            return usage.inputTokens
                + usage.cacheCreationInputTokens
                + usage.cacheReadInputTokens
        }
        return nil
    }

    /// Context window size per model family. All current Claude models use 200K.
    private static func contextWindowSize(for model: String) -> Int {
        200_000
    }
}

// MARK: - JSONL Transcript Entry (partial decode)

struct TranscriptEntry: Decodable {
    let type: String
    let subtype: String?
    let timestamp: String?
    let message: TranscriptMessage?
}

struct TranscriptMessage: Decodable {
    let model: String?
    let usage: TranscriptUsage?
    let content: [TranscriptContent]?
}

struct TranscriptContent: Decodable {
    let type: String
    let name: String?
    let input: TranscriptToolInput?
}

struct TranscriptToolInput: Decodable {
    let filePath: String?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
    }
}

struct TranscriptUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}
