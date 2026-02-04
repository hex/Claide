// ABOUTME: Swift wrapper over the Rust C FFI for terminal emulation.
// ABOUTME: Manages lifecycle, event dispatch, and grid snapshots.

import Foundation

/// Wraps a Rust-backed terminal emulator with PTY and event callbacks.
///
/// Events from the Rust reader thread are dispatched to the main thread
/// before invoking closures. The bridge retains itself via the C callback
/// context pointer until `deinit`.
final class TerminalBridge: @unchecked Sendable {
    let handle: ClaideTerminalRef
    let shellPid: UInt32

    var onTitle: ((String) -> Void)?
    var onDirectoryChange: ((String) -> Void)?
    var onChildExit: ((Int32) -> Void)?
    var onWakeup: (() -> Void)?
    var onBell: (() -> Void)?

    /// Spawn a shell process and start terminal emulation.
    ///
    /// - Parameters:
    ///   - shell: Path to the shell executable (e.g. "/bin/zsh").
    ///   - args: Shell arguments (e.g. ["-l"]).
    ///   - environment: Environment variables as key-value pairs.
    ///   - directory: Initial working directory.
    ///   - cols: Terminal width in columns.
    ///   - rows: Terminal height in rows.
    ///   - cellWidth: Cell width in pixels.
    ///   - cellHeight: Cell height in pixels.
    init?(
        shell: String,
        args: [String],
        environment: [(String, String)],
        directory: String,
        cols: UInt32,
        rows: UInt32,
        cellWidth: UInt16,
        cellHeight: UInt16
    ) {
        // Convert Swift strings to C strings for FFI
        let cShell = shell.withCString { strdup($0) }!
        defer { free(cShell) }

        let cArgs = args.map { $0.withCString { strdup($0)! } }
        defer { cArgs.forEach { free($0) } }

        let cEnvKeys = environment.map { $0.0.withCString { strdup($0)! } }
        let cEnvValues = environment.map { $0.1.withCString { strdup($0)! } }
        defer {
            cEnvKeys.forEach { free($0) }
            cEnvValues.forEach { free($0) }
        }

        let cDir = directory.withCString { strdup($0) }!
        defer { free(cDir) }

        // Create temporary handle to get `self` pointer for callback context.
        // We need a two-phase init: allocate handle first, then set context.
        // Since claide_terminal_create needs the context at creation time,
        // we'll use a static trampoline that receives context = self.
        var tempHandle: ClaideTerminalRef?

        // We need self to exist before calling create, so use a class-level
        // temporary storage pattern. Actually, we can use withExtendedLifetime
        // since the callback won't fire until after init completes (reader thread
        // needs PTY bytes first).

        // Use UnsafeMutableRawPointer to self — safe because we're in init
        // and the bridge outlives the handle.
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self as AnyObject).toOpaque())

        // Actually, `self` isn't available yet at this point in a failable init.
        // We need a different approach: store a pointer to a Box that we fill in later.
        // Use a context wrapper.

        // Simplest approach: use a heap-allocated context box.
        let context = TerminalBridgeContext()

        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        tempHandle = cArgs.withUnsafeBufferPointer { argsBuffer in
            let argPtrs = argsBuffer.map { UnsafePointer($0) }
            return argPtrs.withUnsafeBufferPointer { argPtrBuffer in
                cEnvKeys.withUnsafeBufferPointer { keysBuffer in
                    let keyPtrs = keysBuffer.map { UnsafePointer($0) }
                    return keyPtrs.withUnsafeBufferPointer { keyPtrBuffer in
                        cEnvValues.withUnsafeBufferPointer { valuesBuffer in
                            let valuePtrs = valuesBuffer.map { UnsafePointer($0) }
                            return valuePtrs.withUnsafeBufferPointer { valuePtrBuffer in
                                claide_terminal_create(
                                    cShell,
                                    argPtrBuffer.baseAddress,
                                    UInt32(args.count),
                                    keyPtrBuffer.baseAddress,
                                    valuePtrBuffer.baseAddress,
                                    UInt32(environment.count),
                                    cDir,
                                    cols, rows,
                                    cellWidth, cellHeight,
                                    terminalEventCallback,
                                    contextPtr
                                )
                            }
                        }
                    }
                }
            }
        }

        guard let h = tempHandle else {
            // Release the context since we won't be using it
            Unmanaged<TerminalBridgeContext>.fromOpaque(contextPtr).release()
            return nil
        }

        self.handle = h
        self.shellPid = claide_terminal_shell_pid(h)

        // Wire up the context to dispatch events to this bridge
        context.bridge = self
    }

    /// Write raw bytes to the terminal input.
    func write(_ data: Data) {
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            claide_terminal_write(handle, ptr, UInt32(buffer.count))
        }
    }

    /// Write a UTF-8 string to the terminal input.
    func write(_ string: String) {
        string.withCString { cstr in
            claide_terminal_write_str(handle, cstr)
        }
    }

    /// Resize the terminal grid and PTY.
    func resize(cols: UInt32, rows: UInt32, cellWidth: UInt16, cellHeight: UInt16) {
        claide_terminal_resize(handle, cols, rows, cellWidth, cellHeight)
    }

    /// Take a snapshot of the visible terminal grid.
    func snapshot() -> UnsafeMutablePointer<ClaideGridSnapshot>? {
        claide_terminal_snapshot(handle)
    }

    /// Free a snapshot returned by `snapshot()`.
    static func freeSnapshot(_ snapshot: UnsafeMutablePointer<ClaideGridSnapshot>?) {
        claide_terminal_snapshot_free(snapshot)
    }

    deinit {
        claide_terminal_destroy(handle)
    }
}

// MARK: - Event Callback Infrastructure

/// Heap-allocated context that mediates between the C callback and the Swift bridge.
/// Using a separate object avoids the chicken-and-egg problem of needing `self`
/// before init completes.
private final class TerminalBridgeContext: @unchecked Sendable {
    weak var bridge: TerminalBridge?
}

/// C-compatible callback function invoked by the Rust reader thread.
/// Dispatches to the main thread before touching any bridge state.
private let terminalEventCallback: ClaideEventCallback = {
    (context: UnsafeMutableRawPointer?,
     eventType: UInt32,
     stringValue: UnsafePointer<CChar>?,
     intValue: Int32) in

    guard let context else { return }

    // Unretained reference — the context is retained by the bridge's init
    let ctx = Unmanaged<TerminalBridgeContext>.fromOpaque(context).takeUnretainedValue()
    guard let bridge = ctx.bridge else { return }

    // Extract string value on this thread (it may be freed after callback returns)
    let string: String? = stringValue.map { String(cString: $0) }

    DispatchQueue.main.async {
        switch eventType {
        case UInt32(ClaideEventWakeup):
            bridge.onWakeup?()
        case UInt32(ClaideEventTitle):
            if let title = string {
                bridge.onTitle?(title)
            }
        case UInt32(ClaideEventBell):
            bridge.onBell?()
        case UInt32(ClaideEventChildExit):
            bridge.onChildExit?(intValue)
        case UInt32(ClaideEventDirectoryChange):
            if let dir = string {
                bridge.onDirectoryChange?(dir)
            }
        default:
            break
        }
    }
}
