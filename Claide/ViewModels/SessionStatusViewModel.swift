// ABOUTME: Watches the Claude Code JSONL transcript and extracts context window usage.
// ABOUTME: Reads from the tail of the file for efficiency (files can be megabytes).

import Foundation
import Darwin

@MainActor @Observable
final class SessionStatusViewModel {
    var status: SessionStatus?

    private var watcher: FileWatcher?
    private var directoryWatcher: FileWatcher?
    private var retryTask: Task<Void, Never>?
    private var watchedPath: String?
    private var watchedSessionDir: String?
    private var storedShellPid: pid_t = 0

    /// Tail read size — one assistant entry is typically a few KB
    private static let tailBytes = 65_536

    /// Start watching the transcript for the Claude Code session in the given directory.
    /// When shellPid is provided, uses process tree walking to identify the correct
    /// transcript even when multiple sessions share the same project directory.
    /// Polls periodically until a Claude descendant appears under the shell.
    func startWatching(sessionDirectory: String, shellPid: pid_t = 0) {
        let projectDir = Self.projectDirectory(for: sessionDirectory)

        // Try process-based lookup first (reliable with concurrent sessions)
        let path: String
        var foundViaProcess = false
        if shellPid > 0,
           let processPath = Self.findTranscriptByProcess(shellPid: shellPid, projectDir: projectDir) {
            path = processPath
            foundViaProcess = true
        } else if let newestPath = Self.findNewestJsonl(in: projectDir) {
            // Process lookup failed (or no shellPid) — use most recently modified transcript
            path = newestPath
        } else {
            // No transcripts found — poll until one appears
            if shellPid > 0 {
                stopWatching()
                watchedSessionDir = sessionDirectory
                storedShellPid = shellPid
                startRetryPolling()
                watchDirectoryForNewFiles(projectDir)
            }
            return
        }

        guard path != watchedPath else {
            if foundViaProcess { stopRetryPolling() }
            return
        }
        stopWatching()
        watchedPath = path
        watchedSessionDir = sessionDirectory
        storedShellPid = shellPid

        reload(from: path)

        let fileCallback: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                self?.reload(from: path)
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
        watcher?.stop()
        watcher = nil
        directoryWatcher?.stop()
        directoryWatcher = nil
        stopRetryPolling()
        watchedPath = nil
        watchedSessionDir = nil
    }

    // MARK: - Retry Polling

    /// Poll every 3 seconds for a Claude descendant of the shell process.
    /// Covers the case where Claude starts after Claide or resumes a transcript
    /// (no directory event for existing file modifications).
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

    // MARK: - Directory & Transcript Watching

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

    /// Called by the directory watcher and retry timer.
    /// When a shell PID is known, only switches to a process-matched transcript.
    private func recheckTranscript() {
        guard let dir = watchedSessionDir else { return }
        let projectDir = Self.projectDirectory(for: dir)

        let newest: String?
        if storedShellPid > 0,
           let processPath = Self.findTranscriptByProcess(shellPid: storedShellPid, projectDir: projectDir) {
            newest = processPath
            stopRetryPolling()
        } else {
            newest = Self.findNewestJsonl(in: projectDir)
            if newest == nil { return }
        }

        guard let newest, newest != watchedPath else { return }
        startWatching(sessionDirectory: dir, shellPid: storedShellPid)
    }

    private func reload(from path: String) {
        guard let data = Self.readTail(path: path, bytes: Self.tailBytes) else { return }
        if let parsed = SessionStatus.fromTranscriptTail(data) {
            status = parsed
        }
    }

