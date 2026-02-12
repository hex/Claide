// ABOUTME: Monitors the Cmd key with a 300ms hold delay before reporting pressed state.
// ABOUTME: Handles app activation/deactivation to prevent stuck key state.

import AppKit
import SwiftUI

@MainActor
@Observable
final class CommandKeyObserver {
    private static let holdDelay: Duration = .milliseconds(300)

    var isPressed: Bool
    nonisolated(unsafe) private var monitor: Any?
    nonisolated(unsafe) private var didBecomeActiveObserver: NSObjectProtocol?
    nonisolated(unsafe) private var didResignActiveObserver: NSObjectProtocol?
    nonisolated(unsafe) private var holdTask: Task<Void, Never>?

    init() {
        isPressed = false
        monitor = nil
        didBecomeActiveObserver = nil
        didResignActiveObserver = nil
        holdTask = nil
        configureObservers()
    }

    private func configureObservers() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleCommandKeyChange(isDown: event.modifierFlags.contains(.command))
            }
            return event
        }
        let center = NotificationCenter.default
        didBecomeActiveObserver = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleCommandKeyChange(isDown: NSEvent.modifierFlags.contains(.command))
            }
        }
        didResignActiveObserver = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleCommandKeyChange(isDown: false)
            }
        }
    }

    private func handleCommandKeyChange(isDown: Bool) {
        holdTask?.cancel()
        holdTask = nil

        if isDown {
            holdTask = Task {
                try? await Task.sleep(for: Self.holdDelay)
                guard !Task.isCancelled else { return }
                isPressed = true
            }
        } else {
            isPressed = false
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let didBecomeActiveObserver { NotificationCenter.default.removeObserver(didBecomeActiveObserver) }
        if let didResignActiveObserver { NotificationCenter.default.removeObserver(didResignActiveObserver) }
        holdTask?.cancel()
    }
}
