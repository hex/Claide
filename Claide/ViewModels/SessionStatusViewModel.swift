// ABOUTME: Watches the Claude Code JSONL transcript and extracts context window usage.
// ABOUTME: Reads from the tail of the file for efficiency (files can be megabytes).

import Foundation
import Darwin

@MainActor @Observable
final class SessionStatusViewModel {
    var status: SessionStatus?

    private var watcher: FileWatcher?
    private var directoryWatcher: FileWatcher?
    private var pollTask: Task<Void, Never>?
    private var watchedPath: String?
    private var watchedProjectDir: String?
    private var watchedClaudePid: pid_t = 0
    /// Tail read size — one assistant entry is typically a few KB
    nonisolated(unsafe) private static let tailBytes = 65_536

    /// Start watching the transcript for the Claude Code session in the given directory.
    /// Scans for a Claude process affiliated with this Claide instance via CLAIDE_PID.
    func startWatching(sessionDirectory: String) {
        // Only start once — polling handles everything after initial call
        guard pollTask == nil else { return }
        poll()
        startPolling()
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
        directoryWatcher?.stop()
        directoryWatcher = nil
        pollTask?.cancel()
        pollTask = nil
        watchedPath = nil
        watchedProjectDir = nil
        watchedClaudePid = 0
    }

    // MARK: - Polling

