// ABOUTME: Codable models for persisting and restoring terminal session state.
// ABOUTME: Captures window frames, tab layouts, pane trees, and working directories.

import Foundation

/// Complete application state for session restoration.
struct SessionState: Codable {
    let windows: [WindowState]
}

/// State of a single window.
struct WindowState: Codable {
    let frame: CodableRect
    let tabs: [TabState]
    let activeTabIndex: Int
}

/// State of a single tab within a window.
struct TabState: Codable {
    let paneTree: PaneNode
    let activePaneID: PaneID
    let paneDirectories: [String: String]  // PaneID.uuidString -> directory path
    var paneProfiles: [String: TerminalProfile]?  // PaneID.uuidString -> profile (nil = all default)
}

/// CGRect wrapper for Codable conformance.
struct CodableRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Snapshot Helpers

extension TerminalTabManager {
    /// Capture the current state of all tabs in this tab manager.
    func captureTabStates() -> [TabState] {
        tabs.map { tab in
            var dirs: [String: String] = [:]
            var profiles: [String: TerminalProfile] = [:]
            for (paneID, vm) in tab.paneViewModels {
                if let dir = vm.currentDirectory {
                    dirs[paneID.uuidString] = dir
                }
                if vm.profile != .default {
                    profiles[paneID.uuidString] = vm.profile
                }
            }
            return TabState(
                paneTree: tab.paneController.paneTree,
                activePaneID: tab.paneController.activePaneID,
                paneDirectories: dirs,
                paneProfiles: profiles.isEmpty ? nil : profiles
            )
        }
    }
}

// MARK: - Persistence

enum SessionPersistence {
    private static var stateURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let claideDir = appSupport.appendingPathComponent("Claide", isDirectory: true)
        try? FileManager.default.createDirectory(at: claideDir, withIntermediateDirectories: true)
        return claideDir.appendingPathComponent("session.json")
    }

    static func save(_ state: SessionState) {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            // Best-effort persistence — don't crash on save failure
        }
    }

    static func load() -> SessionState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(SessionState.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: stateURL)
    }
}
