// ABOUTME: Swift wrapper over the Rust C FFI for terminal emulation.
// ABOUTME: Manages lifecycle, event dispatch, and grid snapshots.

import Foundation
import os

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

        let context = TerminalBridgeContext()
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        // Build optional pointer arrays matching C's `const char *const *` type
        var argPtrs: [UnsafePointer<CChar>?] = cArgs.map { UnsafePointer($0) }
        var keyPtrs: [UnsafePointer<CChar>?] = cEnvKeys.map { UnsafePointer($0) }
        var valuePtrs: [UnsafePointer<CChar>?] = cEnvValues.map { UnsafePointer($0) }

        let tempHandle = claide_terminal_create(
            cShell,
            &argPtrs,
            UInt32(args.count),
            &keyPtrs,
            &valuePtrs,
            UInt32(environment.count),
            cDir,
            cols, rows,
            cellWidth, cellHeight,
            terminalEventCallback,
            contextPtr
        )

        guard let h: ClaideTerminalRef = tempHandle else {
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

    /// Resize the terminal grid and notify the shell (sends SIGWINCH).
    func resize(cols: UInt32, rows: UInt32, cellWidth: UInt16, cellHeight: UInt16) {
        claide_terminal_resize(handle, cols, rows, cellWidth, cellHeight)
    }

    /// Resize the terminal grid without notifying the shell.
    func resizeGrid(cols: UInt32, rows: UInt32) {
        claide_terminal_resize_grid(handle, cols, rows)
    }

    /// Resize the terminal grid without reflowing content or notifying the shell.
    /// Old content stays as-is — rows are truncated or padded instead of rewrapped.
    func resizeGridNoReflow(cols: UInt32, rows: UInt32) {
        claide_terminal_resize_grid_no_reflow(handle, cols, rows)
    }

    /// Notify the shell of the current window size (sends SIGWINCH).
    func notifyPtySize(cols: UInt32, rows: UInt32, cellWidth: UInt16, cellHeight: UInt16) {
        claide_terminal_notify_pty_size(handle, cols, rows, cellWidth, cellHeight)
    }

    /// Take a snapshot of the visible terminal grid.
    func snapshot() -> UnsafeMutablePointer<ClaideGridSnapshot>? {
        claide_terminal_snapshot(handle)
    }

    /// Free a snapshot returned by `snapshot()`.
    static func freeSnapshot(_ snapshot: UnsafeMutablePointer<ClaideGridSnapshot>?) {
        claide_terminal_snapshot_free(snapshot)
    }

    // MARK: - Row Text

    /// Extract text for a single visible row directly from the terminal grid.
    func rowText(row: Int) -> String? {
        guard let ptr = claide_terminal_row_text(handle, UInt32(row)) else { return nil }
        defer { claide_terminal_free_string(ptr) }
        return String(cString: ptr)
    }

    // MARK: - Scrollback

    /// Scroll the terminal viewport by the given number of lines.
    /// Positive delta scrolls up (into history), negative scrolls down.
    func scroll(delta: Int32) {
        claide_terminal_scroll(handle, delta)
    }

    // MARK: - Search

    /// Start a search with the given query. Searches forward from the cursor.
    /// Returns true if a match was found.
    func searchSet(query: String) -> Bool {
        query.withCString { cstr in
            claide_terminal_search_set(handle, cstr)
        }
    }

    /// Navigate to the next or previous match.
    /// Returns true if a match was found.
    func searchAdvance(forward: Bool) -> Bool {
        claide_terminal_search_advance(handle, forward)
    }

    /// Clear the current search and remove highlights.
    func searchClear() {
        claide_terminal_search_clear(handle)
    }

    // MARK: - Selection

    /// Start a selection at the given grid position.
    func startSelection(row: Int32, col: UInt32, side: SelectionSide, type: SelectionKind) {
        claide_terminal_selection_start(handle, row, col, side.rawValue, `type`.rawValue)
    }

    /// Update the selection endpoint as the mouse moves.
    func updateSelection(row: Int32, col: UInt32, side: SelectionSide) {
        claide_terminal_selection_update(handle, row, col, side.rawValue)
    }

    /// Clear the current selection.
    func clearSelection() {
        claide_terminal_selection_clear(handle)
    }

    /// Extract the selected text, or nil if nothing is selected.
    func selectedText() -> String? {
        guard let ptr = claide_terminal_selection_text(handle) else { return nil }
        defer { claide_terminal_selection_text_free(ptr) }
        return String(cString: ptr)
    }

    // MARK: - Colors

    /// Push a color scheme's 16 ANSI + FG + BG colors to the Rust terminal.
    func setColors(_ scheme: TerminalColorScheme) {
        var palette = ClaideColorPalette()
        // C arrays import as tuples in Swift; use pointer to write bytes
        withUnsafeMutablePointer(to: &palette.ansi) { tuplePtr in
            tuplePtr.withMemoryRebound(to: UInt8.self, capacity: 48) { ptr in
                for i in 0..<16 {
                    ptr[i * 3]     = scheme.ansi[i].r
                    ptr[i * 3 + 1] = scheme.ansi[i].g
                    ptr[i * 3 + 2] = scheme.ansi[i].b
                }
            }
        }
        palette.fg_r = scheme.foreground.r
        palette.fg_g = scheme.foreground.g
        palette.fg_b = scheme.foreground.b
        palette.bg_r = scheme.background.r
        palette.bg_g = scheme.background.g
        palette.bg_b = scheme.background.b
        claide_terminal_set_colors(handle, &palette)
    }

    deinit {
        claide_terminal_destroy(handle)
    }
}

