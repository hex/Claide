# tmux Pane Expansion Plan

## Overview

Expand Claide's tmux integration from read-only session attachment to full
bidirectional pane management, including native splits, session browsing,
and remote connectivity via SSH and mosh.

## Current State

Claide's tmux control mode (`tmux -CC`) handles:
- Attaching to existing sessions, displaying panes via `%output` → `feedOutput()`
- Input interception (keyboard → `send-keys`, paste → `send-keys -l`)
- Resize sync (debounced `resize-pane` on grid size changes)
- Layout sync on `%layout-change` with pane diffing
- Window lifecycle (create, close, rename)
- Initial content via `capture-pane -p -e`
- Disconnect recovery with graceful cleanup

Key limitation: Claide-initiated splits create local panes, NOT tmux panes.
The integration is effectively one-way (tmux → Claide) for pane topology.

---

## Phase 1: tmux-Native Splits

**Goal**: When a user splits a pane that belongs to a tmux session, create a
tmux pane via `split-window` instead of a local Claide pane.

### Why This Matters

Without this, splits made in Claide are lost on detach/reattach. The user
expects that if they're in a tmux session, their layout is persistent. This
is the single most impactful gap in the current integration.

### Implementation Approach

1. **Detect tmux context on split**: `PaneTreeController.split()` checks if the
   active pane belongs to a tmux session (via `TerminalTabManager.tmuxPaneMap`).

2. **Route to tmux**: Instead of local `PaneNode.split()`, send
   `split-window -t %<pane-id> [-h|-v]` through `TmuxControlChannel`.

3. **Let tmux drive layout**: The `split-window` triggers a `%layout-change`
   notification. The existing layout parser + pane differ already handles this —
   it will detect the new pane and create the corresponding GhosttyTerminalView.

4. **Suppress local tree mutation**: The split action becomes async — the local
   tree doesn't change immediately. It updates when `%layout-change` arrives.

### Edge Cases

- **Split direction mapping**: Claide's horizontal/vertical must map correctly to
  tmux's `-h` (horizontal = side-by-side) and `-v` (vertical = stacked).
  tmux's naming is inverted from what most people expect.
- **Focus after split**: tmux automatically focuses the new pane. The
  `%window-pane-changed` notification should drive Claide's `activePaneID`.
- **Resize race**: The new pane may trigger resize events before registration.
  The existing `pendingOutput` buffering should handle this.

### Acceptance Criteria

- Split a tmux pane in Claide → detach → reattach → layout preserved
- Both horizontal and vertical splits work
- Close a tmux pane in Claide → tmux pane dies → layout reflows
- Focus follows tmux's active pane after split

---

## Phase 2: tmux Session Browser

**Goal**: A panel showing all tmux sessions, windows, and panes on the system.
Click to attach, context menu to rename/kill.

### Why This Matters

Currently, attaching to tmux requires the command palette. A visual browser
makes tmux sessions discoverable and manageable, especially when juggling
multiple projects.

### Implementation Approach

1. **Data source**: Periodic `tmux list-sessions -F` / `list-windows -F` /
   `list-panes -F` via shell subprocess (NOT through a control mode connection,
   since we may not be attached yet).

2. **UI location**: New panel in the existing sidebar (`MainSplitViewController`
   sidebar area), alongside the graph and file log panels.

3. **Tree structure**: Sessions → Windows → Panes, with metadata:
   - Session: name, attached clients count, created time
   - Window: name, index, active flag, layout description
   - Pane: title, current command, pid, dimensions

4. **Actions**:
   - Click session/window → attach via `tmux -CC attach -t <target>`
   - Right-click → rename, kill, create new window
   - Detach button on attached sessions

5. **Live updates**: While browsing, poll every 5s. Once attached, the control
   channel notifications keep things current.

### Acceptance Criteria

- Lists all local tmux sessions with their windows and panes
- Single-click attaches to a session in a new tab
- Sessions created/destroyed elsewhere appear within 5 seconds
- Kill session from browser → session dies, browser updates

---

