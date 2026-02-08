// ABOUTME: Owns the terminal state, PTY file descriptor, and reader thread.
// ABOUTME: Provides methods for writing, resizing, and snapshotting the terminal.

use std::io::Write;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::JoinHandle;

use alacritty_terminal::grid::{Dimensions, Scroll};
use alacritty_terminal::index::{Column, Direction, Line, Point, Side};
use alacritty_terminal::selection::{Selection, SelectionType};
use alacritty_terminal::term::cell::Flags;
use alacritty_terminal::sync::FairMutex;
use alacritty_terminal::term::search::{Match, RegexSearch};
use alacritty_terminal::term::{Config, Term};
use alacritty_terminal::vte::ansi::Rgb;

use crate::grid_snapshot::{self, ClaideGridSnapshot, DEFAULT_ANSI, DEFAULT_BG, DEFAULT_FG};
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

/// Per-instance color palette: 16 ANSI colors + default foreground/background.
pub struct ColorPalette {
    pub ansi: [Rgb; 16],
    pub fg: Rgb,
    pub bg: Rgb,
}

impl Default for ColorPalette {
    fn default() -> Self {
        Self {
            ansi: DEFAULT_ANSI,
            fg: DEFAULT_FG,
            bg: DEFAULT_BG,
        }
    }
}

/// C-compatible palette struct for FFI.
#[repr(C)]
pub struct ClaideColorPalette {
    pub ansi: [u8; 48], // 16 colors x 3 bytes (r, g, b)
    pub fg_r: u8,
    pub fg_g: u8,
    pub fg_b: u8,
    pub bg_r: u8,
    pub bg_g: u8,
    pub bg_b: u8,
}

/// Search state for terminal find-in-buffer.
struct SearchState {
    regex: Option<RegexSearch>,
    current_match: Option<Match>,
}

/// Opaque handle owning all terminal state.
pub struct TerminalHandle {
    term: Arc<FairMutex<Term<Listener>>>,
    pty_master: OwnedFd,
    shell_pid: u32,
    reader_thread: Option<JoinHandle<()>>,
    shutdown: Arc<AtomicBool>,
    palette: FairMutex<ColorPalette>,
    search: FairMutex<SearchState>,
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
            palette: FairMutex::new(ColorPalette::default()),
            search: FairMutex::new(SearchState {
                regex: None,
                current_match: None,
            }),
        })
    }

    /// Replace the color palette from a C-compatible struct.
    pub fn set_colors(&self, c_palette: &ClaideColorPalette) {
        let mut palette = self.palette.lock();
        for i in 0..16 {
            palette.ansi[i] = Rgb {
                r: c_palette.ansi[i * 3],
                g: c_palette.ansi[i * 3 + 1],
                b: c_palette.ansi[i * 3 + 2],
            };
        }
        palette.fg = Rgb { r: c_palette.fg_r, g: c_palette.fg_g, b: c_palette.fg_b };
        palette.bg = Rgb { r: c_palette.bg_r, g: c_palette.bg_g, b: c_palette.bg_b };
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

    /// Take a snapshot of the visible grid using the current palette.
    pub fn snapshot(&self) -> Box<ClaideGridSnapshot> {
        let term = self.term.lock();
        let palette = self.palette.lock();
        let search = self.search.lock();
        Box::new(grid_snapshot::take_snapshot(&term, &palette, search.current_match.as_ref()))
    }

    /// Extract text for a single visible row, reading directly from the grid.
    pub fn row_text(&self, row: u32) -> Option<String> {
        let term = self.term.lock();
        let grid = term.grid();
        let rows = grid.screen_lines();
        let cols = grid.columns();
        let display_offset = grid.display_offset();

        if row as usize >= rows {
            return None;
        }

        let line = Line((row as i32) - (display_offset as i32));
        let grid_row = &grid[line];
        let mut text = String::with_capacity(cols);

        for col_idx in 0..cols {
            let cell = &grid_row[Column(col_idx)];
            if cell.flags.contains(Flags::WIDE_CHAR_SPACER) {
                continue;
            }
            let cp = cell.c as u32;
            if cp == 0 || cp == 0xFFFF {
                text.push(' ');
            } else if let Some(scalar) = char::from_u32(cp) {
                text.push(scalar);
            } else {
                text.push(' ');
            }
        }

        Some(text)
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

    /// Scroll the terminal viewport. Positive delta scrolls up (into history),
    /// negative scrolls down (toward live output).
    pub fn scroll(&self, delta: i32) {
        let mut term = self.term.lock();
        term.scroll_display(Scroll::Delta(delta));
    }

    // MARK: - Search

    /// Compile a search regex and find the first match forward from the cursor.
    /// Returns true if a match was found.
    pub fn search_set(&self, query: &str) -> bool {
        let mut regex = match RegexSearch::new(query) {
            Ok(r) => r,
            Err(_) => {
                self.search_clear();
                return false;
            }
        };

        let mut term = self.term.lock();
        let origin = term.grid().cursor.point;
        let found = term.search_next(&mut regex, origin, Direction::Right, Side::Left, None);

        if let Some(ref m) = found {
            Self::scroll_to_match(&mut term, m);
        }

        let mut search = self.search.lock();
        search.current_match = found;
        search.regex = Some(regex);

        search.current_match.is_some()
    }

    /// Navigate to the next or previous match.
    /// Returns true if a match was found.
    pub fn search_advance(&self, forward: bool) -> bool {
        let mut search = self.search.lock();

        // Destructure to allow borrowing regex and current_match independently
        let SearchState { regex, current_match } = &mut *search;
        let regex = match regex.as_mut() {
            Some(r) => r,
            None => return false,
        };
        let current = match current_match.as_ref() {
            Some(m) => m.clone(),
            None => return false,
        };

        let mut term = self.term.lock();

        let (origin, direction) = if forward {
            (*current.end(), Direction::Right)
        } else {
            (*current.start(), Direction::Left)
        };

        let found = term.search_next(regex, origin, direction, Side::Left, None);

        if let Some(ref m) = found {
            Self::scroll_to_match(&mut term, m);
        }

        *current_match = found;
        current_match.is_some()
    }

    /// Clear search state and remove highlights.
    pub fn search_clear(&self) {
        let mut search = self.search.lock();
        search.regex = None;
        search.current_match = None;
    }

    /// Scroll the viewport so the match is visible, centering it if needed.
    fn scroll_to_match(term: &mut Term<Listener>, m: &Match) {
        let grid = term.grid();
        let display_offset = grid.display_offset() as i32;
        let screen_lines = grid.screen_lines() as i32;
        let match_line = m.start().line.0;

        // Visible line range: top = -display_offset, bottom = top + screen_lines - 1
        let top_visible = -display_offset;
        let bottom_visible = top_visible + screen_lines - 1;

        if match_line >= top_visible && match_line <= bottom_visible {
            return; // Already visible
        }

        // Scroll so the match line is roughly centered
        let target_offset = (-match_line + screen_lines / 2).max(0);
        let delta = target_offset - display_offset;
        if delta != 0 {
            term.scroll_display(Scroll::Delta(delta));
        }
    }
}

impl Drop for TerminalHandle {
    fn drop(&mut self) {
        // Signal the reader thread to stop
        self.shutdown.store(true, Ordering::Relaxed);

        // Kill the shell so the PTY slave closes. Without this, the reader
        // thread is stuck in a blocking read() on its dup'd master fd and
        // join() would block the main thread forever.
        unsafe {
            libc::kill(self.shell_pid as i32, libc::SIGHUP);
        }

        if let Some(thread) = self.reader_thread.take() {
            let _ = thread.join();
        }
    }
}