// MARK: - Selection Types

/// Which half of a cell the cursor is on (determines selection boundary).
enum SelectionSide: UInt8 {
    case left = 0
    case right = 1
}

/// Selection mode matching alacritty_terminal's SelectionType.
enum SelectionKind: UInt8 {
    case simple = 0   // Character-by-character
    case block = 1    // Rectangular block
    case semantic = 2 // Word boundaries (double-click)
    case lines = 3    // Full lines (triple-click)
}

// MARK: - Event Callback Infrastructure

/// Heap-allocated context that mediates between the C callback and the Swift bridge.
/// Using a separate object avoids the chicken-and-egg problem of needing `self`
/// before init completes.
private final class TerminalBridgeContext: @unchecked Sendable {
    weak var bridge: TerminalBridge?

    /// Coalesces Wakeup events so at most one GCD dispatch is in flight at a time.
    /// Set to true on the reader thread before dispatch, cleared on main thread after delivery.
    private var _wakeupPending = false
    private var _lock = os_unfair_lock()

    /// Attempt to set the wakeup flag. Returns true if it was previously unset.
    func trySetWakeup() -> Bool {
        os_unfair_lock_lock(&_lock)
        let was = _wakeupPending
        _wakeupPending = true
        os_unfair_lock_unlock(&_lock)
        return !was
    }

    /// Clear the wakeup flag after the main-thread dispatch has delivered.
    func clearWakeup() {
        os_unfair_lock_lock(&_lock)
        _wakeupPending = false
        os_unfair_lock_unlock(&_lock)
    }
}

/// C-compatible callback function invoked by the Rust reader thread.
/// Dispatches to the main thread before touching any bridge state.
/// Wakeup events are coalesced so only one GCD dispatch is in flight at a time.
private let terminalEventCallback: ClaideEventCallback = {
    (context: UnsafeMutableRawPointer?,
     eventType: UInt32,
     stringValue: UnsafePointer<CChar>?,
     intValue: Int32) in

    guard let context else { return }

    // Unretained reference — the context is retained by the bridge's init
    let ctx = Unmanaged<TerminalBridgeContext>.fromOpaque(context).takeUnretainedValue()
    guard let bridge = ctx.bridge else { return }

    // Wakeup events are coalesced: skip the GCD dispatch if one is already queued
    if eventType == UInt32(ClaideEventWakeup) {
        guard ctx.trySetWakeup() else { return }
        DispatchQueue.main.async {
            ctx.clearWakeup()
            bridge.onWakeup?()
        }
        return
    }

    // Extract string value on this thread (it may be freed after callback returns)
    let string: String? = stringValue.map { String(cString: $0) }

    DispatchQueue.main.async {
        switch eventType {
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
