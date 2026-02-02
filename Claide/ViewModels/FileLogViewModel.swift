// ABOUTME: Watches changes.md and maintains a parsed list of file modifications.
// ABOUTME: Re-parses the file on each write event from the FileWatcher.

import Foundation

@MainActor @Observable
final class FileLogViewModel {
    var changes: [FileChange] = []
    var error: String?

    private var watcher: FileWatcher?
    private var watchedPath: String?

    func startWatching(path: String) {
        guard path != watchedPath else { return }
        stopWatching()
        watchedPath = path

        // Initial load
        reload(from: path)

        // FileWatcher fires on main queue, safe to capture self
        let callback: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                self?.reload(from: path)
            }
        }
        watcher = FileWatcher(path: path, onChange: callback)
        watcher?.start()
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
        watchedPath = nil
    }

    private func reload(from path: String) {
        do {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            changes = FileChange.parseAll(from: contents).reversed()
        } catch {
            self.error = "Failed to read \(path): \(error.localizedDescription)"
        }
    }
}
