// ABOUTME: Runs the `bd` CLI tool and parses its JSON output into Issue models.
// ABOUTME: Handles missing binary and missing .beads/ directory gracefully.

import Foundation

enum BeadsError: Error, LocalizedError {
    case binaryNotFound
    case noDatabase
    case processError(String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            "bd binary not found. Install beads: https://github.com/hex/beads"
        case .noDatabase:
            "No .beads/ directory found in the working directory"
        case .processError(let msg):
            "bd error: \(msg)"
        case .decodingError(let err):
            "Failed to parse bd output: \(err.localizedDescription)"
        }
    }
}

struct BeadsService: Sendable {
    /// Paths to search for the bd binary
    private static let searchPaths = [
        "/opt/homebrew/bin/bd",
        "/usr/local/bin/bd",
        "/usr/bin/bd",
    ]

    /// Find the bd binary path
    static func findBinary() -> String? {
        searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Load issues from the bd CLI, optionally scoped to a working directory
    static func loadIssues(workingDirectory: String? = nil) async throws -> [Issue] {
        guard let bdPath = findBinary() else {
            throw BeadsError.binaryNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bdPath)
        process.arguments = ["list", "--json", "--limit", "0"]

        if let dir = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        // Build environment with homebrew in PATH
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin"
        if !path.contains("/opt/homebrew/bin") {
            env["PATH"] = "/opt/homebrew/bin:" + path
        }
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let errStr = String(data: errData, encoding: .utf8) ?? "unknown error"
            if errStr.contains("no beads database") {
                throw BeadsError.noDatabase
            }
            throw BeadsError.processError(errStr)
        }

        return try decode(outData)
    }

    /// Decode JSON data into Issue array
    static func decode(_ data: Data) throws -> [Issue] {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([Issue].self, from: data)
        } catch {
            throw BeadsError.decodingError(error)
        }
    }
}
