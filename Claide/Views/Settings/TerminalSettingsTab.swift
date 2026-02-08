// ABOUTME: Terminal settings tab for cursor and mouse behavior.
// ABOUTME: Controls input behavior for all terminal panes.

import SwiftUI

struct TerminalSettingsTab: View {
    @AppStorage("cursorStyle") private var cursorStyle: String = "bar"
    @AppStorage("cursorBlink") private var cursorBlink: Bool = true
    @AppStorage("copyOnSelect") private var copyOnSelect: Bool = false
    @AppStorage("pasteOnRightClick") private var pasteOnRightClick: Bool = false

    var body: some View {
        Form {
            Section("Cursor") {
                Picker("Style", selection: $cursorStyle) {
                    Text("Block  \u{2588}").tag("block")
                    Text("Underline  \u{2581}").tag("underline")
                    Text("Bar  \u{2502}").tag("bar")
                }

                Toggle("Blinking Cursor", isOn: $cursorBlink)
            }

            Section("Mouse") {
                Toggle("Copy on select", isOn: $copyOnSelect)
                Toggle("Paste on right-click", isOn: $pasteOnRightClick)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }
}
