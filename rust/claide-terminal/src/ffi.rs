// ABOUTME: C-compatible FFI functions callable from Swift via the bridging header.
// ABOUTME: Wraps TerminalHandle operations behind opaque pointer and C types.

use std::ffi::CStr;
use std::os::raw::{c_char, c_void};
use std::slice;

use crate::grid_snapshot::ClaideGridSnapshot;
use crate::handle::TerminalHandle;
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

/// Resize the terminal and PTY.
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
