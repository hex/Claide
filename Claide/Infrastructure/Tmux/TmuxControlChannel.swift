// ABOUTME: Owns a Process running tmux in control mode (-CC).
// ABOUTME: Reads stdout line-by-line, feeds to TmuxProtocolParser, sends commands to stdin.

import Foundation

/// Manages the tmux control mode process and its I/O streams.
///
/// Launches `tmux -CC` (or `ssh ... tmux -CC attach`) as a subprocess.
/// Stdout is read line-by-line on a background queue and parsed into
/// `TmuxNotification` values. Commands are sent via stdin.
final class TmuxControlChannel: @unchecked Sendable {

    /// Fired for each parsed notification from tmux stdout.
    var onNotification: ((TmuxNotification) -> Void)? {
        didSet { parser.onNotification = onNotification }
    }

    /// Fired when the tmux process exits (with the exit status).
    var onDisconnect: ((Int32) -> Void)?

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let parser = TmuxProtocolParser()
    private let readQueue = DispatchQueue(label: "com.claide.tmux.read", qos: .userInitiated)

    private var lineBuffer = Data()

    /// Start a local tmux control mode session.
    ///
    /// - Parameters:
    ///   - sessionName: Existing session to attach, or nil to create a new one.
    ///   - tmuxPath: Path to the tmux binary. Defaults to `/usr/bin/tmux`.
    func startLocal(sessionName: String? = nil, tmuxPath: String = "/usr/bin/tmux") {
        process.executableURL = URL(fileURLWithPath: tmuxPath)

        var args = ["-CC"]
        if let name = sessionName {
            args += ["attach-session", "-t", name]
        } else {
            args += ["new-session"]
        }
        process.arguments = args

        startProcess()
    }

    /// Start a remote tmux control mode session over SSH.
    ///
    /// - Parameters:
    ///   - host: SSH destination (e.g. "user@host").
    ///   - sessionName: tmux session name on the remote host.
    ///   - sshPath: Path to the ssh binary. Defaults to `/usr/bin/ssh`.
    func startRemote(host: String, sessionName: String? = nil, sshPath: String = "/usr/bin/ssh") {
        process.executableURL = URL(fileURLWithPath: sshPath)

        var remoteCmd = "tmux -CC"
        if let name = sessionName {
            remoteCmd += " attach-session -t \(name)"
        } else {
            remoteCmd += " new-session"
        }
        process.arguments = [host, remoteCmd]

        startProcess()
    }

    /// Send a tmux command through the control channel.
    ///
    /// Commands are newline-terminated. Do not include a trailing newline.
    /// Example: `send(command: "send-keys -t %0 ls Enter")`
    func send(command: String) {
        let data = Data((command + "\n").utf8)
        stdinPipe.fileHandleForWriting.write(data)
    }

    /// Detach from the tmux session gracefully.
    func detach() {
        send(command: "detach-client")
    }

    /// Terminate the control channel process.
    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    var isRunning: Bool {
        process.isRunning
    }

    // MARK: - Private

    private func startProcess() {
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] proc in
            self?.onDisconnect?(proc.terminationStatus)
        }

        let handle = stdoutPipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fh in
            self?.readQueue.async {
                self?.handleReadableData(fh.availableData)
            }
        }

        do {
            try process.run()
        } catch {
            onDisconnect?(-1)
        }
    }

    private func handleReadableData(_ data: Data) {
        guard !data.isEmpty else {
            // EOF — process has exited or pipe closed.
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            flushLineBuffer()
            return
        }

        lineBuffer.append(data)
        extractLines()
    }

    private func extractLines() {
        let newline = UInt8(ascii: "\n")

        while let newlineIndex = lineBuffer.firstIndex(of: newline) {
            let lineData = lineBuffer[lineBuffer.startIndex..<newlineIndex]
            if let line = String(data: lineData, encoding: .utf8) {
                parser.feed(line: line)
            }
            lineBuffer.removeSubrange(lineBuffer.startIndex...newlineIndex)
        }
    }

    private func flushLineBuffer() {
        guard !lineBuffer.isEmpty else { return }
        if let line = String(data: lineBuffer, encoding: .utf8), !line.isEmpty {
            parser.feed(line: line)
        }
        lineBuffer.removeAll()
    }
}
