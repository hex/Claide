// ABOUTME: Tracks terminal process state (running, title, working directory).
// ABOUTME: Acts as the bridge between SwiftTerm delegate callbacks and SwiftUI.

import SwiftUI
import Foundation

@MainActor @Observable
final class TerminalViewModel {
    var title: String = "zsh"
    var isRunning: Bool = false
    var currentDirectory: String?
    var executablePath: String?

    func processStarted(executable: String, args: [String]) {
        isRunning = true
        executablePath = executable
        let name = (executable as NSString).lastPathComponent
        title = ([name] + args).joined(separator: " ")
    }

    func processTerminated(exitCode: Int32?) {
        isRunning = false
        title = "\(title) (exited: \(exitCode ?? -1))"
    }

    func titleChanged(_ newTitle: String) {
        title = newTitle
    }

    func directoryChanged(_ directory: String?) {
        // OSC 7 reports a file:// URL (e.g. "file://hostname/Users/hex/path").
        // Extract the filesystem path from the URL.
        guard let raw = directory else {
            currentDirectory = nil
            return
        }
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            currentDirectory = url.path
        } else {
            currentDirectory = raw
        }
    }
}
