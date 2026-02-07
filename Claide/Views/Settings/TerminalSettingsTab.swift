// ABOUTME: Terminal settings tab for font, cursor, and color scheme preferences.
// ABOUTME: Controls shell appearance and behavior for all terminal panes.

import SwiftUI

struct TerminalSettingsTab: View {
    @AppStorage("fontFamily") private var fontFamily: String = ""
    @AppStorage("cursorStyle") private var cursorStyle: String = "bar"
    @AppStorage("cursorBlink") private var cursorBlink: Bool = true
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 14
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"

    var body: some View {
        Form {
            Section("Terminal") {
                Picker("Font", selection: $fontFamily) {
                    Text("System Mono")
                        .tag("")
                    Divider()
                    ForEach(FontSelection.monospacedFamilies(), id: \.self) { family in
                        Text(family)
                            .tag(family)
                    }
                }

                HStack {
                    Text("Font Size")
                    Spacer()
                    Stepper(value: $terminalFontSize, in: 8...72, step: 1) {
                        Text("\(Int(terminalFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                Picker("Cursor Style", selection: $cursorStyle) {
                    Text("Block  \u{2588}").tag("block")
                    Text("Underline  \u{2581}").tag("underline")
                    Text("Bar  \u{2502}").tag("bar")
                }

                Toggle("Blinking Cursor", isOn: $cursorBlink)

                Picker("Color Scheme", selection: $schemeName) {
                    ForEach(TerminalColorScheme.builtIn) { scheme in
                        Text(scheme.name).tag(scheme.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}
