// ABOUTME: Named terminal configuration profiles for per-tab/pane customization.
// ABOUTME: Captures shell, directory, color scheme, and font settings.

import Foundation

/// Configuration profile for a terminal pane.
///
/// Each pane can have its own profile. The `default` profile reads settings
/// from UserDefaults so existing global preferences continue to work.
struct TerminalProfile: Codable, Equatable {
    var name: String
    var shell: String?
    var directory: String?
    var colorScheme: String?
    var fontFamily: String?
    var fontSize: Double?
    /// The built-in profile that inherits all settings from UserDefaults.
    static let `default` = TerminalProfile(name: "Default")

    /// Resolve the effective shell path (profile override or system default).
    var resolvedShell: String {
        if let shell, !shell.isEmpty { return shell }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// Resolve the effective working directory.
    var resolvedDirectory: String {
        if let directory, !directory.isEmpty { return directory }
        return NSHomeDirectory()
    }

    /// Resolve the effective color scheme name.
    var resolvedColorScheme: String {
        colorScheme ?? UserDefaults.standard.string(forKey: "terminalColorScheme") ?? "hexed"
    }

    /// Resolve the effective font family.
    var resolvedFontFamily: String {
        fontFamily ?? ""
    }

    /// Resolve the effective font size.
    var resolvedFontSize: Double {
        fontSize ?? {
            let size = UserDefaults.standard.double(forKey: "terminalFontSize")
            return size > 0 ? size : 14
        }()
    }

}

// MARK: - Profile Storage

enum ProfileStorage {
    private static let key = "terminalProfiles"

    static func loadAll() -> [TerminalProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profiles = try? JSONDecoder().decode([TerminalProfile].self, from: data)
        else { return [] }
        return profiles
    }

    static func saveAll(_ profiles: [TerminalProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