    /// Read the last N bytes of a file without loading the whole thing.
    private static func readTail(path: String, bytes: Int) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let offset = fileSize > UInt64(bytes) ? fileSize - UInt64(bytes) : 0
        handle.seek(toFileOffset: offset)
        return handle.readDataToEndOfFile()
    }

    // MARK: - Process-Based Transcript Discovery

    /// Find the JSONL transcript for a Claude Code session running under a specific shell.
    /// Walks the process tree to find a "claude" descendant, then matches its start time
    /// to the JSONL file that was created at that moment.
    nonisolated static func findTranscriptByProcess(shellPid: pid_t, projectDir: String) -> String? {
        guard let claude = findClaudeDescendant(of: shellPid) else { return nil }
        return findTranscriptByStartTime(claude.startTime, in: projectDir)
    }

    /// BFS the process tree from a shell PID to find a "claude" descendant.
    /// Returns the PID and start time of the first match.
    nonisolated private static func findClaudeDescendant(of shellPid: pid_t) -> (pid: pid_t, startTime: Date)? {
        let procs = snapshotProcessTable()

        // Build parent→children map
        var children: [pid_t: [pid_t]] = [:]
        for p in procs {
            children[p.ppid, default: []].append(p.pid)
        }

        // BFS from shellPid, look for a process named "claude"
        var queue = children[shellPid] ?? []
        while !queue.isEmpty {
            let pid = queue.removeFirst()
            if let info = procs.first(where: { $0.pid == pid }), info.name == "claude" {
                return (pid: pid, startTime: info.startTime)
            }
            queue.append(contentsOf: children[pid] ?? [])
        }
        return nil
    }

    /// Snapshot the kernel process table via sysctl.
    nonisolated private static func snapshotProcessTable() -> [ProcessEntry] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: size_t = 0
        sysctl(&name, UInt32(name.count), nil, &size, nil, 0)

        let count = size / MemoryLayout<kinfo_proc>.size
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        sysctl(&name, UInt32(name.count), &procs, &size, nil, 0)
        let actualCount = size / MemoryLayout<kinfo_proc>.size

        return (0..<actualCount).map { i in
            let info = procs[i]
            let pid = info.kp_proc.p_pid
            let ppid = info.kp_eproc.e_ppid

            // Extract process name from the fixed-size C char array
            var comm = info.kp_proc.p_comm
            let processName = withUnsafePointer(to: &comm) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }

            let tv = info.kp_proc.p_starttime
            let startTime = Date(
                timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000
            )

            return ProcessEntry(pid: pid, ppid: ppid, name: processName, startTime: startTime)
        }
    }

    /// Find the JSONL file whose creation time is closest to a process start time.
    /// Handles both new sessions (file created shortly after process start) and
    /// resumed sessions (file modified after process start but created earlier).
    nonisolated private static func findTranscriptByStartTime(_ startTime: Date, in projectDir: String) -> String? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: projectDir) else { return nil }

        let files = contents
            .filter { $0.hasSuffix(".jsonl") }
            .compactMap { name -> (path: String, created: Date, modified: Date)? in
                let full = (projectDir as NSString).appendingPathComponent(name)
                guard let attrs = try? fm.attributesOfItem(atPath: full),
                      let created = attrs[.creationDate] as? Date,
                      let modified = attrs[.modificationDate] as? Date else { return nil }
                return (full, created, modified)
            }

        // New session: file created within 60s after process started
        let window: TimeInterval = 60
        if let match = files
            .filter({ $0.created >= startTime && $0.created.timeIntervalSince(startTime) <= window })
            .min(by: { $0.created.timeIntervalSince(startTime) < $1.created.timeIntervalSince(startTime) }) {
            return match.path
        }

        // Resumed session: file modified after process started (but created earlier)
        if let match = files
            .filter({ $0.modified >= startTime })
            .max(by: { $0.modified < $1.modified }) {
            return match.path
        }

        return nil
    }

    // MARK: - Path Helpers

    /// Compute the Claude Code project directory for a session working directory.
    nonisolated static func projectDirectory(for sessionDirectory: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let encoded = sessionDirectory
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return (home as NSString)
            .appendingPathComponent(".claude/projects/\(encoded)")
    }

    /// Find the most recently created .jsonl transcript for a session.
    nonisolated static func findTranscript(sessionDirectory: String) -> String? {
        findNewestJsonl(in: projectDirectory(for: sessionDirectory))
    }

    /// Find the most recently modified .jsonl in a project directory.
    nonisolated static func findNewestJsonl(in projectDir: String) -> String? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: projectDir) else { return nil }

        return contents
            .filter { $0.hasSuffix(".jsonl") }
            .compactMap { name -> (String, Date)? in
                let full = (projectDir as NSString).appendingPathComponent(name)
                guard let attrs = try? fm.attributesOfItem(atPath: full),
                      let modified = attrs[.modificationDate] as? Date else { return nil }
                return (full, modified)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }
}

// MARK: - Process Table Entry

private struct ProcessEntry {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let startTime: Date
}
