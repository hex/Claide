<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Claide icon">
</p>

# Claide

[claide.hexul.com](https://claide.hexul.com)

A GPU-accelerated macOS terminal emulator built with Swift and [GhosttyKit](https://github.com/ghostty-org/ghostty). Ghostty provides VTE emulation, PTY management, and Metal rendering. Includes a project visualization sidebar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions.

Version 2026.2.2 | macOS 14.0+ | Swift 6.0 | MIT License

<p align="center">
  <img src="docs/screenshot.png" width="720" alt="Claide screenshot">
</p>

## Install

```bash
brew install --cask hex/tap/claide
```

Or download the latest DMG from [GitHub Releases](https://github.com/hex/Claide/releases).

## Features

### Terminal

- **GhosttyKit rendering**: GPU-accelerated Metal rendering via libghostty — VTE parsing, glyph rasterization, and compositing handled by the Ghostty engine
- **Tabs and splits**: Multiple tabs, horizontal/vertical pane splits, pane zoom
- **Session persistence**: Saves and restores tabs, splits, and working directories
- **9 color schemes**: Hexed, Dracula, Nord, Catppuccin Frappe, One Dark, Gruvbox Dark, Tokyo Night, Solarized Dark, Solarized Light
- **URL detection**: Clickable URLs
- **IME**: Full `NSTextInputClient` implementation (marked text, candidate window)
- **Process icons**: Recognizes 40+ executables in the tab bar
- **Claude Code integration**: Context usage tracking via process tree walk + JSONL transcript parsing
- **tmux control mode**: Attach to tmux sessions via `-CC`. Native tab/pane mapping, nested split reconstruction, input routing, and paste interception. Session picker with existing session detection.
- **Hotkey window**: Quake-style dropdown terminal toggled by a global hotkey. Slides in from any screen edge, works over fullscreen apps. Configurable size, position, animation, and behavior.

### Sidebar

```
+---------------------------+----------------+
|                           | BOARD | GRAPH  |
|  Terminal                 |----------------|
|  (tabs, splits)           |  Issue view    |
|                           |  (switchable)  |
|                           |----------------|
|                           |  FILES         |
|                           |  (always on)   |
+---------------------------+----------------+
```

- **Board**: Kanban columns (Open, Active, Blocked, Done). Reads from beads issues or Claude Code tasks.
- **Graph**: Force-directed dependency graph on SwiftUI Canvas. Pan, zoom, drag, click-to-select with 2-hop neighbor highlighting.
- **Files**: Live file change monitor via GCD DispatchSource.
- **Resizable panels**: Draggable divider between Tasks and Files with persisted split ratio.

## Architecture

Two layers — a GhosttyKit terminal engine and a Swift application shell.

### GhosttyKit Engine

`GhosttyApp` (`Infrastructure/Ghostty/GhosttyApp.swift`) is a singleton owning the `ghostty_app_t` handle. It creates a Ghostty config, registers runtime callbacks (wakeup, clipboard, close surface), and routes actions to surfaces.

`GhosttyTerminalView` (`Infrastructure/Ghostty/GhosttyTerminalView.swift`) is an NSView hosting a `ghostty_surface_t`. Ghostty owns the CAMetalLayer and rendering pipeline — the view is layer-hosting (Ghostty sets the layer, then enables `wantsLayer`). A 60fps timer forces Core Animation re-composition since Ghostty's async surface updates don't trigger it in layer-hosting views.

All C callbacks are file-scope free functions to avoid Swift 6 MainActor isolation issues — closures defined in `@MainActor` methods inherit that isolation, causing assertions when Ghostty calls back from its IO thread.

Terminal colors are managed by Ghostty's config (`~/.config/ghostty/config`). Chrome colors (window appearance, pane title bars, dividers) are derived from `ChromeColorScheme` presets.

### Swift Application Shell

**Window**: Chromeless `NSWindow` with repositioned traffic lights and a custom tab bar.

**Hotkey window**: Borderless `NSPanel` with Carbon `RegisterEventHotKey` for the global shortcut. Uses `.nonactivatingPanel` + `.moveToActiveSpace` + `.fullScreenAuxiliary` with deferred activation to appear over fullscreen apps without triggering a space switch. Notch-safe content inset via `auxiliaryTopLeftArea` detection.

### Pane System

`PaneNode` is an immutable N-ary tree for split layouts with functional mutations. `PaneTreeController` manages the tree lifecycle. `PaneSplitView` and `PaneContainerView` handle the recursive NSView hierarchy for rendering splits.

### View Models

| ViewModel | Drives | Data Source |
|---|---|---|
| `TerminalViewModel` | Status bar, directory tracking | Ghostty action callbacks |
| `GraphViewModel` | Board + Graph views, force layout | BeadsService or ClaudeTaskService |
| `FileLogViewModel` | File change list | `changes.md` via FileWatcher |
| `SessionStatusViewModel` | Context usage bar | Claude Code JSONL transcripts |

## Performance

A benchmark script (`tools/termbench.sh`) tests sequential text, dense ASCII, ANSI colors, and Unicode throughput across terminals (Claide, Ghostty, Alacritty, iTerm2, WezTerm, kitty, Terminal.app).

## Build

### Requirements

- macOS 14.0+
- Xcode (Swift 6.0)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- GhosttyKit.xcframework in `Frameworks/` (built from `ThirdParty/ghostty/` via `tools/build-ghosttykit.sh`; requires [Zig](https://ziglang.org/) 0.14+)
- [beads](https://github.com/hex/beads) (`bd` CLI) for issue tracking sidebar (optional; falls back to Claude Code tasks)

### Debug

```bash
xcodegen generate
xcodebuild -scheme Claide -destination 'platform=macOS' build
```

Or open `Claide.xcodeproj` in Xcode after generating.

### Release

Release builds are done locally with a private script that handles archiving, code signing (Developer ID), notarization, DMG creation, and Sparkle EdDSA signing.

## Project Structure

```
Claide/
  ClaideApp.swift                # Entry point, NSApplicationDelegateAdaptor, Sparkle updater
  AppDelegate.swift              # App lifecycle, window restoration, hotkey wiring
  ContentView.swift              # Root layout
  MainWindowController.swift     # Window chrome, traffic light positioning
  MainSplitViewController.swift  # Terminal/sidebar split
  BridgingHeader.h               # System header imports (libproc)
  Infrastructure/
    Ghostty/
      GhosttyApp.swift           # Singleton owning ghostty_app_t, config, callbacks
      GhosttyTerminalView.swift  # NSView hosting ghostty_surface_t with Metal rendering
    Tmux/
      TmuxControlChannel.swift   # PTY-backed tmux -CC process management
      TmuxProtocolParser.swift   # Streaming parser for tmux control mode protocol
      TmuxNotification.swift     # Typed tmux notification model (%output, %layout-change, etc.)
      TmuxSessionManager.swift   # Maps tmux panes/windows to Claide views, routes I/O
      TmuxLayoutParser.swift     # Recursive descent parser for tmux layout descriptors
      TmuxKeyEncoder.swift       # NSEvent to tmux send-keys notation conversion
  HotkeyWindow/
    GlobalHotkey.swift           # Carbon RegisterEventHotKey wrapper
    HotkeyWindowController.swift # Dropdown window positioning, animation, fullscreen overlay
    HotkeyRecorderView.swift     # SwiftUI key recorder with modifier symbols
  Features/
    CommandPalette/              # Fuzzy command palette (items, registry, overlay)
  Theme.swift                    # Colors, fonts, spacing tokens (derived from Ghostty BG/FG)
  Palette.swift                  # Color palette utilities
  FontSelection.swift            # Monospaced font enumeration
  NodeVisuals.swift              # Graph node rendering properties
  EdgeVisuals.swift              # Graph edge rendering properties
  KanbanColumn.swift             # Kanban column layout
  Updates/
    CheckForUpdatesView.swift    # "Check for Updates..." menu item (Sparkle)
  Models/
    Issue.swift                  # Shared issue model
    IssueDependency.swift        # Dependency edges
    FileChange.swift             # Change log entry
    SessionStatus.swift          # Claude Code context usage
    ChromeColorScheme.swift      # 9 named color presets for UI chrome
  ViewModels/
    GraphViewModel.swift         # Issues, positions, force layout
    FileLogViewModel.swift       # File watcher + parser
    TerminalViewModel.swift      # Terminal title, directory, process state
    SessionStatusViewModel.swift
  Views/
    TerminalSection.swift        # Terminal area layout
    SidebarSection.swift         # Sidebar area layout
    Graph/
      GraphPanel.swift           # Canvas-based dependency graph
      IssueNode.swift            # Node rendering
    Kanban/KanbanPanel.swift
    FileLog/FileLogPanel.swift
    Terminal/
      TerminalPanel.swift        # NSViewRepresentable host
      TerminalTabBar.swift       # Tab strip with add/close
      TerminalTabManager.swift   # Tab lifecycle, shell spawning
      TerminalTheme.swift        # Terminal color palette for AppKit views
      TerminalProfile.swift      # Per-terminal configuration
      SessionStatusBar.swift     # Context usage indicator
      SessionState.swift         # Session save/restore
      PaneNode.swift             # Immutable N-ary tree for split layouts
      PaneTreeController.swift   # Split tree lifecycle
      PaneContainerView.swift    # Recursive split container
      PaneSplitView.swift        # Split divider view
    Settings/
      SettingsView.swift         # Settings window (tabbed)
      GeneralSettingsTab.swift   # Shell, scrollback, tabs, window behavior
      TerminalSettingsTab.swift  # Cursor style, mouse behavior
      AppearanceSettingsTab.swift # Fonts, color scheme, pane indicators
      HotkeySettingsTab.swift     # Hotkey window configuration
      AboutSettingsTab.swift     # Version, website, update check
    EmptyStateView.swift
    IssueDetailPopover.swift
    SplitDividerSetter.swift
  Services/
    BeadsService.swift           # bd CLI integration
    ClaudeTaskService.swift      # ~/.claude/tasks/ reader
    FileWatcher.swift            # GCD DispatchSource file monitor
  Resources/
    shell-integration/zsh/       # Shell integration scripts
  Assets.xcassets/
Frameworks/
  GhosttyKit.xcframework/       # Pre-built universal binary (arm64 + x86_64)
ThirdParty/
  ghostty/                       # Ghostty source (reference for API patterns)
tools/
  build-ghosttykit.sh            # Builds GhosttyKit.xcframework from ThirdParty/ghostty
  termbench.sh                   # Terminal throughput benchmark
ClaideTests/                     # Unit and integration tests
project.yml                      # XcodeGen spec
appcast.xml                      # Sparkle update feed
```

## Updates

In-app update checking via [Sparkle](https://sparkle-project.org/). The "Check for Updates..." menu item appears in the Claide menu. Updates are distributed as signed DMGs and verified with EdDSA signatures. The appcast is hosted in this repository and served via `raw.githubusercontent.com`.

## Tests

```bash
xcodebuild -scheme Claide -destination 'platform=macOS' test
```

Tests cover issue parsing, force layout convergence, node/edge visuals, kanban columns, font selection, file change parsing, Claude Code task parsing, color schemes, pane node tree operations, pane tree controller lifecycle, pane container view layout, palette resolution, foreground process detection, main window controller, terminal view model, terminal tab manager, session status, zoom-adaptive metrics, tmux protocol parsing, tmux layout parsing, tmux window lifecycle, tmux pane mapping, and tmux split routing.

## Status

Claide is feature-complete for its original scope: a GPU-accelerated terminal with Claude Code monitoring, tmux control mode, and a project visualization sidebar. Development is paused.

## License

MIT -- Copyright (c) Alexandru Geana (hexul)
