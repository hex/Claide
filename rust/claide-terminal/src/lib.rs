// ABOUTME: Entry point for the claide-terminal static library.
// ABOUTME: Exposes C FFI functions for terminal emulation from Swift.

pub mod ffi;
pub mod grid_snapshot;
pub mod handle;
pub mod listener;
pub mod pty_reader;

/// Returns the library version as a packed integer (major * 10000 + minor * 100 + patch).
#[no_mangle]
pub extern "C" fn claide_terminal_version() -> u32 {
    0 * 10000 + 1 * 100 + 0 // 0.1.0
}
