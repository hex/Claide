// ABOUTME: Appearance settings tab for fonts, color scheme, and pane visual preferences.
// ABOUTME: Controls how terminal and UI elements look.

import SwiftUI

struct AppearanceSettingsTab: View {
    @AppStorage("fontFamily") private var fontFamily: String = ""
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 14
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"
    @AppStorage("uiFontSize") private var uiFontSize: Double = 12
    @AppStorage("paneFocusIndicator") private var paneFocusIndicator = true
    @AppStorage("dimUnfocusedPanes") private var dimUnfocusedPanes = true

    var body: some View {
        Form {
            Section("Terminal Font") {
                Picker("Family", selection: $fontFamily) {
                    Text("System Mono")
                        .tag("")
                    Divider()
                    ForEach(FontSelection.monospacedFamilies(), id: \.self) { family in
                        Text(family)
                            .tag(family)
                    }
                }

                Stepper(value: $terminalFontSize, in: 8...72, step: 1) {
                    HStack {
                        Text("Size")
                        Spacer()
                        Text("\(Int(terminalFontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section("Color Scheme") {
                ThemeBrowser(selection: $schemeName)
            }

            Section("UI") {
                Stepper(value: $uiFontSize, in: 9...18, step: 1) {
                    HStack {
                        Text("Sidebar Font Size")
                        Spacer()
                        Text("\(Int(uiFontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section("Panes") {
                Toggle("Show focus indicator", isOn: $paneFocusIndicator)
                Toggle("Dim unfocused panes", isOn: $dimUnfocusedPanes)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }
}
