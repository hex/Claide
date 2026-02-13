// ABOUTME: Terminal settings tab for mouse behavior.
// ABOUTME: Controls input behavior for all terminal panes.

import SwiftUI

struct TerminalSettingsTab: View {
    @AppStorage("copyOnSelect") private var copyOnSelect: Bool = false
    @AppStorage("pasteOnRightClick") private var pasteOnRightClick: Bool = false

    var body: some View {
        Form {
            Section("Mouse") {
                Toggle("Copy on select", isOn: $copyOnSelect)
                Toggle("Paste on right-click", isOn: $pasteOnRightClick)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }
}
