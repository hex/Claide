// ABOUTME: Registers a system-wide hotkey using Carbon's RegisterEventHotKey.
// ABOUTME: Provides conversion between Cocoa modifier flags and Carbon modifier bitmask.

import AppKit
import Carbon.HIToolbox

/// Registers a system-wide keyboard shortcut that fires even when the app is not focused.
/// Uses Carbon's RegisterEventHotKey — the only permission-free mechanism on macOS.
@MainActor
final class GlobalHotkey {

    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    private let handler: () -> Void

    /// Register a global hotkey.
    /// - Parameters:
    ///   - keyCode: Virtual key code (same as NSEvent.keyCode).
    ///   - modifiers: Cocoa modifier flags (.command, .option, .control, .shift).
    ///   - handler: Called when the hotkey is pressed.
    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        self.handler = handler
        register(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        // UnregisterEventHotKey is a plain C function, safe to call from nonisolated deinit.
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }

    // MARK: - Registration

    private func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        let carbonMods = Self.carbonModifiers(from: modifiers)

        // Unique ID for this hotkey — signature + id pair
        var hotKeyID = EventHotKeyID(signature: 0x434C_4149, id: 1) // "CLAI"

        // Install the Carbon event handler that dispatches to our Swift closure
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let handlerPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    hotkey.handler()
                }
                return noErr
            },
            1,
            &eventType,
            handlerPtr,
            nil
        )

        RegisterEventHotKey(
            keyCode,
            carbonMods,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    // MARK: - Modifier Conversion

    /// Convert Cocoa modifier flags to Carbon modifier bitmask.
    nonisolated static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        return carbon
    }

    /// Convert Carbon modifier bitmask back to Cocoa modifier flags.
    nonisolated static func cocoaModifiers(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey) != 0     { flags.insert(.command) }
        if carbon & UInt32(optionKey) != 0  { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(shiftKey) != 0   { flags.insert(.shift) }
        return flags
    }
}
