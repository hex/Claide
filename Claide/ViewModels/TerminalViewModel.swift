// ABOUTME: Tracks terminal process state (running, title, working directory).
// ABOUTME: Polls the process table to keep the foreground executable current.

import SwiftUI
import Foundation
import Darwin

@MainActor @Observable
final class TerminalViewModel {
    var title: String = "zsh"
    var isRunning: Bool = false
    var currentDirectory: String?
    var executablePath: String?

    private var shellPid: pid_t = 0
    private var shellExecutable: String?
    private var trackingTask: Task<Void, Never>?

    func processStarted(executable: String, args: [String]) {
        isRunning = true
        executablePath = executable
        shellExecutable = executable
        let name = (executable as NSString).lastPathComponent
        title = ([name] + args).joined(separator: " ")
    }

    func processTerminated(exitCode: Int32?) {
        isRunning = false
        stopTrackingForeground()
        title = "\(title) (exited: \(exitCode ?? -1))"
    }

    func titleChanged(_ newTitle: String) {
        title = newTitle
    }

    func directoryChanged(_ directory: String?) {
        // OSC 7 reports a file:// URL (e.g. "file://hostname/Users/hex/path").
        // Extract the filesystem path from the URL.
        guard let raw = directory else {
            currentDirectory = nil
            return
        }
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            currentDirectory = url.path
        } else {
            currentDirectory = raw
        }
    }

    // MARK: - Foreground Process Tracking

    /// Begin polling the shell's child processes to keep `executablePath` current.
    func startTrackingForeground(shellPid: pid_t) {
        self.shellPid = shellPid
        trackingTask?.cancel()
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.updateForeground()
            }
        }
    }

    func stopTrackingForeground() {
        trackingTask?.cancel()
        trackingTask = nil
    }

    private func updateForeground() {
        guard shellPid > 0 else { return }
        let childPath = Self.foregroundChildExecutable(of: shellPid)
        let newPath = childPath ?? shellExecutable
        if newPath != executablePath {
            executablePath = newPath
        }
    }

    // MARK: - Process Inspection (nonisolated for testability)

    /// Executable path of the most recently forked direct child, or nil if none.
    nonisolated static func foregroundChildExecutable(of parentPid: pid_t) -> String? {
        guard parentPid > 0 else { return nil }

        var pids = [pid_t](repeating: 0, count: 128)
        let byteSize = Int32(pids.count * MemoryLayout<pid_t>.size)
        // proc_listchildpids returns the number of PIDs placed in the buffer.
        let count = Int(proc_listchildpids(parentPid, &pids, byteSize))
        guard count > 0 else { return nil }

        // Pick the highest PID (most recently forked child).
        let childPid = pids.prefix(count).max() ?? pids[0]
        return executablePath(for: childPid)
    }

    /// Resolve a PID to its executable path via libproc.
    nonisolated static func executablePath(for pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return nil }
        return String(cString: buffer)
    }
}
