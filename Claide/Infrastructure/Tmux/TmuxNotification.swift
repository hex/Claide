// ABOUTME: Typed representations of tmux control mode protocol notifications.
// ABOUTME: Each variant maps to a %notification from tmux -CC stdout.

import Foundation

/// Notifications emitted by tmux in control mode (-CC).
///
/// tmux prefixes each notification with `%` followed by the notification type.
/// Pane IDs use `%<n>`, window IDs use `@<n>`, session IDs use `$<n>`.
enum TmuxNotification: Equatable {

    /// Terminal output from a pane. Data has been octal-unescaped.
    case output(paneID: Int, data: Data)

    /// A command response block completed successfully.
    case blockEnd(commandNumber: Int, data: String)

    /// A command response block completed with an error.
    case blockError(commandNumber: Int, data: String)

    /// A new window was created.
    case windowAdd(windowID: Int)

    /// A window was closed.
    case windowClose(windowID: Int)

    /// A window was renamed.
    case windowRenamed(windowID: Int, name: String)

    /// The layout of a window changed (panes added, removed, or resized).
    case layoutChange(windowID: Int, layout: String)

    /// The active pane in a window changed.
    case windowPaneChanged(windowID: Int, paneID: Int)

    /// A pane's mode changed (e.g. entered copy mode).
    case paneModeChanged(paneID: Int)

    /// The attached session changed.
    case sessionChanged(sessionID: Int, name: String)

    /// The list of sessions changed.
    case sessionsChanged

    /// tmux exited or detached. Optional reason string.
    case exit(reason: String?)

    /// An unrecognized notification. Stored for forward-compatibility.
    case unrecognized(line: String)
}