## Phase 3: Remote tmux (SSH)

**Goal**: Connect to a remote host via SSH, start or attach `tmux -CC`, and
get native Claide panes backed by remote tmux.

### Why This Matters

This is the killer differentiator — iTerm2's most beloved tmux feature. Work on
a remote server with native local panes, scrollback, and copy/paste. Disconnect
your laptop, reconnect later, everything is still there.

### Implementation Approach

1. **Connection setup**: SSH subprocess via `Process`:
   ```
   ssh -t user@host tmux -CC new-session -A -s claide
   ```
   The `-A` flag attaches to existing session named "claide" or creates one.

2. **PTY requirement**: SSH needs a TTY (like local tmux -CC). Reuse the same
   PTY-based Process pattern from `TmuxControlChannel`.

3. **Protocol reuse**: Once SSH connects and tmux -CC starts, the stdout stream
   is identical to local tmux -CC. The existing `TmuxProtocolParser` works
   unchanged.

4. **Host management UI**: Dialog for entering host, user, port, identity file.
   Store recent connections (NOT passwords — rely on SSH keys / ssh-agent).

5. **Connection state**: Track connection health. SSH disconnects are more common
   than local tmux crashes. Show reconnect UI, attempt auto-reconnect with
   backoff.

### Edge Cases

- **Latency**: Remote `%output` may lag. Don't debounce output display (it's
  already frame-buffered by the 60fps render timer).
- **Resize propagation**: `resize-pane` commands travel over SSH. Debouncing
  is more important here (current 100ms debounce may need tuning).
- **SSH auth failures**: Surface error clearly. Don't retry auth in a loop.
- **Host key verification**: Respect `~/.ssh/known_hosts`. Show the fingerprint
  dialog if unknown host.
- **Bandwidth**: Large terminal output over slow links. tmux's flow control
  (`%pause` / `%continue`) is already parsed — need to implement the response.

### Acceptance Criteria

- SSH to a remote host → tmux panes appear as native Claide panes
- Disconnect SSH → panes show "disconnected" state
- Reconnect → panes restore with current content
- SSH key auth works (password auth is stretch goal)

---

## Phase 4: Remote tmux over Mosh

**Goal**: Use mosh instead of SSH as the transport layer for remote tmux -CC,
providing roaming and intermittent connectivity support.

### Why This Matters

SSH connections die when you change networks, close your laptop lid, or hit a
long period of packet loss. Mosh (Mobile Shell) uses UDP + SSP (State
Synchronization Protocol) to maintain sessions across IP changes, sleep/wake
cycles, and high-latency links. For remote tmux, this means true
"always connected" behavior.

### How Mosh Works (Relevant to Our Integration)

- Mosh authenticates via SSH initially, then switches to UDP (port 60000-61000)
- `mosh-server` runs on the remote host, `mosh-client` runs locally
- Mosh does NOT provide a raw byte stream like SSH — it runs a remote terminal
  emulator and syncs screen state via SSP
- This is a problem: mosh's local prediction and screen diffing will interfere
  with tmux -CC's raw protocol output

### The Mosh + tmux -CC Challenge

Mosh was designed for interactive terminal use, not protocol tunneling. The
standard `mosh user@host -- tmux -CC attach` approach has issues:

1. **Mosh interprets control sequences**: Mosh runs its own VTE on the remote
   side and diffs screen state. tmux -CC output (`%begin`, `%output`, etc.) gets
   processed as terminal output by mosh-server's parser, which corrupts the
   protocol stream.

2. **Local prediction**: Mosh echoes keystrokes locally before server confirms.
   This would double-echo tmux commands in the control channel.

### Approach A: Mosh as Transport, tmux -CC over Side Channel

Use mosh for the resilient connection, but tunnel the tmux -CC protocol through
a separate channel:

1. **Establish mosh connection** to the remote host (for resilience)
2. **Inside the mosh session**, start a TCP/Unix socket listener that bridges to
   `tmux -CC`:
   ```
   socat TCP-LISTEN:12345,reuseaddr EXEC:"tmux -CC attach -t claide"
   ```
