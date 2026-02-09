// ABOUTME: Registers a system-wide hotkey using Carbon's RegisterEventHotKey.
// ABOUTME: Provides conversion between Cocoa modifier flags and Carbon modifier bitmask.

import AppKit
import Carbon.HIToolbox

/// Registers a system-wide keyboard shortcut that fires even when the app is not focused.
/// Uses Carbon's RegisterEventHotKey — the only permission-free mechanism on macOS.
@MainActor
final class GlobalHotkey {

    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?

    /// Static weak reference used by the C callback to dispatch to the current instance.
    /// Carbon callbacks are @convention(c) and cannot capture context.
    /// nonisolated(unsafe) because deinit needs to clear it and the C callback reads it.
    nonisolated(unsafe) private static weak var activeInstance: GlobalHotkey?

    private let handler: () -> Void

    /// Register a global hotkey.
    /// - Parameters:
    ///   - keyCode: Virtual key code (same as NSEvent.keyCode).
    ///   - modifiers: Cocoa modifier flags (.command, .option, .control, .shift).
    ///   - handler: Called when the hotkey is pressed.
    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        self.handler = handler
        Self.activeInstance = self
        register(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        // Clear the static reference if it points to us
        if Self.activeInstance === self {
            Self.activeInstance = nil
        }
    }

    // MARK: - Registration

    private func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        let carbonMods = Self.carbonModifiers(from: modifiers)
        var hotKeyID = EventHotKeyID(signature: 0x434C_4149, id: 1) // "CLAI"

        // Install the Carbon event handler for hotkey events
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                // Dispatch to the active instance on the main thread.
                // No userData needed — we use the static weak reference.
                DispatchQueue.main.async {
                    GlobalHotkey.activeInstance?.handler()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            NSLog("GlobalHotkey: InstallEventHandler failed with status \(status)")
            return
        }

        let regStatus = RegisterEventHotKey(
            keyCode,
            carbonMods,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if regStatus != noErr {
            NSLog("GlobalHotkey: RegisterEventHotKey failed with status \(regStatus)")
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
