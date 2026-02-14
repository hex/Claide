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
    /// Tail read size — one assistant entry is typically a few KB
    private static let tailBytes = 65_536

    /// Start watching the transcript for the Claude Code session in the given directory.
    /// Scans for a Claude process affiliated with this Claide instance via CLAIDE_PID.
    /// Clears status when no affiliated Claude process is running.
    func startWatching(sessionDirectory: String) {
        let projectDir = Self.projectDirectory(for: sessionDirectory)

        guard let path = Self.findTranscriptForClaide(in: projectDir) else {
            // No affiliated Claude process — clear stale status and poll for one to appear
            status = nil
            stopWatching()
            watchedSessionDir = sessionDirectory
            startRetryPolling()
            watchDirectoryForNewFiles(projectDir)
            return
        }

        guard path != watchedPath else { return }
        stopWatching()
        watchedPath = path
        watchedSessionDir = sessionDirectory

        reload(from: path)

        let fileCallback: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                self?.reload(from: path)
            }
        }
        watcher = FileWatcher(path: path, onChange: fileCallback)
        watcher?.start()

        watchDirectoryForNewFiles(projectDir)
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

    /// Poll every 3 seconds for a Claude process affiliated with this Claide instance.
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
    /// Uses env-var-based detection to find the right transcript, or clears status
    /// when no affiliated Claude process is running.
    private func recheckTranscript() {
        guard let dir = watchedSessionDir else { return }
        let projectDir = Self.projectDirectory(for: dir)

        guard let newest = Self.findTranscriptForClaide(in: projectDir) else {
            // No affiliated Claude process — clear stale status
            status = nil
            return
        }

        guard newest != watchedPath else { return }
        startWatching(sessionDirectory: dir)
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

    /// Check whether a process's environment contains a specific KEY=VALUE pair.
    /// Uses sysctl KERN_PROCARGS2 to read the process's argument+environment buffer.
    nonisolated static func processHasEnvVar(pid: pid_t, key: String, value: String) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, Int32(pid)]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return false }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return false }

        // Buffer layout: argc (int32) | exec_path\0 | argv[0]\0 ... argv[argc-1]\0 | env[0]\0 ...
        guard size >= MemoryLayout<Int32>.size else { return false }
        let argc: Int32 = buffer.withUnsafeBufferPointer {
            $0.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        }

        // Split everything after the argc int on null bytes
        let bodyStart = MemoryLayout<Int32>.size
        let parts = buffer[bodyStart..<size].split(separator: 0, omittingEmptySubsequences: true)

        // Skip: exec_path + argc argv strings = 1 + argc entries
        let envStart = 1 + Int(argc)
        guard parts.count > envStart else { return false }

        let needle = "\(key)=\(value)"
        let needleBytes = Array(needle.utf8)
        for part in parts[envStart...] {
            if Array(part) == needleBytes { return true }
        }
        return false
    }

    /// Scan the process table for a "claude" process whose environment contains
    /// CLAIDE_PID matching this Claide instance. Returns the PID and start time.
    nonisolated static func findClaudeForClaide() -> (pid: pid_t, startTime: Date)? {
        let myPid = "\(getpid())"
        let procs = snapshotProcessTable()

        for proc in procs where proc.name == "claude" {
            if processHasEnvVar(pid: proc.pid, key: "CLAIDE_PID", value: myPid) {
                return (pid: proc.pid, startTime: proc.startTime)
            }
        }
        return nil
    }

    /// Find the transcript for the Claude process affiliated with this Claide instance.
    nonisolated static func findTranscriptForClaide(in projectDir: String) -> String? {
        guard let claude = findClaudeForClaide() else { return nil }
        return findTranscriptByStartTime(claude.startTime, in: projectDir)
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
