// ABOUTME: Owns the terminal state, PTY file descriptor, and reader thread.
// ABOUTME: Provides methods for writing, resizing, and snapshotting the terminal.

use std::io::Write;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::JoinHandle;

use alacritty_terminal::grid::Dimensions;
use alacritty_terminal::index::{Column, Line, Point, Side};
use alacritty_terminal::selection::{Selection, SelectionType};
use alacritty_terminal::sync::FairMutex;
use alacritty_terminal::term::{Config, Term};

use crate::grid_snapshot::{self, ClaideGridSnapshot};
use crate::listener::Listener;
use crate::pty_reader;

/// Terminal dimensions for constructing the Term.
struct TermDimensions {
    cols: usize,
    lines: usize,
}

impl Dimensions for TermDimensions {
    fn total_lines(&self) -> usize {
        self.lines
    }
    fn screen_lines(&self) -> usize {
        self.lines
    }
    fn columns(&self) -> usize {
        self.cols
    }
}

/// Opaque handle owning all terminal state.
pub struct TerminalHandle {
    term: Arc<FairMutex<Term<Listener>>>,
    pty_master: OwnedFd,
    shell_pid: u32,
    reader_thread: Option<JoinHandle<()>>,
    shutdown: Arc<AtomicBool>,
}

impl TerminalHandle {
    /// Spawn a new shell process with a PTY and start the reader thread.
    pub fn new(
        executable: &str,
        args: &[&str],
        env: &[(&str, &str)],
        working_dir: &str,
        cols: u32,
        rows: u32,
        cell_width: u16,
        cell_height: u16,
        listener: Listener,
    ) -> Result<Self, String> {
        // Open PTY pair
        let pty_pair = rustix_openpty::openpty(None, None)
            .map_err(|e| format!("openpty failed: {}", e))?;

        let master_fd = pty_pair.controller;
        let slave_fd = pty_pair.user;

        // Set initial window size
        let winsize = rustix_openpty::rustix::termios::Winsize {
            ws_row: rows as u16,
            ws_col: cols as u16,
            ws_xpixel: cols as u16 * cell_width,
            ws_ypixel: rows as u16 * cell_height,
        };

        // Set window size on the slave PTY
        unsafe {
            libc::ioctl(slave_fd.as_raw_fd(), libc::TIOCSWINSZ, &winsize as *const _ as *const libc::c_void);
        }

        // Fork and exec the shell
        let pid = unsafe { libc::fork() };
        if pid < 0 {
            return Err("fork failed".into());
        }

        if pid == 0 {
            // Child process
            unsafe {
                // Create new session
                libc::setsid();

                // Set controlling terminal
                libc::ioctl(slave_fd.as_raw_fd(), libc::TIOCSCTTY as libc::c_ulong, 0);

                // Redirect stdio to PTY slave
                libc::dup2(slave_fd.as_raw_fd(), 0);
                libc::dup2(slave_fd.as_raw_fd(), 1);
                libc::dup2(slave_fd.as_raw_fd(), 2);

                // Close original fds
                drop(slave_fd);
                drop(master_fd);

                // Set working directory
                let dir = std::ffi::CString::new(working_dir).unwrap();
                libc::chdir(dir.as_ptr());

                // Set environment variables
                for (key, value) in env {
                    let k = std::ffi::CString::new(*key).unwrap();
                    let v = std::ffi::CString::new(*value).unwrap();
                    libc::setenv(k.as_ptr(), v.as_ptr(), 1);
                }

                // Build argv
                let exec_cstr = std::ffi::CString::new(executable).unwrap();
                let mut argv_cstrs: Vec<std::ffi::CString> = Vec::new();
                argv_cstrs.push(exec_cstr.clone());
                for arg in args {
                    argv_cstrs.push(std::ffi::CString::new(*arg).unwrap());
                }
                let mut argv_ptrs: Vec<*const libc::c_char> = argv_cstrs.iter().map(|s| s.as_ptr()).collect();
                argv_ptrs.push(std::ptr::null());

                libc::execvp(exec_cstr.as_ptr(), argv_ptrs.as_ptr());

                // If execvp returns, it failed
                libc::_exit(127);
            }
        }

        // Parent process — close slave fd
        drop(slave_fd);

        // Create the terminal emulator
        let dims = TermDimensions {
            cols: cols as usize,
            lines: rows as usize,
        };
        let config = Config::default();
        let term = Arc::new(FairMutex::new(Term::new(config, &dims, listener.clone())));

        let shutdown = Arc::new(AtomicBool::new(false));

        // Duplicate the master fd for the reader thread (we keep the original for writing)
        let reader_fd = unsafe { libc::dup(master_fd.as_raw_fd()) };
        if reader_fd < 0 {
            return Err("dup failed".into());
        }

        let term_clone = Arc::clone(&term);
        let shutdown_clone = Arc::clone(&shutdown);

        let reader_thread = std::thread::Builder::new()
            .name("pty-reader".into())
            .spawn(move || {
                pty_reader::run_reader(reader_fd, term_clone, listener, shutdown_clone);
                // Close the duplicated fd when done
                unsafe { libc::close(reader_fd); }
            })
            .map_err(|e| format!("Failed to spawn reader thread: {}", e))?;

        Ok(TerminalHandle {
            term,
            pty_master: master_fd,
            shell_pid: pid as u32,
            reader_thread: Some(reader_thread),
            shutdown,
        })
    }

