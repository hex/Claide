// ABOUTME: Reads PTY output on a background thread, feeds bytes to the VTE parser.
// ABOUTME: Includes an OSC 7 byte-level scanner to detect directory change sequences.

use std::io::Read;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use alacritty_terminal::event::{Event, EventListener};
use alacritty_terminal::sync::FairMutex;
use alacritty_terminal::term::Term;
use alacritty_terminal::vte;

use crate::listener::Listener;

/// Scans for OSC 7 (directory change) escape sequences in the raw byte stream.
///
/// Sequence format: ESC ] 7 ; <url> ST
/// Where ST is either ESC \ or BEL (0x07).
///
/// This runs before VTE parsing because alacritty_terminal doesn't expose OSC 7.
struct Osc7Scanner {
    state: Osc7State,
    buffer: Vec<u8>,
}

#[derive(PartialEq)]
enum Osc7State {
    Ground,
    Esc,       // saw ESC
    OscStart,  // saw ESC ]
    Osc7,      // saw ESC ] 7
    OscSemi,   // saw ESC ] 7 ;
    Payload,   // collecting URL bytes
    PayloadEsc, // saw ESC inside payload (looking for \)
}

impl Osc7Scanner {
    fn new() -> Self {
        Self {
            state: Osc7State::Ground,
            buffer: Vec::with_capacity(256),
        }
    }

    /// Process a single byte, returns the directory URL if a complete OSC 7 sequence was found.
    fn feed(&mut self, byte: u8) -> Option<String> {
        match self.state {
            Osc7State::Ground => {
                if byte == 0x1b {
                    self.state = Osc7State::Esc;
                }
                None
            }
            Osc7State::Esc => {
                if byte == b']' {
                    self.state = Osc7State::OscStart;
                } else {
                    self.state = Osc7State::Ground;
                }
                None
            }
            Osc7State::OscStart => {
                if byte == b'7' {
                    self.state = Osc7State::Osc7;
                } else {
                    self.state = Osc7State::Ground;
                }
                None
            }
            Osc7State::Osc7 => {
                if byte == b';' {
                    self.state = Osc7State::OscSemi;
                    self.buffer.clear();
                } else {
                    self.state = Osc7State::Ground;
                }
                None
            }
            Osc7State::OscSemi => {
                // Transition: first payload byte
                self.state = Osc7State::Payload;
                self.feed_payload(byte)
            }
            Osc7State::Payload => self.feed_payload(byte),
            Osc7State::PayloadEsc => {
                self.state = Osc7State::Ground;
                if byte == b'\\' {
                    self.complete()
                } else {
                    self.buffer.clear();
                    None
                }
            }
        }
    }

    fn feed_payload(&mut self, byte: u8) -> Option<String> {
        match byte {
            0x07 => {
                // BEL terminates OSC
                self.state = Osc7State::Ground;
                self.complete()
            }
            0x1b => {
                // Possible start of ST (ESC \)
                self.state = Osc7State::PayloadEsc;
                None
            }
            _ => {
                if self.buffer.len() < 4096 {
                    self.buffer.push(byte);
                } else {
                    // Payload too long, abort
                    self.state = Osc7State::Ground;
                    self.buffer.clear();
                }
                None
            }
        }
    }

    fn complete(&mut self) -> Option<String> {
        let result = String::from_utf8(self.buffer.clone()).ok();
        self.buffer.clear();
        result
    }
}

/// Maximum bytes to accumulate before flushing through VTE.
const BATCH_LIMIT: usize = 1024 * 1024; // 1 MB

/// Check if a file descriptor has data available for reading without blocking.
fn poll_readable(fd: i32) -> bool {
    let mut pfd = libc::pollfd {
        fd,
        events: libc::POLLIN,
        revents: 0,
    };
    let ret = unsafe { libc::poll(&mut pfd, 1, 0) };
    ret > 0 && (pfd.revents & libc::POLLIN) != 0
}

/// Runs the PTY reader loop. Call from a dedicated thread.
///
/// Drains all available PTY data before processing through VTE to maximize
/// throughput. Uses poll() to check for more data without blocking, then
/// flushes the accumulated batch in a single lock acquisition.
pub fn run_reader(
    pty_fd: i32,
    term: Arc<FairMutex<Term<Listener>>>,
    listener: Listener,
    shutdown: Arc<AtomicBool>,
) {
    let file = unsafe { std::fs::File::from_raw_fd(pty_fd) };
    let mut reader = std::io::BufReader::with_capacity(65536, file);
    let mut buf = [0u8; 65536];
    let mut parser = vte::ansi::Processor::<vte::ansi::StdSyncHandler>::new();
    let mut osc7 = Osc7Scanner::new();
    let mut pending = Vec::with_capacity(65536);

    loop {
        if shutdown.load(Ordering::Relaxed) {
            break;
        }

        // Blocking read — suspends the thread when no data is available
        let n = match reader.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        };

        pending.extend_from_slice(&buf[..n]);

        // Drain: keep reading while more data is available and under the batch limit.
        // poll() with zero timeout returns immediately, so we only accumulate
        // data that's already in the kernel buffer.
        while pending.len() < BATCH_LIMIT && poll_readable(pty_fd) {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => pending.extend_from_slice(&buf[..n]),
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }

        // Scan for OSC 7 before VTE parsing
        for &byte in pending.iter() {
            if let Some(dir) = osc7.feed(byte) {
                listener.send_directory_change(&dir);
            }
        }

        // Flush the entire batch through VTE in a single lock acquisition
        {
            let mut term = term.lock();
            parser.advance(&mut *term, &pending);
        }
        pending.clear();

        listener.send_event(Event::Wakeup);
    }

    // Flush any remaining buffered bytes
    if !pending.is_empty() {
        let mut guard = term.lock();
        parser.advance(&mut *guard, &pending);
        drop(guard);
        listener.send_event(Event::Wakeup);
    }

    // Prevent the File from closing the fd — handle.rs owns it via pty_master_fd
    std::mem::forget(reader.into_inner());
}

use std::os::fd::FromRawFd;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn osc7_bel_terminator() {
        let mut scanner = Osc7Scanner::new();
        let seq = b"\x1b]7;file:///Users/hex/projects\x07";
        let mut result = None;
        for &byte in seq.iter() {
            if let Some(dir) = scanner.feed(byte) {
                result = Some(dir);
            }
        }
        assert_eq!(result, Some("file:///Users/hex/projects".to_string()));
    }

    #[test]
    fn osc7_st_terminator() {
        let mut scanner = Osc7Scanner::new();
        let seq = b"\x1b]7;file:///Users/hex\x1b\\";
        let mut result = None;
        for &byte in seq.iter() {
            if let Some(dir) = scanner.feed(byte) {
                result = Some(dir);
            }
        }
        assert_eq!(result, Some("file:///Users/hex".to_string()));
    }

    #[test]
    fn osc7_ignores_other_osc() {
        let mut scanner = Osc7Scanner::new();
        let seq = b"\x1b]0;Window Title\x07";
        let mut result = None;
        for &byte in seq.iter() {
            if let Some(dir) = scanner.feed(byte) {
                result = Some(dir);
            }
        }
        assert_eq!(result, None);
    }

    #[test]
    fn osc7_mixed_with_normal_output() {
        let mut scanner = Osc7Scanner::new();
        let seq = b"Hello world\x1b]7;file:///tmp\x07more text";
        let mut result = None;
        for &byte in seq.iter() {
            if let Some(dir) = scanner.feed(byte) {
                result = Some(dir);
            }
        }
        assert_eq!(result, Some("file:///tmp".to_string()));
    }
}
