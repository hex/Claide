// ABOUTME: NSViewRepresentable wrapping NSTextField for the command palette search field.
// ABOUTME: Uses AppKit's makeFirstResponder to reliably steal focus from GhosttyTerminalView.

import AppKit
import SwiftUI

/// Text field that takes AppKit first responder as soon as it enters a window.
///
/// SwiftUI's `@FocusState` can't reliably override AppKit's first responder
/// when a raw NSView (like GhosttyTerminalView) holds it. This wrapper uses
/// `window.makeFirstResponder()` directly on the underlying NSTextField.
struct PaletteTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""

    func makeNSView(context: Context) -> AutoFocusTextField {
        let field = AutoFocusTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16)
        field.delegate = context.coordinator
        field.cell?.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ field: AutoFocusTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}

/// NSTextField subclass that claims first responder when added to a window.
///
/// `viewDidMoveToWindow` fires once the view is installed in the window
/// hierarchy, which is the right moment to call `makeFirstResponder`.
final class AutoFocusTextField: NSTextField {
    private var hasFocused = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if !hasFocused, let window {
            hasFocused = true
            window.makeFirstResponder(self)
        }
    }
}
