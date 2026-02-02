<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Claide icon">
</p>

# Claide

A macOS companion app for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions. Provides a terminal, issue tracker visualization, and live file change monitoring in a single window.

<p align="center">
  <img src="docs/screenshot.png" width="720" alt="Claide screenshot">
</p>

## Requirements

- macOS 14.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [beads](https://github.com/hex/beads) (`bd` CLI) for issue tracking

## Build

```
cd Claide
xcodegen generate
xcodebuild -scheme Claide -destination 'platform=macOS' build
```

Or open `Claide.xcodeproj` in Xcode after generating.

## Layout

```
+---------------------------+----------------+
|                           | BOARD | GRAPH  |
|  Terminal                 |----------------|
|  (zsh, full environment)  |  Issue view    |
|                           |  (switchable)  |
|                           |----------------|
|                           |  FILES         |
|                           |  (always on)   |
+---------------------------+----------------+
```

The window is split horizontally: terminal on the left (~65%), sidebar on the right (~35%). The sidebar has two sections:

- **Top**: Board and Graph tabs (switchable)
- **Bottom**: File change log (always visible, ~30% height)

## Features

### Terminal

Embedded terminal via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). Launches `/bin/zsh -l` with full environment (homebrew paths, OSC 7 directory tracking). Custom font selection available in Settings.

### Board

Kanban-style view with four columns: Open, Active, Blocked, Done. Cards show title, priority, type, owner, and dependency count. Data comes from `bd list --json` (beads issue tracker).

### Graph

Interactive force-directed dependency graph rendered on a SwiftUI Canvas. Supports pan, zoom (scroll wheel + trackpad pinch), node dragging, and click-to-select with 2-hop neighbor highlighting. Zoom-adaptive detail: text, badges, and info rows fade in/out at different scale thresholds.

### Files

Live file change monitor. Watches `changes.md` (written by `cs` session hooks on every Claude Write/Edit tool call) using a GCD DispatchSource. Each entry shows timestamp, tool type (Write/Edit), filename, and path.

## Architecture

MVVM with three view models:

| ViewModel | Drives | Data Source |
|---|---|---|
| `TerminalViewModel` | Terminal status bar, directory tracking | SwiftTerm delegate callbacks |
| `GraphViewModel` | Board + Graph views, force layout | `bd list --json` via BeadsService |
| `FileLogViewModel` | File change list | `changes.md` via FileWatcher |

### Project Structure

```
Claide/
  ClaideApp.swift          # Entry point, window configuration
  ContentView.swift        # Root HSplitView + sidebar VSplitView
  Theme.swift              # Colors, fonts, spacing tokens
  Models/
    Issue.swift            # Beads issue model
    IssueDependency.swift  # Edge between issues
    FileChange.swift       # Parsed change log entry
  ViewModels/
    GraphViewModel.swift   # Issues, positions, force layout
    FileLogViewModel.swift # File watcher + parser
    TerminalViewModel.swift
  Views/
    Graph/GraphPanel.swift # Canvas-based dependency graph
    Kanban/KanbanPanel.swift
    FileLog/FileLogPanel.swift
    Terminal/TerminalPanel.swift
    SettingsView.swift     # Font picker
  Services/
    BeadsService.swift     # Runs bd CLI, decodes JSON
    FileWatcher.swift      # GCD DispatchSource file monitor
  Assets.xcassets/         # App icon
ClaideTests/               # 93 tests across 10 suites
project.yml                # XcodeGen spec
```

## Vision

Claide is a personal dashboard for working alongside Claude Code. The terminal is the primary workspace; everything else exists to provide context without switching windows.

Near-term:
- Issue creation and status updates directly from the sidebar
- Drag-and-drop between kanban columns (dispatches `bd update` under the hood)
- Graph edge labels and filtering by dependency type
- Session history: switch between multiple `cs` sessions

Longer-term:
- Watch `bd` output for real-time issue updates (same pattern as FileWatcher)
- Searchable file change log with path filtering
- Multiple terminal tabs

## Tests

```
xcodebuild -scheme Claide -destination 'platform=macOS' test
```

93 tests covering issue parsing, force layout convergence, node/edge visuals, kanban column assignment, font selection, file change parsing, and zoom-adaptive metrics.

## License

Private.
