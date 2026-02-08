// ABOUTME: Reads PTY output on a background thread, feeds bytes to the VTE parser.
// ABOUTME: Includes an OSC 7 byte-level scanner to detect directory change sequences.

use std::io::Read;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use alacritty_terminal::event::{Event, EventListener};
use alacritty_terminal::sync::FairMutex;
use alacritty_terminal::term::Term;
use alacritty_terminal::vte;
use memchr::memchr;

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

    /// Scan a batch of bytes, using memchr to skip directly to ESC bytes in ground state.
    fn scan_batch(&mut self, data: &[u8], listener: &Listener) {
        let mut pos = 0;
        while pos < data.len() {
            if self.state == Osc7State::Ground {
                // SIMD-accelerated skip to the next ESC byte
                match memchr(0x1b, &data[pos..]) {
                    Some(offset) => {
                        pos += offset;
                        self.state = Osc7State::Esc;
                        pos += 1;
                    }
                    None => break,
                }
            } else {
                if let Some(dir) = self.feed(data[pos]) {
                    listener.send_directory_change(&dir);
                }
                pos += 1;
            }
        }
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
/// Read into a Vec's spare capacity, returning the number of bytes read.
/// Avoids intermediate stack buffers by writing directly into the Vec.
fn read_into_vec(file: &mut std::fs::File, vec: &mut Vec<u8>) -> std::io::Result<usize> {
    vec.reserve(65536);
    let start = vec.len();
    // SAFETY: reserve() ensures capacity >= start + 65536. The bytes between
    // len and capacity are allocated but uninitialized; read() will overwrite
    // them before we set_len to include only the bytes actually written.
    unsafe { vec.set_len(start + 65536) };
    match file.read(&mut vec[start..]) {
        Ok(n) => {
            unsafe { vec.set_len(start + n) };
            Ok(n)
        }
        Err(e) => {
            unsafe { vec.set_len(start) };
            Err(e)
        }
    }
}

pub fn run_reader(
    pty_fd: i32,
    term: Arc<FairMutex<Term<Listener>>>,
    listener: Listener,
    shutdown: Arc<AtomicBool>,
) {
    let mut file = unsafe { std::fs::File::from_raw_fd(pty_fd) };
    let mut parser = vte::ansi::Processor::<vte::ansi::StdSyncHandler>::new();
    let mut osc7 = Osc7Scanner::new();
    let mut pending = Vec::with_capacity(65536);

    loop {
        if shutdown.load(Ordering::Relaxed) {
            break;
        }

        // Blocking read directly into pending — no intermediate buffer
        match read_into_vec(&mut file, &mut pending) {
            Ok(0) => break,
            Ok(_) => {}
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }

        // Drain: keep reading while more data is available and under the batch limit.
        // poll() with zero timeout returns immediately, so we only accumulate
        // data that's already in the kernel buffer.
        while pending.len() < BATCH_LIMIT && poll_readable(pty_fd) {
            match read_into_vec(&mut file, &mut pending) {
                Ok(0) => break,
                Ok(_) => {}
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }

        // Scan for OSC 7 before VTE parsing (memchr skips to ESC bytes)
        osc7.scan_batch(&pending, &listener);

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
    std::mem::forget(file);
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

    #[test]
    fn scan_batch_matches_byte_by_byte() {
        // Test data: normal text, then two OSC 7 sequences, then more text
        let data = b"normal output\x1b]7;file:///first\x07between\x1b]7;file:///second\x1b\\trailing";

        // Byte-by-byte
        let mut scanner1 = Osc7Scanner::new();
        let mut results1 = Vec::new();
        for &byte in data.iter() {
            if let Some(dir) = scanner1.feed(byte) {
                results1.push(dir);
            }
        }

        // Batch (memchr-accelerated) — collect results manually since we can't
        // easily create a real Listener in tests. Replicate scan_batch logic.
        let mut scanner2 = Osc7Scanner::new();
        let mut results2 = Vec::new();
        let mut pos = 0;
        while pos < data.len() {
            if scanner2.state == Osc7State::Ground {
                match memchr(0x1b, &data[pos..]) {
                    Some(offset) => {
                        pos += offset;
                        scanner2.state = Osc7State::Esc;
                        pos += 1;
                    }
                    None => break,
                }
            } else {
                if let Some(dir) = scanner2.feed(data[pos]) {
                    results2.push(dir);
                }
                pos += 1;
            }
        }

        assert_eq!(results1, results2);
        assert_eq!(results1, vec!["file:///first", "file:///second"]);
    }
}
