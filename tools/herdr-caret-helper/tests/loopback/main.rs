//! Loopback integration tests: a mock herdr server on one end of a UnixStream
//! pair and the observe runner on the other. The suites live in the `cursor`,
//! `ansi`, and `protocol22` modules; this root keeps the one helper the last
//! two share.

use herdr_caret_helper::wire::*;

mod ansi;
mod cursor;
mod protocol22;

fn terminal_frame(seq: u64, width: u16, height: u16, bytes: &[u8]) -> TerminalFrame {
    TerminalFrame {
        seq,
        width,
        height,
        full: true,
        bytes: bytes.to_vec(),
    }
}