    /// Poll every 3 seconds for transcript changes.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { return }
                self.poll()
            }
        }
    }

    /// Core poll: find the Claude process, locate its active transcript, and update status.
    /// Locks onto a transcript once found — only re-evaluates when the Claude process
    /// changes or when the locked transcript has no parseable data yet.
    private func poll() {
        guard let claudePid = Self.findClaudeForClaide() else {
            // No affiliated Claude process running
            if status != nil { status = nil }
            unwatchFiles()
            watchedClaudePid = 0
            return
        }

        let pidChanged = claudePid != watchedClaudePid
        watchedClaudePid = claudePid

        guard let projectDir = Self.projectDirectoryForClaide() else { return }

        // Re-evaluate transcript selection only when:
        // 1. Claude process changed (new session started)
        // 2. No transcript locked yet
        // 3. Locked transcript isn't producing data (e.g. stuck on a stub file)
        let needsSearch = pidChanged || watchedPath == nil || status == nil

        if needsSearch {
            let transcript = Self.findActiveTranscript(in: projectDir)

            if transcript != watchedPath {
                unwatchFiles()
                watchedPath = transcript
                watchedProjectDir = projectDir
                if let transcript {
                    watchFile(transcript)
                    watchDirectory(projectDir)
                }
            }
        }

        if let path = watchedPath {
            reload(from: path)
        } else if status != nil {
            status = nil
        }
    }

    // MARK: - File & Directory Watching

    private func watchFile(_ path: String) {
        let callback: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                self?.reload(from: path)
            }
        }
        watcher = FileWatcher(path: path, onChange: callback)
        watcher?.start()
    }

    private func watchDirectory(_ projectDir: String) {
        let callback: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        directoryWatcher = FileWatcher(path: projectDir, onChange: callback)
        directoryWatcher?.start()
    }

    private func unwatchFiles() {
        watcher?.stop()
        watcher = nil
        directoryWatcher?.stop()
        directoryWatcher = nil
    }

    // MARK: - Transcript Reading

    private func reload(from path: String) {
        guard let data = Self.readTail(path: path, bytes: Self.tailBytes) else { return }
        if let parsed = SessionStatus.fromTranscriptTail(data) {
            status = parsed
        }
    }

    /// Read the last N bytes of a file without loading the whole thing.
    nonisolated private static func readTail(path: String, bytes: Int) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let offset = fileSize > UInt64(bytes) ? fileSize - UInt64(bytes) : 0
        handle.seek(toFileOffset: offset)
        return handle.readDataToEndOfFile()
    }

    // MARK: - Transcript Discovery

    /// Find the most recently modified .jsonl in a project directory that contains
    /// parseable assistant data. Tries files newest-first and stops at the first hit.
    nonisolated static func findActiveTranscript(in projectDir: String) -> String? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: projectDir) else { return nil }

        let files = contents
            .filter { $0.hasSuffix(".jsonl") }
            .compactMap { name -> (path: String, modified: Date)? in
                let full = (projectDir as NSString).appendingPathComponent(name)
                guard let attrs = try? fm.attributesOfItem(atPath: full),
                      let modified = attrs[.modificationDate] as? Date else { return nil }
                return (full, modified)
            }
            .sorted { $0.modified > $1.modified }

        for file in files {
            guard let data = readTail(path: file.path, bytes: tailBytes) else { continue }
            if SessionStatus.fromTranscriptTail(data) != nil {
                return file.path
            }
        }
        return nil
    }

    /// Find the active transcript for the Claude process affiliated with this Claide instance.
    nonisolated static func findTranscriptForClaide() -> String? {
        guard let projectDir = projectDirectoryForClaide() else { return nil }
        return findActiveTranscript(in: projectDir)
    }

    /// Find the project directory for the Claude process affiliated with this Claide instance.
    nonisolated static func projectDirectoryForClaide() -> String? {
        guard let claude = findClaudeForClaide() else { return nil }
        guard let cwd = processWorkingDirectory(pid: claude) else { return nil }
        return projectDirectory(for: cwd)
    }

    // MARK: - Process Discovery

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

    /// Extract the basename of argv[0] for a process via KERN_PROCARGS2.
    /// Unlike kp_proc.p_comm, argv[0] preserves the original invocation name
    /// even when the executable is reached via symlink.
    nonisolated static func processArgv0Basename(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, Int32(pid)]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        guard size >= MemoryLayout<Int32>.size else { return nil }
        let argc: Int32 = buffer.withUnsafeBufferPointer {
            $0.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        }
        guard argc > 0 else { return nil }

        let bodyStart = MemoryLayout<Int32>.size
        let parts = buffer[bodyStart..<size].split(separator: 0, omittingEmptySubsequences: true)
        // parts layout: exec_path, argv[0], argv[1], ..., env vars
        guard parts.count >= 2 else { return nil }

        guard let argv0 = String(bytes: parts[1], encoding: .utf8) else { return nil }
        return (argv0 as NSString).lastPathComponent
    }

    /// Scan the process table for a Claude Code process whose environment contains
    /// CLAIDE_PID matching this Claide instance. Returns the PID.
    /// Uses argv[0] instead of kp_proc.p_comm because the claude binary is a symlink
    /// (e.g., claude -> versions/2.1.42) and p_comm reflects the resolved target name.
    nonisolated static func findClaudeForClaide() -> pid_t? {
        let myPid = getpid()
        let myPidStr = "\(myPid)"
        let procs = snapshotProcessTable()

        // BFS from our PID to find all descendant processes
        var childrenOf: [pid_t: [ProcessEntry]] = [:]
        for proc in procs {
            childrenOf[proc.ppid, default: []].append(proc)
        }

        var queue: [pid_t] = [myPid]
        var visited: Set<pid_t> = [myPid]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            for child in childrenOf[current] ?? [] {
                guard !visited.contains(child.pid) else { continue }
                visited.insert(child.pid)
                queue.append(child.pid)

                guard processArgv0Basename(pid: child.pid) == "claude" else { continue }
                if processHasEnvVar(pid: child.pid, key: "CLAIDE_PID", value: myPidStr) {
                    return child.pid
                }
            }
        }

        return nil
    }

    /// Get a process's current working directory via proc_pidinfo.
    nonisolated static func processWorkingDirectory(pid: pid_t) -> String? {
        var vpi = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, size)
        guard ret == size else { return nil }

        return withUnsafePointer(to: &vpi.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
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

            return ProcessEntry(pid: pid, ppid: ppid, name: processName)
        }
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
}
