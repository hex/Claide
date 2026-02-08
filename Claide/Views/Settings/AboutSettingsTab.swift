// ABOUTME: About tab showing app identity, version, website, copyright, and update check.
// ABOUTME: Displays Sparkle-powered "Check for Updates" button.

import Sparkle
import SwiftUI

struct AboutSettingsTab: View {
    @ObservedObject private var updateModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.updateModel = CheckForUpdatesViewModel(updater: updater)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                    }
                    Text("Claide")
                        .font(.title2.bold())
                    Text("Version \(version)")
                        .foregroundStyle(.secondary)
                    Link("claide.hexul.com", destination: URL(string: "https://claide.hexul.com")!)
                        .foregroundStyle(.link)
                    Text("\u{00A9} Alexandru Geana (hexul)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                Button("Check for Updates...") {
                    updater.checkForUpdates()
                }
                .disabled(!updateModel.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }
}
