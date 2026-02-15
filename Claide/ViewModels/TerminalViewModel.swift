// ABOUTME: Tracks terminal process state (running, title, working directory).
// ABOUTME: Polls the process table to keep the foreground executable current.

import SwiftUI
import Foundation
import Darwin

enum TabColor: String, CaseIterable {
    case base, red, orange, yellow, green, cyan, blue, purple, pink

    // Tokyo Night palette
    var color: Color {
        switch self {
        case .base:   Color(nsColor: TerminalTheme.background)
        case .red:    Color(red: 0.97, green: 0.31, blue: 0.35) // #f7544a
        case .orange: Color(red: 1.00, green: 0.63, blue: 0.35) // #ffa159
        case .yellow: Color(red: 0.88, green: 0.77, blue: 0.40) // #e0c566
        case .green:  Color(red: 0.45, green: 0.82, blue: 0.52) // #73d185
        case .cyan:   Color(red: 0.49, green: 0.84, blue: 0.87) // #7dd6de
        case .blue:   Color(red: 0.49, green: 0.63, blue: 0.96) // #7da0f5
        case .purple: Color(red: 0.73, green: 0.56, blue: 0.98) // #bb8ffa
        case .pink:   Color(red: 1.00, green: 0.47, blue: 0.66) // #ff78a8
        }
    }

    var label: String {
        switch self {
        case .base: "Default"
        default: rawValue.capitalized
        }
    }

    /// Color pre-blended with the terminal background at 25% mix.
    /// Produces an opaque color that looks identical on any dark surface.
    var tint: Color {
        let bg = TerminalTheme.background
        let fg = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let mix = 0.25
        return Color(
            red:   Double(bg.redComponent)   * (1 - mix) + Double(fg.redComponent)   * mix,
            green: Double(bg.greenComponent) * (1 - mix) + Double(fg.greenComponent) * mix,
            blue:  Double(bg.blueComponent)  * (1 - mix) + Double(fg.blueComponent)  * mix
        )
    }

    /// Colored circle for use in NSMenu-backed context menus.
    /// NSMenu renders SF Symbols as template images, stripping color.
    var swatch: Image {
        let size: CGFloat = 12
        let nsImage = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(self.color).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        nsImage.isTemplate = false
        return Image(nsImage: nsImage)
    }
}

@MainActor @Observable
final class TerminalViewModel {
    var title: String = "zsh"
    var customTitle: String?
    var tabColor: TabColor?
    var isRunning: Bool = false
    var profile: TerminalProfile = .default

    /// When true, foreground process tracking is suppressed.
    /// Used for tmux panes where the local shell is a dummy process.
    var isTmuxPane: Bool = false
    var progressState: UInt8? = nil
    var progressValue: Int32? = nil
    private var progressResetTask: Task<Void, Never>?

    var displayTitle: String {
        if let custom = customTitle, !custom.isEmpty { return custom }
        return title
    }

    var currentDirectory: String?
    var executablePath: String?

    private var shellPid: pid_t = 0
    private var shellExecutable: String?
    private var trackingTask: Task<Void, Never>?

    func processStarted(executable: String, args: [String]) {
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

    func progressReported(state: UInt8, progress: Int32) {
        progressResetTask?.cancel()
        if state == 0 {
            progressState = nil
            progressValue = nil
            progressResetTask = nil
        } else {
            progressState = state
            progressValue = progress == -1 ? nil : progress
            progressResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else { return }
                self.progressState = nil
                self.progressValue = nil
            }
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
        let commandRunning = childPath != nil
        if commandRunning != isRunning {
            isRunning = commandRunning
        }
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
