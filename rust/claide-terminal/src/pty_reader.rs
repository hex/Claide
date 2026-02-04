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

/// Runs the PTY reader loop. Call from a dedicated thread.
///
/// Reads bytes from the PTY, scans for OSC 7, then feeds through VTE into Term.
pub fn run_reader(
    pty_fd: i32,
    term: Arc<FairMutex<Term<Listener>>>,
    listener: Listener,
    shutdown: Arc<AtomicBool>,
) {
    let file = unsafe { std::fs::File::from_raw_fd(pty_fd) };
    let mut reader = std::io::BufReader::with_capacity(8192, file);
    let mut buf = [0u8; 4096];
    let mut parser = vte::ansi::Processor::<vte::ansi::StdSyncHandler>::new();
    let mut osc7 = Osc7Scanner::new();

    loop {
        if shutdown.load(Ordering::Relaxed) {
            break;
        }

        match reader.read(&mut buf) {
            Ok(0) => break, // EOF
            Ok(n) => {
                let bytes = &buf[..n];

                // Scan for OSC 7 before VTE parsing
                for &byte in bytes {
                    if let Some(dir) = osc7.feed(byte) {
                        listener.send_directory_change(&dir);
                    }
                }

                // Feed bytes to the terminal
                {
                    let mut term = term.lock();
                    parser.advance(&mut *term, bytes);
                }

                // Notify Swift that the terminal state changed
                listener.send_event(Event::Wakeup);
            }
            Err(e) => {
                if e.kind() == std::io::ErrorKind::Interrupted {
                    continue;
                }
                // EIO means the child exited and the PTY slave was closed
                break;
            }
        }
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
