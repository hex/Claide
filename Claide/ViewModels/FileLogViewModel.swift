// ABOUTME: Watches the JSONL transcript and git working tree for file operations.
// ABOUTME: Merges Claude tool calls and git status into a unified file change list.

import Foundation

@MainActor @Observable
final class FileLogViewModel {
    var changes: [FileChange] = []
    var error: String?

    private var watcher: FileWatcher?
    private var directoryWatcher: FileWatcher?
    private var gitWatcher: FileWatcher?
    private var retryTask: Task<Void, Never>?
    private var watchedPath: String?
    private var watchedSessionDir: String?
    private var storedShellPid: pid_t = 0

    private var transcriptChanges: [FileChange] = []
    private var gitChanges: [FileChange] = []

    /// Start watching the transcript and working directory for file operations.
    /// Uses the same process-based discovery as SessionStatusViewModel.
    func startWatching(sessionDirectory: String, shellPid: pid_t = 0) {
        let projectDir = SessionStatusViewModel.projectDirectory(for: sessionDirectory)

        // Start git watching for the working directory regardless of transcript
        startGitWatching(directory: sessionDirectory)

        let path: String
        var foundViaProcess = false
        if shellPid > 0,
           let processPath = SessionStatusViewModel.findTranscriptByProcess(
               shellPid: shellPid, projectDir: projectDir
           ) {
            path = processPath
            foundViaProcess = true
        } else if shellPid > 0 {
            // Shell exists but no Claude session yet — poll until one appears
            stopTranscriptWatching()
            watchedSessionDir = sessionDirectory
            storedShellPid = shellPid
            startRetryPolling()
            watchDirectoryForNewFiles(projectDir)
            return
        } else {
            return
        }

        guard path != watchedPath else {
            if foundViaProcess { stopRetryPolling() }
            return
        }
        stopTranscriptWatching()
        watchedPath = path
        watchedSessionDir = sessionDirectory
        storedShellPid = shellPid

        reloadTranscript(from: path)

        let fileCallback: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadTranscript(from: path)
            }
        }
        watcher = FileWatcher(path: path, onChange: fileCallback)
        watcher?.start()

        watchDirectoryForNewFiles(projectDir)

        if foundViaProcess {
            stopRetryPolling()
        } else if shellPid > 0 {
            startRetryPolling()
        }
    }

    func stopWatching() {
        stopTranscriptWatching()
        gitWatcher?.stop()
        gitWatcher = nil
        gitChanges = []
        mergeChanges()
    }

    private func stopTranscriptWatching() {
        watcher?.stop()
        watcher = nil
        directoryWatcher?.stop()
        directoryWatcher = nil
        stopRetryPolling()
        watchedPath = nil
        watchedSessionDir = nil
    }

    // MARK: - Retry Polling

    private func startRetryPolling() {
        stopRetryPolling()
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { return }
                self.recheckTranscript()
            }
        }
    }

    private func stopRetryPolling() {
        retryTask?.cancel()
        retryTask = nil
    }

    // MARK: - Directory Watching (for transcript discovery)

    private func watchDirectoryForNewFiles(_ projectDir: String) {
        directoryWatcher?.stop()
        let dirCallback: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                self?.recheckTranscript()
            }
        }
        directoryWatcher = FileWatcher(path: projectDir, onChange: dirCallback)
        directoryWatcher?.start()
    }

    private func recheckTranscript() {
        guard let dir = watchedSessionDir else { return }
        let projectDir = SessionStatusViewModel.projectDirectory(for: dir)

        if storedShellPid > 0 {
            if let processPath = SessionStatusViewModel.findTranscriptByProcess(
                shellPid: storedShellPid, projectDir: projectDir
            ) {
                guard processPath != watchedPath else {
                    stopRetryPolling()
                    return
                }
                startWatching(sessionDirectory: dir, shellPid: storedShellPid)
            }
        }
    }

    // MARK: - Git Watching

    private func startGitWatching(directory: String) {
        gitWatcher?.stop()

        // Find the git repo root for this directory
        let repoRoot = Self.gitRepoRoot(for: directory)
        guard let repoRoot else { return }

        reloadGit(repoRoot: repoRoot)

        let callback: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadGit(repoRoot: repoRoot)
            }
        }
        gitWatcher = FileWatcher(path: repoRoot, onChange: callback)
        gitWatcher?.start()
    }

    /// Find the git repo root for a directory. Runs synchronously (fast for local repos).
    nonisolated private static func gitRepoRoot(for directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "rev-parse", "--show-toplevel"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run git status and parse the output. Called from a background task.
    nonisolated private static func fetchGitChanges(repoRoot: String) -> [FileChange] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoRoot, "status", "--porcelain"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return FileChange.parseGitStatus(output, repoRoot: repoRoot)
    }

    private func reloadGit(repoRoot: String) {
        Task { [weak self] in
            let changes = await Task.detached {
                Self.fetchGitChanges(repoRoot: repoRoot)
            }.value
            self?.gitChanges = changes
            self?.mergeChanges()
        }
    }

    // MARK: - Transcript Reload

    private func reloadTranscript(from path: String) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            transcriptChanges = FileChange.parseTranscript(data)
            error = nil
        } catch {
            self.error = "Failed to read \(path): \(error.localizedDescription)"
        }
        mergeChanges()
    }

    // MARK: - Merge

    /// Combine transcript and git changes, deduplicating by file path.
    /// Transcript entries take priority (they have specific tool info).
    private func mergeChanges() {
        let transcriptPaths = Set(transcriptChanges.map(\.filePath))
        let uniqueGit = gitChanges.filter { !transcriptPaths.contains($0.filePath) }
        let merged = transcriptChanges + uniqueGit
        changes = merged.sorted { $0.timestamp > $1.timestamp }
    }
}
