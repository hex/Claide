// ABOUTME: Appearance settings tab for UI font size and pane focus preferences.
// ABOUTME: Controls visual indicators like focus stripe and unfocused pane dimming.

import SwiftUI

struct AppearanceSettingsTab: View {
    @AppStorage("uiFontSize") private var uiFontSize: Double = 12
    @AppStorage("paneFocusIndicator") private var paneFocusIndicator = true
    @AppStorage("dimUnfocusedPanes") private var dimUnfocusedPanes = true

    var body: some View {
        Form {
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

            Section("Panes") {
                Toggle("Show focus indicator", isOn: $paneFocusIndicator)
                Toggle("Dim unfocused panes", isOn: $dimUnfocusedPanes)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}
