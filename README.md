<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Claide icon">
</p>

# Claide

[claide.hexul.com](https://claide.hexul.com)

A GPU-accelerated macOS terminal emulator built with Swift, Metal, and Rust. Uses [alacritty_terminal](https://crates.io/crates/alacritty_terminal) for VT emulation and a custom Metal pipeline for rendering. Includes a project visualization sidebar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions.

Version 2026.2.4 | macOS 14.0+ | Swift 6.0 | MIT License

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

- **3-pass Metal rendering**: Background quads, R8 text glyphs, RGBA8 emoji — driven by CVDisplayLink
- **Dual glyph atlas**: 2048x2048 R8 for text + 2048x2048 RGBA8 for emoji, shelf-packed with Core Text rasterization
- **Tabs and splits**: Multiple tabs, horizontal/vertical pane splits, pane zoom
- **Session persistence**: Saves and restores tabs, splits, and working directories
- **9 color schemes**: Hexed, Dracula, Nord, Catppuccin Frappe, One Dark, Gruvbox Dark, Tokyo Night, Solarized Dark, Solarized Light
- **Emoji**: Full emoji support including ZWJ sequences, via `CTFontCreateForString` font fallback
- **Search**: In-terminal text search with match highlighting
- **URL detection**: Clickable URLs
- **IME**: Full `NSTextInputClient` implementation (marked text, candidate window)
- **Process icons**: Recognizes 40+ executables in the tab bar
- **Claude Code integration**: Context usage tracking via process tree walk + JSONL transcript parsing

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

## Architecture

Two layers — a Rust terminal backend and a Swift/Metal rendering frontend — connected by a C FFI boundary.

### Rust Backend

The `claide-terminal` crate (`rust/claide-terminal/`) owns terminal emulation, PTY management, and grid state.

**Core structure**: `TerminalHandle` owns an `Arc<FairMutex<Term<Listener>>>`, an `OwnedFd`, a reader thread, and per-instance state (palette, search results, grid cache).

**PTY creation**: Direct `fork()`+`execvp()` (not `posix_spawn`).

**Reader thread** (`pty_reader.rs`): Blocking read followed by a `poll()` drain loop that batches up to 1MB of data, then acquires the terminal lock once to feed the entire batch through the VTE parser. An OSC 7 byte-level scanner extracts directory changes during the read loop without waiting for full VTE processing.

**FairMutex**: Dual `parking_lot` mutex pattern that prevents the reader thread from starving the main thread (or vice versa) during heavy output.

**22 FFI functions** (`ffi.rs`): create, destroy, write (2), resize (4), snapshot (2), selection (5), search (3), scroll, row_text, free_string, shell_pid, set_colors, version.

**Damage-based incremental snapshots** (`grid_snapshot.rs`): A `PersistentGrid` caches per-row data and only reprocesses rows the VTE parser has marked as damaged. Output uses a sparse cell format — blank cells with default background are skipped entirely, reducing data transferred across the FFI boundary. Each cell carries:
- Glyph codepoint, foreground/background colors (resolved from Named/Indexed/RGB via per-instance palette)
- Flags (bold, italic, underline, strikethrough, inverse)
- `extra_offset`/`extra_count` for multi-codepoint sequences (emoji ZWJ)

**Dependencies**: alacritty_terminal 0.25.1 (patched: adds `resize_no_reflow()` for powerline-safe resizing), vte 0.15, libc 0.2, rustix-openpty 0.2.

### Swift/Metal Frontend

```
MetalTerminalView (NSView + CAMetalLayer)
  -> CVDisplayLink render loop (needsRedraw flag)
  -> GridRenderer: snapshot -> per-cell instance buffers
  -> 3-pass Metal draw:
       1. Background quads (instanced)
       2. R8 text glyphs (alpha-blended)
       3. RGBA8 emoji (premultiplied alpha)
```

**Dual atlas**: Two shelf-packed 2048x2048 atlases — R8 (single-channel) for text glyphs, RGBA8 (4-channel) for emoji. Text uses Core Text with `CGContextSetFontSmoothingStyle` for dark-background rendering. Emoji uses premultiplied alpha compositing.

**Instance buffer strategy**: Buffers are built in heap-allocated arrays, then bulk `memcpy`'d into Metal `storageModeShared` buffers. Direct indexed writes to shared-mode Metal memory are 15-20% slower due to write-combining/uncached memory semantics.

**Wakeup coalescing**: `os_unfair_lock`-based coalescing (macOS 14.0 target precludes `Synchronization.Atomic`).

**Window**: Chromeless `NSWindow` with repositioned traffic lights and a custom tab bar.

### Pane System

`PaneNode` is an immutable N-ary tree for split layouts with functional mutations. `PaneTreeController` manages the tree lifecycle. `PaneSplitView` and `PaneContainerView` handle the recursive NSView hierarchy for rendering splits.

### View Models

| ViewModel | Drives | Data Source |
|---|---|---|
| `TerminalViewModel` | Status bar, directory tracking | TerminalBridge event callbacks |
| `GraphViewModel` | Board + Graph views, force layout | BeadsService or ClaudeTaskService |
| `FileLogViewModel` | File change list | `changes.md` via FileWatcher |
| `SessionStatusViewModel` | Context usage bar | Claude Code JSONL transcripts |

## Performance

Claide is competitive with Alacritty and Ghostty on `cat`-throughput benchmarks. A benchmark script (`tools/termbench.sh`) tests sequential text, dense ASCII, ANSI colors, and Unicode throughput across terminals.

Key factors:

- **Rust opt-level**: Dev builds use `opt-level = 2` (not the default 0). VTE parsing is 5-7x faster with optimization — millions of small method calls need inlining.
- **Release profile**: `opt-level = 3`, thin LTO, `codegen-units = 1`. Debug lib: 48MB. Release lib: 3.6MB.
- **Batched PTY reads**: Up to 1MB per lock acquisition via `poll()` loop, minimizing lock contention.
- **Sparse snapshots**: Only damaged rows are reprocessed; blank cells are skipped entirely.
- **Heap-to-GPU memcpy**: Instance buffers built in cached heap memory, avoiding the write-combining penalty of direct Metal shared-buffer writes.

## Build

### Requirements

- macOS 14.0+
- Xcode (Swift 6.0)
- [Rust toolchain](https://rustup.rs/) 1.85.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [beads](https://github.com/hex/beads) (`bd` CLI) for issue tracking sidebar (optional; falls back to Claude Code tasks)

### Debug

```bash
xcodegen generate
xcodebuild -scheme Claide -destination 'platform=macOS' build
```

Or open `Claide.xcodeproj` in Xcode after generating.

The Rust library is built automatically by a pre-build script phase. Dev builds use `opt-level = 2` for acceptable VTE throughput.

### Release

```bash
scripts/release.sh
```

The release script handles archiving, code signing (Developer ID), notarization, DMG creation, Sparkle EdDSA signing, and GitHub Release publishing. See `scripts/release.sh` for details.

## Project Structure

```
Claide/
  ClaideApp.swift                # Entry point, NSApplicationDelegateAdaptor, Sparkle updater
  AppDelegate.swift              # App lifecycle, window restoration
  ContentView.swift              # Root layout
  MainWindowController.swift     # Window chrome, traffic light positioning
  MainSplitViewController.swift  # Terminal/sidebar split
  Theme.swift                    # Colors, fonts, spacing tokens
  Palette.swift                  # Color palette utilities
  FontSelection.swift            # Monospaced font enumeration
  NodeVisuals.swift              # Graph node rendering properties
  EdgeVisuals.swift              # Graph edge rendering properties
  KanbanColumn.swift             # Kanban column layout
  BridgingHeader.h               # Rust C FFI header imports
  Updates/
    CheckForUpdatesView.swift    # "Check for Updates..." menu item (Sparkle)
  Models/
    Issue.swift                  # Shared issue model
    IssueDependency.swift        # Dependency edges
    FileChange.swift             # Change log entry
    SessionStatus.swift          # Claude Code context usage
    TerminalColorScheme.swift    # 9 built-in color schemes
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
      MetalTerminalView.swift    # NSView + CAMetalLayer, keyboard/mouse input
      TerminalBridge.swift       # Swift wrapper over Rust C FFI
      GlyphAtlas.swift           # Core Text -> MTLTexture shelf-packed atlas
      GridRenderer.swift         # Snapshot -> Metal instance buffers
      TerminalShaders.metal      # Vertex + fragment shaders (3 passes)
      TerminalPanel.swift        # NSViewRepresentable host
      TerminalTabBar.swift       # Tab strip with add/close
      TerminalTabManager.swift   # Tab lifecycle, shell spawning
      TerminalTheme.swift        # Terminal color palette
      TerminalProfile.swift      # Per-terminal configuration
      TerminalSearchBar.swift    # In-terminal search UI
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
rust/
  build-universal.sh         # Build script (debug/release via CONFIGURATION)
  Cargo.toml                 # Workspace manifest with patched alacritty_terminal
  claide-terminal/
    include/
      claide_terminal.h      # C header declaring FFI types and functions
    src/
      lib.rs                     # Crate root
      ffi.rs                     # 22 C ABI entry points
      handle.rs                  # PTY fork/exec, Term creation, palette
      pty_reader.rs              # Reader thread: PTY -> VTE parser
      listener.rs                # Event dispatch to Swift callbacks
      grid_snapshot.rs           # Damage-based incremental snapshots
  patches/                   # Patched alacritty_terminal crate
scripts/
  release.sh                 # Signed, notarized DMG build + Sparkle signing
tools/
  termbench.sh               # Terminal throughput benchmark
ClaideTests/                 # Unit and integration tests
project.yml                  # XcodeGen spec
appcast.xml                  # Sparkle update feed
```

## Updates

In-app update checking via [Sparkle](https://sparkle-project.org/). The "Check for Updates..." menu item appears in the Claide menu. Updates are distributed as signed DMGs and verified with EdDSA signatures. The appcast is hosted in this repository and served via `raw.githubusercontent.com`.

## Tests

```bash
xcodebuild -scheme Claide -destination 'platform=macOS' test
```

Tests cover issue parsing, force layout convergence, node/edge visuals, kanban columns, font selection, file change parsing, Claude Code task parsing, terminal color schemes, pane node tree operations, pane tree controller lifecycle, pane container view layout, palette resolution, foreground process detection, main window controller, terminal view model, terminal tab manager, session status, and zoom-adaptive metrics.

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

## License

MIT -- Copyright (c) Alexandru Geana (hexul)
