// ABOUTME: C-compatible FFI functions callable from Swift via the bridging header.
// ABOUTME: Wraps TerminalHandle operations behind opaque pointer and C types.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::slice;

use alacritty_terminal::index::Side;
use alacritty_terminal::selection::SelectionType;

use crate::grid_snapshot::ClaideGridSnapshot;
use crate::handle::{ClaideColorPalette, TerminalHandle};
use crate::listener::{ClaideEventCallback, Listener};

/// Opaque pointer type for the terminal handle.
pub type ClaideTerminalRef = *mut TerminalHandle;

/// Create a new terminal with a shell process.
///
/// # Safety
/// All string pointers must be valid, null-terminated UTF-8.
/// `env_keys` and `env_values` must be arrays of `env_count` valid C strings.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_create(
    executable: *const c_char,
    args: *const *const c_char,
    args_count: u32,
    env_keys: *const *const c_char,
    env_values: *const *const c_char,
    env_count: u32,
    working_dir: *const c_char,
    cols: u32,
    rows: u32,
    cell_width: u16,
    cell_height: u16,
    callback: ClaideEventCallback,
    context: *mut c_void,
) -> ClaideTerminalRef {
    let executable = match CStr::from_ptr(executable).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let mut args_vec: Vec<&str> = Vec::new();
    if !args.is_null() && args_count > 0 {
        let args_slice = slice::from_raw_parts(args, args_count as usize);
        for &arg in args_slice {
            match CStr::from_ptr(arg).to_str() {
                Ok(s) => args_vec.push(s),
                Err(_) => return std::ptr::null_mut(),
            }
        }
    }

    let mut env_vec: Vec<(&str, &str)> = Vec::new();
    if !env_keys.is_null() && !env_values.is_null() && env_count > 0 {
        let keys = slice::from_raw_parts(env_keys, env_count as usize);
        let values = slice::from_raw_parts(env_values, env_count as usize);
        for i in 0..env_count as usize {
            let key = match CStr::from_ptr(keys[i]).to_str() {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            let value = match CStr::from_ptr(values[i]).to_str() {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            env_vec.push((key, value));
        }
    }

    let working_dir = match CStr::from_ptr(working_dir).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let listener = Listener::new(callback, context);

    match TerminalHandle::new(
        executable,
        &args_vec,
        &env_vec,
        working_dir,
        cols,
        rows,
        cell_width,
        cell_height,
        listener,
    ) {
        Ok(handle) => Box::into_raw(Box::new(handle)),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Destroy a terminal handle, killing the shell and freeing all resources.
///
/// # Safety
/// `handle` must be a valid pointer returned by `claide_terminal_create`, or null.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_destroy(handle: ClaideTerminalRef) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Write raw bytes to the terminal's PTY.
///
/// # Safety
/// `handle` must be valid. `data` must point to `len` valid bytes.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_write(
    handle: ClaideTerminalRef,
    data: *const u8,
    len: u32,
) {
    if handle.is_null() || data.is_null() {
        return;
    }
    let bytes = slice::from_raw_parts(data, len as usize);
    let _ = (*handle).write(bytes);
}

/// Write a null-terminated UTF-8 string to the terminal's PTY.
///
/// # Safety
/// `handle` must be valid. `str_ptr` must be a valid null-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_write_str(
    handle: ClaideTerminalRef,
    str_ptr: *const c_char,
) {
    if handle.is_null() || str_ptr.is_null() {
        return;
    }
    if let Ok(s) = CStr::from_ptr(str_ptr).to_str() {
        let _ = (*handle).write(s.as_bytes());
    }
}

/// Resize the terminal grid and notify the shell (sends SIGWINCH).
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_resize(
    handle: ClaideTerminalRef,
    cols: u32,
    rows: u32,
    cell_width: u16,
    cell_height: u16,
) {
    if handle.is_null() {
        return;
    }
    (*handle).resize(cols, rows, cell_width, cell_height);
}

/// Resize the terminal grid without notifying the shell.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_resize_grid(
    handle: ClaideTerminalRef,
    cols: u32,
    rows: u32,
) {
    if handle.is_null() {
        return;
    }
    (*handle).resize_grid(cols, rows);
}

/// Resize the terminal grid without reflowing content or notifying the shell.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_resize_grid_no_reflow(
    handle: ClaideTerminalRef,
    cols: u32,
    rows: u32,
) {
    if handle.is_null() {
        return;
    }
    (*handle).resize_grid_no_reflow(cols, rows);
}

