// ABOUTME: SwiftUI view that captures a global hotkey binding from raw key events.
// ABOUTME: Displays modifier symbols and key name; uses app-level event monitor for capture.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Displays the current hotkey binding and allows recording a new one.
struct HotkeyRecorderView: View {
    @AppStorage("hotkeyKeyCode") private var keyCode: Int = -1
    @AppStorage("hotkeyModifiers") private var modifiers: Int = 0
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if isRecording {
                    Text("Type shortcut...")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                } else {
                    Text(displayString)
                        .foregroundStyle(keyCode >= 0 ? .primary : .secondary)
                }
            }
            .frame(width: 160, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? AnyShapeStyle(.selection.opacity(0.3)) : AnyShapeStyle(.quaternary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? .blue : .clear, lineWidth: 1.5)
            )
            .onTapGesture {
                isRecording = true
            }
            .background(
                HotkeyEventInterceptor(
                    isActive: $isRecording,
                    onRecord: { code, mods in
                        keyCode = Int(code)
                        modifiers = Int(mods.rawValue)
                        isRecording = false
                    },
                    onCancel: {
                        isRecording = false
                    }
                )
            )

            if keyCode >= 0 {
                Button("Clear") {
                    keyCode = -1
                    modifiers = 0
                    isRecording = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var displayString: String {
        guard keyCode >= 0 else { return "Click to record" }
        let mods = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        return Self.hotkeyDisplayString(keyCode: UInt16(keyCode), modifiers: mods)
    }

    /// Format a hotkey as modifier symbols + key name (e.g., "⌃⌥⇧⌘A").
    static func hotkeyDisplayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option)  { parts += "⌥" }
        if modifiers.contains(.shift)   { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        parts += keyName(for: keyCode)
        return parts
    }

    /// Human-readable name for a virtual key code.
    static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Return:       return "Return"
        case kVK_Tab:          return "Tab"
        case kVK_Space:        return "Space"
        case kVK_Delete:       return "Delete"
        case kVK_Escape:       return "Esc"
        case kVK_ForwardDelete: return "Fwd Del"
        case kVK_UpArrow:      return "↑"
        case kVK_DownArrow:    return "↓"
        case kVK_LeftArrow:    return "←"
        case kVK_RightArrow:   return "→"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_Home:    return "Home"
        case kVK_End:     return "End"
        case kVK_PageUp:  return "Page Up"
        case kVK_PageDown: return "Page Down"
        default:
            if let name = characterForKeyCode(keyCode) {
                return name.uppercased()
            }
            return "Key\(keyCode)"
        }
    }

    /// Resolve a key code to its printable character using the current keyboard layout.
    private static func characterForKeyCode(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataPtr, to: CFData.self)
        let layout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

// MARK: - App-Level Event Interceptor

/// Installs/removes an app-level key event monitor when recording is active.
/// Uses addLocalMonitorForEvents to capture keys BEFORE system shortcuts handle them,
/// allowing recording of combinations like Cmd+` that the responder chain never sees.
private struct HotkeyEventInterceptor: NSViewRepresentable {
    @Binding var isActive: Bool
    let onRecord: (UInt16, NSEvent.ModifierFlags) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isActive {
            context.coordinator.startMonitoring(onRecord: onRecord, onCancel: onCancel)
        } else {
            context.coordinator.stopMonitoring()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var monitor: Any?

        func startMonitoring(
            onRecord: @escaping (UInt16, NSEvent.ModifierFlags) -> Void,
            onCancel: @escaping () -> Void
        ) {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Escape cancels recording
                if event.keyCode == UInt16(kVK_Escape) {
                    onCancel()
                    return nil // Consume the event
                }

                // Require at least one modifier (bare keys aren't useful as global hotkeys)
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .intersection([.command, .option, .control, .shift])
                guard !mods.isEmpty else { return event }

                onRecord(event.keyCode, mods)
                return nil // Consume the event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stopMonitoring()
        }
    }
}