3. **SSH port-forward** (or mosh's future UDP tunnel) to connect Claide's
   `TmuxProtocolParser` to that socket
4. Mosh handles reconnection; the socket bridge restarts automatically

**Pros**: Clean protocol separation. tmux -CC stream is byte-exact.
**Cons**: Requires socat or similar on remote. Extra socket setup complexity.

### Approach B: Mosh for Resilience, SSH for tmux -CC

Simpler hybrid approach:

1. Use mosh conceptually — but actually use **SSH with autossh/ServerAliveInterval**
   for the tmux -CC channel
2. Use mosh's reconnection idea but implement it ourselves:
   - SSH connects, starts `tmux -CC attach`
   - On disconnect, auto-reconnect SSH and re-attach
   - tmux preserves session state; `capture-pane` restores content

**Pros**: No remote-side dependencies beyond tmux and sshd. Works today.
**Cons**: Not true mosh — reconnection has a gap (seconds, not seamless).

### Approach C: Mosh with `-n` (No Terminal) + Direct tmux Socket

Mosh 1.4+ discussion includes a `--no-term` / raw pipe mode that would pass
bytes through without terminal interpretation. If this lands:

1. `mosh --no-term user@host -- tmux -CC attach -t claide`
2. Raw byte stream, mosh handles UDP reconnection
3. Claide's `TmuxProtocolParser` sees clean protocol

**Pros**: Best of both worlds.
**Cons**: Depends on upstream mosh feature that may not ship soon.

### Recommended Approach

Start with **Approach B** (SSH reconnection with tmux persistence) as it
requires zero remote-side setup beyond tmux + sshd. Implement as:

1. Wrap the SSH connection in an auto-reconnect loop with exponential backoff
2. On reconnect, `tmux -CC attach` re-sends `%layout-change` and we rebuild
3. Add visual indicator (e.g., yellow status) during reconnection gap
4. If actual `mosh --no-term` support materializes, swap the transport layer —
   the protocol handling above it stays identical

Research **Approach A** (socat bridge) as a power-user option for those who need
true UDP resilience and have socat available.

### Acceptance Criteria

- SSH disconnect → auto-reconnect within 5 seconds on same network
- Network change (WiFi → cellular) → reconnect within 30 seconds
- Laptop sleep/wake → reconnect and restore pane content
- Visual indicator during reconnection (not just frozen panes)
- Configurable: SSH reconnect (default) vs mosh bridge (opt-in)

---

## Phase 5: tmux Pane Inspector (Stretch)

**Goal**: A lightweight non-terminal pane showing metadata about the attached
tmux session — pane PIDs, current commands, environment, directories.

### Implementation Notes

- Data from `list-panes -F '#{pane_pid} #{pane_current_command} #{pane_current_path}'`
- Lightweight SwiftUI view in sidebar
- Refreshes on `%layout-change` and every 10 seconds
- Useful for debugging and for understanding what's running where

---

## Dependency Graph

```
Phase 1 (native splits)  ─── no dependencies, can start immediately
Phase 2 (session browser) ─── no dependencies, can start immediately
Phase 3 (remote SSH)      ─── benefits from Phase 1 (remote splits)
Phase 4 (remote mosh)     ─── depends on Phase 3 (SSH transport)
Phase 5 (inspector)       ─── benefits from Phase 2 (sidebar pattern)
```

Phases 1 and 2 are independent and can be developed in parallel.
Phase 3 is the critical path to Phase 4.

## Open Questions

1. **Mouse passthrough**: Should we implement mouse event forwarding to tmux?
   (Currently keyboard-only.) This affects all phases.
2. **tmux minimum version**: What's the oldest tmux version we support?
   Flow control (`%pause`/`%continue`) requires tmux 3.2+.
3. **Authentication for remote**: SSH key only? Or also support password auth
   (requires pseudo-terminal interaction with ssh)?
4. **Mosh availability**: Should we bundle mosh-client, or require the user to
   install it? (`brew install mosh`)
