//! Deadline-bound frame reads and wire-error mapping shared by the runners.
//!
//! Every read re-arms the socket read timeout from the time left until the
//! caller's deadline, and maps the wire layer's string errors onto `RunError`.

use crate::error::RunError;
use crate::wire::{read_frame, read_frame_bytes, MAX_FRAME_SIZE};
use serde::Deserialize;
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

pub(crate) fn remaining(deadline: Instant) -> Option<Duration> {
    let now = Instant::now();
    if now >= deadline {
        None
    } else {
        Some(deadline - now)
    }
}

/// Arms the stream's read timeout to the time remaining until `deadline`.
/// Shared by `read_frame_deadline` and `read_frame_bytes_deadline` so both
/// obey the same per-read deadline arithmetic (a zero-or-negative remainder
/// is a timeout; a zero `set_read_timeout` would instead disable blocking).
fn arm_read_timeout(stream: &UnixStream, deadline: Instant) -> Result<(), RunError> {
    let rem = remaining(deadline).ok_or(RunError::Timeout)?;
    let rem = if rem.is_zero() {
        Duration::from_millis(1)
    } else {
        rem
    };
    stream.set_read_timeout(Some(rem)).map_err(|_| RunError::Io)
}

pub(crate) fn read_frame_deadline<M: for<'de> Deserialize<'de>>(
    mut stream: &UnixStream,
    deadline: Instant,
) -> Result<M, RunError> {
    arm_read_timeout(stream, deadline)?;
    read_frame(&mut stream, MAX_FRAME_SIZE).map_err(map_frame_err)
}

/// Same as `read_frame_deadline` but returns the raw frame payload bytes
/// without decoding them. Used by the protocol-22 observe loop (`ansi_runner`)
/// which must tolerate `ServerMessage` variants it does not know how to
/// decode, without misaligning on their contents (see `wire::read_frame_bytes`).
pub(crate) fn read_frame_bytes_deadline(
    mut stream: &UnixStream,
    deadline: Instant,
) -> Result<Vec<u8>, RunError> {
    arm_read_timeout(stream, deadline)?;
    read_frame_bytes(&mut stream, MAX_FRAME_SIZE).map_err(map_frame_err)
}

pub(crate) fn map_frame_err(e: String) -> RunError {
    if e.contains("timeout") {
        RunError::Timeout
    } else if e.contains("unexpected_eof")
        || e.contains("connection_reset")
        || e.contains("io_error")
    {
        RunError::Io
    } else if e.starts_with("oversized_frame") || e.starts_with("decode_error") {
        RunError::Bincode(e)
    } else {
        RunError::Io
    }
}

pub(crate) fn encode_err(e: String) -> RunError {
    RunError::Bincode(e)
}
