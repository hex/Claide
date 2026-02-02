// ABOUTME: Settings window for user preferences, accessible via Cmd+,.
// ABOUTME: Currently offers monospaced font selection for terminal and graph panels.

import SwiftUI

struct SettingsView: View {
    @AppStorage("fontFamily") private var fontFamily: String = ""
    @AppStorage("cursorStyle") private var cursorStyle: String = "bar"
    @AppStorage("cursorBlink") private var cursorBlink: Bool = true

    var body: some View {
        Form {
            Picker("Terminal Font", selection: $fontFamily) {
                Text("System Mono")
                    .tag("")
                Divider()
                ForEach(FontSelection.monospacedFamilies(), id: \.self) { family in
                    Text(family)
                        .tag(family)
                }
            }

            Picker("Cursor Style", selection: $cursorStyle) {
                Text("Block  \u{2588}").tag("block")
                Text("Underline  \u{2581}").tag("underline")
                Text("Bar  \u{2502}").tag("bar")
            }

            Toggle("Blinking Cursor", isOn: $cursorBlink)
        }
        .formStyle(.grouped)
        .frame(width: 350)
    }
}
