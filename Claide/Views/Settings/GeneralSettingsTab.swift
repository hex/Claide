// ABOUTME: General settings tab for shell, startup, scrollback, and window behavior.
// ABOUTME: Controls session defaults like shell path, working directory, and close behavior.

import SwiftUI

struct GeneralSettingsTab: View {
    @AppStorage("shellPath") private var shellPath: String = ""
    @AppStorage("workingDirectory") private var workingDirectory: String = "home"
    @AppStorage("customWorkingDirectory") private var customWorkingDirectory: String = ""
    @AppStorage("scrollbackLines") private var scrollbackLines: Int = 2048
    @AppStorage("newTabPosition") private var newTabPosition: String = "end"
    @AppStorage("confirmBeforeClosing") private var confirmBeforeClosing = true
    @AppStorage("quitWhenLastWindowCloses") private var quitWhenLastWindowCloses = false
    @AppStorage("bellStyle") private var bellStyle: String = "visual"

    private var effectiveShell: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    var body: some View {
        Form {
            Section("Shell") {
                TextField("Shell", text: $shellPath, prompt: Text(effectiveShell))

                Picker("Working Directory", selection: $workingDirectory) {
                    Text("Home (~)").tag("home")
                    Text("Last Used").tag("lastUsed")
                    Text("Custom").tag("custom")
                }

                if workingDirectory == "custom" {
                    HStack {
                        TextField("Path", text: $customWorkingDirectory)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                customWorkingDirectory = url.path
                            }
                        }
                    }
                }
            }

            Section("Scrollback") {
                HStack {
                    Text("Lines")
                    Spacer()
                    TextField("", value: $scrollbackLines, formatter: {
                        let f = NumberFormatter()
                        f.numberStyle = .none
                        f.usesGroupingSeparator = false
                        return f
                    }())
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 80)
                }
            }

            Section("Tabs") {
                Picker("New Tab Position", selection: $newTabPosition) {
                    Text("End").tag("end")
                    Text("After Current").tag("afterCurrent")
                }
            }

            Section("Window") {
                Toggle("Confirm before closing with running process", isOn: $confirmBeforeClosing)
                Toggle("Quit when last window closes", isOn: $quitWhenLastWindowCloses)
                Picker("Bell", selection: $bellStyle) {
                    Text("None").tag("none")
                    Text("Visual").tag("visual")
                    Text("Audio").tag("audio")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }
}
