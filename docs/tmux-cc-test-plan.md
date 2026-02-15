# tmux -CC Control Mode — Test Plan

## Prerequisites

- tmux installed (`/usr/bin/tmux` or `brew install tmux`)
- Claide built with current GhosttyKit (has `ghostty_surface_feed_output`)
- At least one terminal available outside Claide for running tmux commands

## Unit Tests (automated)

377 tests pass via `xcodebuild test`. Covers:

| Suite | Count | What |
|-------|-------|------|
| TmuxProtocolParser (8 suites) | ~30 | `%output` decoding, octal unescape, `%begin/%end` blocks, window/session notifications, exit, edge cases |
| TmuxKeyEncoder (2 suites) | 13 | Special key mapping (arrows, function keys, backspace), modifier prefixes (Ctrl, Alt, Shift combos) |
| TmuxLayoutParser (5 suites) | 9 | Single pane, horizontal/vertical splits, nested layouts, checksum stripping, allPaneIDs |
| TmuxWindowLifecycle (1 suite) | 9 | `parseWindowList` format, `parsePaneID`, edge cases |
| TmuxSessionList (1 suite) | 5 | `parseSessionList` format, attached flag, colons in names |

## Integration Tests (manual)

### 0. Setup

```bash
# Create a test tmux session in an external terminal
tmux new-session -s test-claide -d
tmux send-keys -t test-claide 'echo hello from tmux' Enter
```

### 1. Command Palette — Session Picker

1. Open Claide, press Cmd+P (command palette)
2. Type "tmux"
3. **Expect**: "tmux: Attach test-claide" item with subtitle "1 window"
4. **Expect**: "tmux: New Session" item at the bottom
5. If no tmux sessions exist, **expect** only "tmux: New Session"

### 2. Attach — Output Rendering

1. Select "tmux: Attach test-claide" from the palette
2. **Expect**: A new tab appears with the tmux session content
3. **Expect**: The "echo hello from tmux" output is visible in the terminal
4. **Expect**: Shell prompt is rendered (bash/zsh prompt)
5. **Expect**: Tab title shows "test-claide" or the tmux window name

### 3. Tab Badge

1. Look at the tab bar for the tmux-attached tab
2. **Expect**: Green split-pane icon (rectangle.split.3x1) instead of the normal shell icon
3. Non-tmux tabs should still show their normal process icon

### 4. Input Routing — Keyboard

1. In the tmux tab, type `ls -la` and press Enter
2. **Expect**: Command executes, output appears
3. Press arrow keys (up for history, left/right to move cursor)
4. **Expect**: Cursor moves correctly, command history works
5. Press Ctrl+C
6. **Expect**: Interrupt signal sent (cancels any running command)
7. Press Ctrl+D on empty prompt
8. **Expect**: Shell exits (tmux may close the pane)
9. Press Tab for completion
10. **Expect**: Tab completion works

### 5. Input Routing — Paste

1. Copy text to clipboard: `echo pasted successfully`
2. Press Cmd+V in the tmux tab
3. **Expect**: Text appears at the cursor position
4. Press Enter
5. **Expect**: Command executes with the pasted text
6. Right-click in the tmux tab (if paste-on-right-click enabled)
7. **Expect**: Clipboard text pasted

### 6. Window Lifecycle — New Window

1. In an external terminal: `tmux new-window -t test-claide`
2. **Expect**: New tab appears in Claide
3. In the external terminal: `tmux rename-window -t test-claide:1 'my-window'`
4. **Expect**: Tab title updates to "my-window"
5. In the external terminal: `tmux kill-window -t test-claide:1`
6. **Expect**: The corresponding Claide tab closes

### 7. Resize Sync

1. Resize the Claide window (drag edge)
2. In the tmux tab, run `tput cols; tput lines`
3. **Expect**: Values match the visible terminal dimensions
4. Resize again, re-run `tput cols; tput lines`
5. **Expect**: Updated values (debounced, ~100ms delay)

### 8. Split Panes (layout-change)

1. In an external terminal: `tmux split-window -t test-claide`
2. **Expect**: The tmux tab in Claide gains a second pane
3. In the external terminal: `tmux kill-pane -t test-claide:.1`
4. **Expect**: The split pane disappears from Claide

> Note: Claide-initiated splits create local panes, not tmux panes.
> Tmux splits must originate from tmux commands.

### 9. Detach

1. Open command palette (Cmd+P), type "tmux"
2. **Expect**: "tmux: Detach" item (not "Attach")
3. Select "tmux: Detach"
4. **Expect**: All tmux tabs close
5. **Expect**: A fresh local terminal tab is created if all tabs were tmux
6. **Expect**: Command palette now shows "tmux: Attach test-claide" again
7. The tmux session should still be alive: `tmux list-sessions` shows it

### 10. Disconnect Recovery

1. Attach to a tmux session in Claide
2. In an external terminal: `tmux kill-server`
3. **Expect**: All tmux tabs in Claide close
4. **Expect**: A fresh local tab appears
5. **Expect**: No crash, no hang

### 11. New Session (no pre-existing)

1. Kill all tmux sessions: `tmux kill-server`
2. Open command palette, select "tmux: New Session"
3. **Expect**: New tmux session created and attached
4. **Expect**: Tab appears with shell prompt
5. Verify: `tmux list-sessions` in external terminal shows the new session

## Edge Cases

| Scenario | Expected |
|----------|----------|
| Attach while already attached | No-op (guarded by `tmuxSession == nil`) |
| tmux not installed | Palette shows "New Session" (listSessions returns []) — attach fails silently, disconnect fires |
| Very long output (e.g., `cat /usr/share/dict/words`) | Renders without hang (output is chunked by tmux) |
| Unicode / emoji in tmux output | Renders correctly (Ghostty handles VT100 parsing) |
| Multiple Claide windows | Each window has independent tmux state |

## Known Limitations

- **Remote SSH** (`attachTmuxRemote`) exists in code but is not yet exposed in the command palette — needs a host input dialog
- **Claide-initiated splits** create local panes, not tmux panes. Only tmux-originated splits map correctly.
- **No search** in tmux panes (Ghostty's search API is not available in libghostty C bindings)
- **No mouse passthrough** to tmux (scroll, click-to-position) — keyboard only for now
