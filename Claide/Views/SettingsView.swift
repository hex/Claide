// ABOUTME: Settings window for user preferences, accessible via Cmd+,.
// ABOUTME: Terminal font/size/cursor and UI appearance options.

import SwiftUI

struct SettingsView: View {
    @AppStorage("fontFamily") private var fontFamily: String = ""
    @AppStorage("cursorStyle") private var cursorStyle: String = "bar"
    @AppStorage("cursorBlink") private var cursorBlink: Bool = true
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 14
    @AppStorage("uiFontSize") private var uiFontSize: Double = 13

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
            }

            Section("Appearance") {
                HStack {
                    Text("UI Font Size")
                    Spacer()
                    Stepper(value: $uiFontSize, in: 9...18, step: 1) {
                        Text("\(Int(uiFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}