    /// Write bytes to the PTY master (terminal input).
    pub fn write(&self, data: &[u8]) -> Result<(), String> {
        let mut file = unsafe { std::fs::File::from_raw_fd(self.pty_master.as_raw_fd()) };
        let result = file.write_all(data).map_err(|e| format!("write failed: {}", e));
        // Don't let File close the fd — OwnedFd owns it
        std::mem::forget(file);
        result
    }

    /// Resize the terminal grid without notifying the shell.
    pub fn resize_grid(&self, cols: u32, rows: u32) {
        let mut term = self.term.lock();
        let dims = TermDimensions {
            cols: cols as usize,
            lines: rows as usize,
        };
        term.resize(dims);
    }

    /// Resize the terminal grid without reflowing content or notifying the shell.
    /// Rows are truncated (shrink) or padded (grow) instead of being rewrapped.
    /// All internal state (scroll region, tabs, damage) is updated correctly.
    pub fn resize_grid_no_reflow(&self, cols: u32, rows: u32) {
        let mut term = self.term.lock();
        let dims = TermDimensions {
            cols: cols as usize,
            lines: rows as usize,
        };
        term.resize_no_reflow(dims);
    }

    /// Notify the shell of the current window size (sends SIGWINCH).
    pub fn notify_pty_size(&self, cols: u32, rows: u32, cell_width: u16, cell_height: u16) {
        let winsize = libc::winsize {
            ws_row: rows as u16,
            ws_col: cols as u16,
            ws_xpixel: cols as u16 * cell_width,
            ws_ypixel: rows as u16 * cell_height,
        };
        unsafe {
            libc::ioctl(self.pty_master.as_raw_fd(), libc::TIOCSWINSZ, &winsize);
        }
    }

    /// Resize the terminal grid and notify the shell.
    pub fn resize(&self, cols: u32, rows: u32, cell_width: u16, cell_height: u16) {
        self.resize_grid(cols, rows);
        self.notify_pty_size(cols, rows, cell_width, cell_height);
    }

    /// Take a snapshot of the visible grid.
    pub fn snapshot(&self) -> Box<ClaideGridSnapshot> {
        let term = self.term.lock();
        Box::new(grid_snapshot::take_snapshot(&term))
    }

    /// Get the shell process ID.
    pub fn shell_pid(&self) -> u32 {
        self.shell_pid
    }

    /// Start a new selection at the given grid position.
    pub fn selection_start(&self, row: i32, col: usize, side: Side, ty: SelectionType) {
        let mut term = self.term.lock();
        let point = Point::new(Line(row), Column(col));
        term.selection = Some(Selection::new(ty, point, side));
    }

    /// Update the selection endpoint.
    pub fn selection_update(&self, row: i32, col: usize, side: Side) {
        let mut term = self.term.lock();
        if let Some(ref mut selection) = term.selection {
            let point = Point::new(Line(row), Column(col));
            selection.update(point, side);
        }
    }

    /// Clear the current selection.
    pub fn selection_clear(&self) {
        let mut term = self.term.lock();
        term.selection = None;
    }

    /// Extract the selected text as a String.
    pub fn selection_text(&self) -> Option<String> {
        let term = self.term.lock();
        term.selection_to_string()
    }
}

impl Drop for TerminalHandle {
    fn drop(&mut self) {
        // Signal the reader thread to stop
        self.shutdown.store(true, Ordering::Relaxed);

        // The OwnedFd for pty_master will be closed when dropped,
        // which will cause the reader thread's read() to return EOF/error.

        if let Some(thread) = self.reader_thread.take() {
            let _ = thread.join();
        }
    }
}
