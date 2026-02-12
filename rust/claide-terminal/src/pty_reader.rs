// ABOUTME: Reads PTY output on a background thread, feeds bytes to the VTE parser.
// ABOUTME: Drains all available PTY data before processing to maximize throughput.

use std::io::Read;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use alacritty_terminal::event::{Event, EventListener};
use alacritty_terminal::sync::FairMutex;
use alacritty_terminal::term::Term;
use alacritty_terminal::vte;

use crate::listener::Listener;

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
    let mut osc7_partial = Vec::new();
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
        for dir in scan_osc7(&pending, &mut osc7_partial) {
            listener.send_directory_change(&dir);
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

/// Scan a data buffer for OSC 7 directory-change sequences using SIMD-accelerated search.
///
/// Uses memchr to find ESC (0x1b) bytes, then inspects those positions for `]7;` sequences.
/// `partial` carries incomplete sequences across batch boundaries.
/// Returns all directory URLs found in the buffer.
fn scan_osc7(data: &[u8], partial: &mut Vec<u8>) -> Vec<String> {
    let mut results = Vec::new();

    // Complete a partial sequence from a previous batch
    if !partial.is_empty() {
        if let Some((url_end, term_len)) = find_osc_terminator(data) {
            partial.extend_from_slice(&data[..url_end]);
            if let Ok(dir) = std::str::from_utf8(partial) {
                results.push(dir.to_string());
            }
            partial.clear();
            // Continue scanning after the terminator
            let rest = &data[url_end + term_len..];
            results.extend(scan_osc7(rest, partial));
            return results;
        } else if data.len() + partial.len() > 4096 {
            // Partial grew too large — abandon it
            partial.clear();
        } else {
            partial.extend_from_slice(data);
            return results;
        }
    }

    let mut pos = 0;
    while let Some(esc_offset) = memchr::memchr(0x1b, &data[pos..]) {
        let esc_pos = pos + esc_offset;
        let remaining = &data[esc_pos..];

        if remaining.starts_with(b"\x1b]7;") {
            let url_start = esc_pos + 4;
            if let Some((url_end, term_len)) = find_osc_terminator(&data[url_start..]) {
                if let Ok(dir) = std::str::from_utf8(&data[url_start..url_start + url_end]) {
                    results.push(dir.to_string());
                }
                pos = url_start + url_end + term_len;
                continue;
            } else {
                // Partial sequence at end of buffer — save for next batch
                partial.clear();
                partial.extend_from_slice(&data[url_start..]);
                break;
            }
        }
        pos = esc_pos + 1;
    }

    results
}

/// Find the terminator for an OSC sequence (BEL or ST) within data.
/// Returns (url_length, terminator_length) if found.
fn find_osc_terminator(data: &[u8]) -> Option<(usize, usize)> {
    for (i, &byte) in data.iter().enumerate() {
        match byte {
            0x07 => return Some((i, 1)),
            0x1b if data.get(i + 1) == Some(&b'\\') => return Some((i, 2)),
            _ => {
                if i > 4096 {
                    return None;
                }
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn osc7_bel_terminator() {
        let data = b"\x1b]7;file:///Users/hex/projects\x07";
        let mut partial = Vec::new();
        let results = scan_osc7(data, &mut partial);
        assert_eq!(results, vec!["file:///Users/hex/projects"]);
    }

    #[test]
    fn osc7_st_terminator() {
        let data = b"\x1b]7;file:///Users/hex\x1b\\";
        let mut partial = Vec::new();
        let results = scan_osc7(data, &mut partial);
        assert_eq!(results, vec!["file:///Users/hex"]);
    }

    #[test]
    fn osc7_ignores_other_osc() {
        let data = b"\x1b]0;Window Title\x07";
        let mut partial = Vec::new();
        let results = scan_osc7(data, &mut partial);
        assert!(results.is_empty());
    }

    #[test]
    fn osc7_mixed_with_normal_output() {
        let data = b"Hello world\x1b]7;file:///tmp\x07more text";
        let mut partial = Vec::new();
        let results = scan_osc7(data, &mut partial);
        assert_eq!(results, vec!["file:///tmp"]);
    }

    #[test]
    fn osc7_partial_across_batches() {
        let mut partial = Vec::new();

        // First batch: OSC 7 prefix + start of URL, no terminator
        let batch1 = b"\x1b]7;file:///Us";
        let results1 = scan_osc7(batch1, &mut partial);
        assert!(results1.is_empty());
        assert!(!partial.is_empty(), "partial should buffer incomplete URL");

        // Second batch: rest of URL + terminator
        let batch2 = b"ers/hex\x07";
        let results2 = scan_osc7(batch2, &mut partial);
        assert_eq!(results2, vec!["file:///Users/hex"]);
        assert!(partial.is_empty(), "partial should be cleared after completion");
    }

    #[test]
    fn osc7_multiple_in_one_buffer() {
        let data = b"\x1b]7;file:///tmp\x07some text\x1b]7;file:///home\x07";
        let mut partial = Vec::new();
        let results = scan_osc7(data, &mut partial);
        assert_eq!(results, vec!["file:///tmp", "file:///home"]);
    }

    #[test]
    fn find_osc_terminator_bel() {
        let data = b"file:///tmp\x07rest";
        let result = find_osc_terminator(data);
        assert_eq!(result, Some((11, 1)));
    }

    #[test]
    fn find_osc_terminator_st() {
        let data = b"file:///tmp\x1b\\rest";
        let result = find_osc_terminator(data);
        assert_eq!(result, Some((11, 2)));
    }

    #[test]
    fn find_osc_terminator_absent() {
        let data = b"file:///tmp with no terminator";
        let result = find_osc_terminator(data);
        assert_eq!(result, None);
    }
}