/// Notify the shell of the current window size (sends SIGWINCH).
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_notify_pty_size(
    handle: ClaideTerminalRef,
    cols: u32,
    rows: u32,
    cell_width: u16,
    cell_height: u16,
) {
    if handle.is_null() {
        return;
    }
    (*handle).notify_pty_size(cols, rows, cell_width, cell_height);
}

/// Take a snapshot of the visible terminal grid.
///
/// The returned pointer must be freed with `claide_terminal_snapshot_free`.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_snapshot(
    handle: ClaideTerminalRef,
) -> *mut ClaideGridSnapshot {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    Box::into_raw((*handle).snapshot())
}

/// Free a grid snapshot.
///
/// # Safety
/// `snapshot` must be a pointer returned by `claide_terminal_snapshot`, or null.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_snapshot_free(snapshot: *mut ClaideGridSnapshot) {
    crate::grid_snapshot::free_snapshot(snapshot);
}

/// Get the shell process ID.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_shell_pid(handle: ClaideTerminalRef) -> u32 {
    if handle.is_null() {
        return 0;
    }
    (*handle).shell_pid()
}

// -- Selection --

/// Start a selection at the given grid position.
///
/// `side`: 0 = Left, 1 = Right.
/// `sel_type`: 0 = Simple, 1 = Block, 2 = Semantic, 3 = Lines.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_selection_start(
    handle: ClaideTerminalRef,
    row: i32,
    col: u32,
    side: u8,
    sel_type: u8,
) {
    if handle.is_null() {
        return;
    }
    let side = if side == 0 { Side::Left } else { Side::Right };
    let ty = match sel_type {
        1 => SelectionType::Block,
        2 => SelectionType::Semantic,
        3 => SelectionType::Lines,
        _ => SelectionType::Simple,
    };
    (*handle).selection_start(row, col as usize, side, ty);
}

/// Update the selection endpoint.
///
/// `side`: 0 = Left, 1 = Right.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_selection_update(
    handle: ClaideTerminalRef,
    row: i32,
    col: u32,
    side: u8,
) {
    if handle.is_null() {
        return;
    }
    let side = if side == 0 { Side::Left } else { Side::Right };
    (*handle).selection_update(row, col as usize, side);
}

/// Clear the current selection.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_selection_clear(handle: ClaideTerminalRef) {
    if handle.is_null() {
        return;
    }
    (*handle).selection_clear();
}

/// Get the selected text as a null-terminated UTF-8 string.
///
/// Returns NULL if no selection exists. The caller must free the returned
/// string with `claide_terminal_selection_text_free`.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_selection_text(
    handle: ClaideTerminalRef,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    match (*handle).selection_text() {
        Some(text) => match CString::new(text) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        None => std::ptr::null_mut(),
    }
}

/// Free a string returned by `claide_terminal_selection_text`.
///
/// # Safety
/// `ptr` must be a pointer returned by `claide_terminal_selection_text`, or null.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_selection_text_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

// -- Scrollback --

/// Scroll the terminal viewport. Positive delta = scroll up (into history),
/// negative = down (toward live output).
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_scroll(
    handle: ClaideTerminalRef,
    delta: i32,
) {
    if handle.is_null() {
        return;
    }
    (*handle).scroll(delta);
}

// -- Search --

/// Start a search with the given query string. Searches forward from the cursor.
/// Returns true if a match was found.
///
/// # Safety
/// `handle` must be valid. `query` must be a valid null-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_search_set(
    handle: ClaideTerminalRef,
    query: *const c_char,
) -> bool {
    if handle.is_null() || query.is_null() {
        return false;
    }
    let query = match CStr::from_ptr(query).to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };
    (*handle).search_set(query)
}

/// Navigate to the next or previous search match.
/// `forward`: true = next match, false = previous match.
/// Returns true if a match was found.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_search_advance(
    handle: ClaideTerminalRef,
    forward: bool,
) -> bool {
    if handle.is_null() {
        return false;
    }
    (*handle).search_advance(forward)
}

/// Clear the current search and remove highlights.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_search_clear(handle: ClaideTerminalRef) {
    if handle.is_null() {
        return;
    }
    (*handle).search_clear();
}

// -- Colors --

/// Set the terminal's color palette.
///
/// # Safety
/// `handle` and `palette` must be valid pointers.
#[no_mangle]
pub unsafe extern "C" fn claide_terminal_set_colors(
    handle: ClaideTerminalRef,
    palette: *const ClaideColorPalette,
) {
    if handle.is_null() || palette.is_null() {
        return;
    }
    (*handle).set_colors(&*palette);
}
