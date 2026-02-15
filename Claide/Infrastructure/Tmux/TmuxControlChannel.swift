// ABOUTME: Owns a Process running tmux in control mode (-CC).
// ABOUTME: Reads stdout line-by-line, feeds to TmuxProtocolParser, sends commands to stdin.

import Foundation

/// Locates the tmux binary using the user's login shell PATH.
///
/// Runs `command -v tmux` in a login shell to resolve the path regardless
/// of how tmux was installed (Homebrew, MacPorts, nix, etc.). Falls back
/// to common paths if the shell lookup fails.
func findTmux() -> String? {
    // Ask a login shell — picks up ~/.zprofile, ~/.bash_profile, etc.
    // which set up PATH for Homebrew, nix, asdf, etc.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-l", "-c", "command -v tmux"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return findTmuxFallback()
    }
    guard process.terminationStatus == 0 else { return findTmuxFallback() }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
        return findTmuxFallback()
    }
    return path
}

private func findTmuxFallback() -> String? {
    let candidates = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/opt/local/bin/tmux",
        "/usr/bin/tmux",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// Manages the tmux control mode process and its I/O streams.
///
/// Launches `tmux -CC` (or `ssh ... tmux -CC attach`) as a subprocess
/// with a PTY (pseudo-terminal). tmux requires a TTY for `tcgetattr()`
/// even in control mode — plain pipes cause it to fail immediately.
///
/// Stdout is read line-by-line on a background queue and parsed into
/// `TmuxNotification` values. Commands are sent via the PTY master.
final class TmuxControlChannel: @unchecked Sendable {

    /// Fired for each parsed notification from tmux stdout.
    var onNotification: ((TmuxNotification) -> Void)? {
        didSet { parser.onNotification = onNotification }
    }

    /// Fired when the tmux process exits (with the exit status).
    var onDisconnect: ((Int32) -> Void)?

    private let process = Process()
    private let parser = TmuxProtocolParser()
    private let readQueue = DispatchQueue(label: "com.claide.tmux.read", qos: .userInitiated)

    /// PTY master file descriptor — used for both reading and writing.
    private var masterFD: Int32 = -1

    /// FileHandle wrapping the master fd for readability monitoring.
    private var masterHandle: FileHandle?

    private var lineBuffer = Data()

    /// Start a local tmux control mode session.
    ///
    /// - Parameters:
    ///   - sessionName: Existing session to attach, or nil to create a new one.
    ///   - tmuxPath: Path to the tmux binary. Resolved via `findTmux()` if nil.
    func startLocal(sessionName: String? = nil, tmuxPath: String? = nil) {
        guard let path = tmuxPath ?? findTmux() else {
            onDisconnect?(-1)
            return
        }
        process.executableURL = URL(fileURLWithPath: path)

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
    ///
    /// Uses POSIX write() on the PTY master fd. NSFileHandle.write() throws
    /// an Objective-C NSException on broken pipe, which Swift cannot catch.
    func send(command: String) {
        guard process.isRunning, masterFD >= 0 else { return }
        let data = Data((command + "\n").utf8)
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            _ = Darwin.write(masterFD, ptr, buffer.count)
        }
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
        // Create a PTY pair. tmux calls tcgetattr() on stdin during init,
        // which requires a real terminal device — plain pipes fail with ENOTTY.
        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            onDisconnect?(-1)
            return
        }
        masterFD = master

        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] proc in
            // Clear readability handler BEFORE closing fd to prevent
            // availableData from throwing on a closed descriptor.
            self?.masterHandle?.readabilityHandler = nil
            if let fd = self?.masterFD, fd >= 0 {
                Darwin.close(fd)
                self?.masterFD = -1
            }
            self?.onDisconnect?(proc.terminationStatus)
        }

        let handle = FileHandle(fileDescriptor: master, closeOnDealloc: false)
        masterHandle = handle
        handle.readabilityHandler = { [weak self] fh in
            self?.readQueue.async { [weak self] in
                guard let self, self.masterFD >= 0 else { return }
                var buffer = [UInt8](repeating: 0, count: 8192)
                let bytesRead = Darwin.read(self.masterFD, &buffer, buffer.count)
                if bytesRead > 0 {
                    self.handleReadableData(Data(buffer[..<bytesRead]))
                } else {
                    // EOF or error — treat as disconnect.
                    self.handleReadableData(Data())
                }
            }
        }

        do {
            try process.run()
            // Close slave in parent — only the child needs it.
            Darwin.close(slave)
        } catch {
            Darwin.close(master)
            Darwin.close(slave)
            masterFD = -1
            onDisconnect?(-1)
        }
    }

    private func handleReadableData(_ data: Data) {
        guard !data.isEmpty else {
            // EOF — process has exited or PTY closed.
            masterHandle?.readabilityHandler = nil
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
