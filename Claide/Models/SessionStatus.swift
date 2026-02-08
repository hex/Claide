// ABOUTME: Context window usage extracted from Claude Code's session transcript.
// ABOUTME: Parses the last assistant entry in the JSONL to get current token counts.

import Foundation

struct SessionStatus {
    let totalInputTokens: Int
    let outputTokens: Int
    let contextWindowSize: Int

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
                totalInputTokens: totalInput,
                outputTokens: usage.outputTokens,
                contextWindowSize: contextWindowSize(for: model)
            )
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
