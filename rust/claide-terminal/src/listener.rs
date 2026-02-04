// ABOUTME: EventListener implementation that forwards alacritty_terminal events to Swift via callback.
// ABOUTME: Dispatches events through a C function pointer with opaque context.

use std::ffi::CString;
use std::os::raw::c_void;
use std::sync::Arc;
use std::sync::atomic::{AtomicPtr, Ordering};

use alacritty_terminal::event::{Event, EventListener};

/// Event types passed to the Swift callback.
#[repr(u32)]
pub enum ClaideEventType {
    Wakeup = 0,
    Title = 1,
    Bell = 2,
    ChildExit = 3,
    DirectoryChange = 4,
}

/// C function pointer type for event callbacks.
pub type ClaideEventCallback = extern "C" fn(
    context: *mut c_void,
    event_type: u32,
    // For Title/DirectoryChange: UTF-8 string. For ChildExit: exit code as string. Null otherwise.
    string_value: *const std::os::raw::c_char,
    int_value: i32,
);

/// Holds the callback function pointer and context for dispatching events to Swift.
pub struct Listener {
    callback: ClaideEventCallback,
    context: Arc<AtomicPtr<c_void>>,
}

// The context pointer is managed by Swift and is thread-safe (TerminalBridge is @Sendable).
unsafe impl Send for Listener {}
unsafe impl Sync for Listener {}

impl Listener {
    pub fn new(callback: ClaideEventCallback, context: *mut c_void) -> Self {
        Self {
            callback,
            context: Arc::new(AtomicPtr::new(context)),
        }
    }

    /// Fire a directory change event (from OSC 7 scanning).
    pub fn send_directory_change(&self, directory: &str) {
        let ctx = self.context.load(Ordering::Relaxed);
        if ctx.is_null() {
            return;
        }
        if let Ok(cstr) = CString::new(directory) {
            (self.callback)(ctx, ClaideEventType::DirectoryChange as u32, cstr.as_ptr(), 0);
        }
    }
}

impl Clone for Listener {
    fn clone(&self) -> Self {
        Self {
            callback: self.callback,
            context: Arc::clone(&self.context),
        }
    }
}

impl EventListener for Listener {
    fn send_event(&self, event: Event) {
        let ctx = self.context.load(Ordering::Relaxed);
        if ctx.is_null() {
            return;
        }

        match event {
            Event::Wakeup => {
                (self.callback)(ctx, ClaideEventType::Wakeup as u32, std::ptr::null(), 0);
            }
            Event::Title(title) => {
                if let Ok(cstr) = CString::new(title) {
                    (self.callback)(ctx, ClaideEventType::Title as u32, cstr.as_ptr(), 0);
                }
            }
            Event::Bell => {
                (self.callback)(ctx, ClaideEventType::Bell as u32, std::ptr::null(), 0);
            }
            Event::ChildExit(code) => {
                (self.callback)(
                    ctx,
                    ClaideEventType::ChildExit as u32,
                    std::ptr::null(),
                    code,
                );
            }
            // Events we don't forward to Swift.
            _ => {}
        }
    }
}
