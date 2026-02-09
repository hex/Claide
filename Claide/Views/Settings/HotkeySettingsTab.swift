// ABOUTME: Settings tab for configuring the global hotkey dropdown terminal.
// ABOUTME: Controls hotkey binding, window position, animation, and behavior.

import SwiftUI

struct HotkeySettingsTab: View {
    @AppStorage("hotkeyEnabled") private var enabled = false
    @AppStorage("hotkeyPosition") private var position = "top"
    @AppStorage("hotkeyScreen") private var screen = "cursor"
    @AppStorage("hotkeySize") private var size: Double = 50.0
    @AppStorage("hotkeyAnimation") private var animation = "slide"
    @AppStorage("hotkeyAnimationDuration") private var animationDuration: Double = 0.2
    @AppStorage("hotkeyHideOnFocusLoss") private var hideOnFocusLoss = true
    @AppStorage("hotkeyAllSpaces") private var allSpaces = true
    @AppStorage("hotkeyShowSidebar") private var showSidebar = false
    @AppStorage("hotkeyFloating") private var floating = true

    var body: some View {
        Form {
            Section("Hotkey") {
                Toggle("Enable hotkey window", isOn: $enabled)

                HStack {
                    Text("Shortcut")
                    Spacer()
                    HotkeyRecorderView()
                }
            }

            Section("Position") {
                Picker("Edge", selection: $position) {
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                    Text("Left").tag("left")
                    Text("Right").tag("right")
                }

                Picker("Screen", selection: $screen) {
                    Text("Screen with cursor").tag("cursor")
                    Text("Primary screen").tag("primary")
                }

                HStack {
                    Text("Size")
                    Slider(value: $size, in: 10...100, step: 5)
                    Text("\(Int(size))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            Section("Animation") {
                Picker("Style", selection: $animation) {
                    Text("Slide").tag("slide")
                    Text("Fade").tag("fade")
                    Text("Instant").tag("instant")
                }

                if animation != "instant" {
                    HStack {
                        Text("Duration")
                        Slider(value: $animationDuration, in: 0.05...0.5, step: 0.05)
                        Text("\(animationDuration, specifier: "%.2f")s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Behavior") {
                Toggle("Hide when window loses focus", isOn: $hideOnFocusLoss)
                Toggle("Show on all Spaces", isOn: $allSpaces)
                Toggle("Float above other windows", isOn: $floating)
                Toggle("Show sidebar", isOn: $showSidebar)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }
}
