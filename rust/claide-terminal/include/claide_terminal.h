// ABOUTME: C header for the claide-terminal static library.
// ABOUTME: Declares FFI types and functions callable from Swift via bridging header.

#ifndef CLAIDE_TERMINAL_H
#define CLAIDE_TERMINAL_H

#include <stdint.h>
#include <stdbool.h>

// -- Opaque handle --

/// Opaque pointer to a Rust TerminalHandle.
typedef void *ClaideTerminalRef;

// -- Event types --

/// Event types sent from Rust to Swift via callback.
enum {
    ClaideEventWakeup          = 0,
    ClaideEventTitle           = 1,
    ClaideEventBell            = 2,
    ClaideEventChildExit       = 3,
    ClaideEventDirectoryChange = 4,
};

/// Callback function type for terminal events.
///
/// @param context  Opaque pointer passed to claide_terminal_create (the Swift TerminalBridge).
/// @param event_type  One of the ClaideEvent* constants.
/// @param string_value  UTF-8 string for Title/DirectoryChange events, NULL otherwise.
/// @param int_value  Exit code for ChildExit, 0 otherwise.
typedef void (*ClaideEventCallback)(
    void *context,
    uint32_t event_type,
    const char *string_value,
    int32_t int_value
);

// -- Grid snapshot types --

/// Per-cell data from the terminal grid.
///
/// Flag bits: BOLD=0x01, ITALIC=0x02, UNDERLINE=0x04, STRIKEOUT=0x08,
///            DIM=0x10, INVERSE=0x20, WIDE_CHAR=0x40, WIDE_SPACER=0x80,
///            HIDDEN=0x100, SELECTED=0x200
typedef struct {
    uint32_t codepoint;
    uint8_t fg_r, fg_g, fg_b;
    uint8_t bg_r, bg_g, bg_b;
    uint16_t flags;
} ClaideCellData;

/// Cursor state within the grid.
typedef struct {
    uint32_t row;
    uint32_t col;
    uint8_t shape;    // 0=Block, 1=Underline, 2=Beam, 3=Hidden
    bool visible;
} ClaideCursorInfo;

/// Complete snapshot of the visible terminal grid.
typedef struct {
    ClaideCellData *cells;  // rows * cols elements, row-major
    uint32_t rows;
    uint32_t cols;
    ClaideCursorInfo cursor;
    uint32_t mode_flags;
} ClaideGridSnapshot;

// -- Lifecycle --

/// Returns the library version as packed integer (major * 10000 + minor * 100 + patch).
uint32_t claide_terminal_version(void);

/// Create a terminal with a shell process.
///
/// @param executable    Path to shell binary (e.g. "/bin/zsh").
/// @param args          Array of argument strings (excluding argv[0]).
/// @param args_count    Number of elements in args.
/// @param env_keys      Array of environment variable names.
/// @param env_values    Array of environment variable values.
/// @param env_count     Number of environment variables.
/// @param working_dir   Initial working directory.
/// @param cols          Terminal width in columns.
/// @param rows          Terminal height in rows.
/// @param cell_width    Cell width in pixels.
/// @param cell_height   Cell height in pixels.
/// @param callback      Function to call when events occur.
/// @param context       Opaque pointer passed to the callback.
/// @return              Handle on success, NULL on failure.
ClaideTerminalRef claide_terminal_create(
    const char *executable,
    const char *const *args,
    uint32_t args_count,
    const char *const *env_keys,
    const char *const *env_values,
    uint32_t env_count,
    const char *working_dir,
    uint32_t cols,
    uint32_t rows,
    uint16_t cell_width,
    uint16_t cell_height,
    ClaideEventCallback callback,
    void *context
);

/// Destroy a terminal, kill the shell, and free all resources.
void claide_terminal_destroy(ClaideTerminalRef handle);

// -- Input --

/// Write raw bytes to the terminal's PTY.
void claide_terminal_write(ClaideTerminalRef handle, const uint8_t *data, uint32_t len);

/// Write a null-terminated UTF-8 string to the terminal's PTY.
void claide_terminal_write_str(ClaideTerminalRef handle, const char *str);

// -- Resize --

/// Resize the terminal grid and notify the shell (sends SIGWINCH).
void claide_terminal_resize(
    ClaideTerminalRef handle,
    uint32_t cols,
    uint32_t rows,
    uint16_t cell_width,
    uint16_t cell_height
);

/// Resize the terminal grid without notifying the shell.
void claide_terminal_resize_grid(
    ClaideTerminalRef handle,
    uint32_t cols,
    uint32_t rows
);

/// Notify the shell of the current window size (sends SIGWINCH).
void claide_terminal_notify_pty_size(
    ClaideTerminalRef handle,
    uint32_t cols,
    uint32_t rows,
    uint16_t cell_width,
    uint16_t cell_height
);

// -- State --

/// Take a snapshot of the visible terminal grid.
/// The returned pointer must be freed with claide_terminal_snapshot_free.
ClaideGridSnapshot *claide_terminal_snapshot(ClaideTerminalRef handle);

/// Free a grid snapshot.
void claide_terminal_snapshot_free(ClaideGridSnapshot *snapshot);

// -- Info --

/// Get the shell process ID.
uint32_t claide_terminal_shell_pid(ClaideTerminalRef handle);

// -- Selection --

/// Selection side constants.
enum {
    ClaideSideLeft  = 0,
    ClaideSideRight = 1,
};

/// Selection type constants.
enum {
    ClaideSelectionSimple   = 0,
    ClaideSelectionBlock    = 1,
    ClaideSelectionSemantic = 2,
    ClaideSelectionLines    = 3,
};

/// Start a selection at the given grid position.
///
/// @param handle    Valid terminal handle.
/// @param row       Grid row (0-based from top of visible area).
/// @param col       Grid column (0-based).
/// @param side      ClaideSideLeft or ClaideSideRight (which half of the cell).
/// @param sel_type  ClaideSelection* constant.
void claide_terminal_selection_start(
    ClaideTerminalRef handle,
    int32_t row,
    uint32_t col,
    uint8_t side,
    uint8_t sel_type
);

/// Update the selection endpoint as the mouse moves.
void claide_terminal_selection_update(
    ClaideTerminalRef handle,
    int32_t row,
    uint32_t col,
    uint8_t side
);

/// Clear the current selection.
void claide_terminal_selection_clear(ClaideTerminalRef handle);

/// Get the selected text as a null-terminated UTF-8 string.
/// Returns NULL if no selection exists.
/// The caller must free the returned string with claide_terminal_selection_text_free.
char *claide_terminal_selection_text(ClaideTerminalRef handle);

/// Free a string returned by claide_terminal_selection_text.
void claide_terminal_selection_text_free(char *ptr);

#endif // CLAIDE_TERMINAL_H
