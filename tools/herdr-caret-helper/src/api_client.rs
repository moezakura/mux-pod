//! Herdr JSON API client (`herdr.sock`): `pane.get` / `pane.scroll` /
//! `pane.process_info` only.
//!
//! Wire shape verified against the vendored herdr v0.9.1 source (read-only
//! reference clone, not part of this crate):
//!   - Request envelope: `Request { id: String, #[serde(flatten)] method: Method }`
//!     (`src/api/schema.rs:36-41`). `pane.get` takes `PaneTarget { pane_id }`
//!     (`src/api/schema/common.rs:34-36`); `pane.scroll` takes
//!     `PaneScrollParams { pane_id, offset_from_bottom: u64 }`
//!     (`src/api/schema/panes.rs:245-249`); `pane.process_info` takes
//!     `PaneProcessInfoParams { pane_id: Option<String> }`
//!     (`src/api/schema/panes.rs:130-134`; this client always sends a pane_id).
//!   - `pane.get`/`pane.scroll` reply with the *same* result shape,
//!     `ResponseResult::PaneInfo { pane: PaneInfo }` (`src/api/schema/response.rs:117-119`;
//!     `pane.scroll`'s handler returns this too, see `src/app/api/panes.rs:186-203`
//!     `handle_pane_scroll` -> `encode_success(id, ResponseResult::PaneInfo { pane })`).
//!     `PaneInfo.scroll` is `Option<PaneScrollInfo { offset_from_bottom,
//!     max_offset_from_bottom, viewport_rows }>` (all `u64`,
//!     `src/api/schema/panes.rs:527-566`).
//!   - `pane.process_info` replies with `ResponseResult::PaneProcessInfo
//!     { process_info: PaneProcessInfo }`, tag `"type": "pane_process_info"`
//!     (`#[serde(tag = "type", rename_all = "snake_case")]` on
//!     `ResponseResult`, `src/api/schema/response.rs:42-43,138-140`).
//!     `PaneProcessInfo.shell_pid` is `Option<u32>` and is
//!     `skip_serializing_if = "Option::is_none"` on the wire, i.e. the key
//!     can be *absent* entirely when there is no shell PID
//!     (`src/api/schema/panes.rs:490-495`) -- this client's `PaneProcessInfo`
//!     only keeps that one field; the rest (`pane_id`,
//!     `foreground_process_group_id`, `tty`, `foreground_processes`) are
//!     ignored, same as `PaneInfo` ignoring fields it does not need below.
//!   - Errors are `ErrorResponse { id, error: ErrorBody { code, message } }`
//!     (`src/api/schema/response.rs:31-37`).
//!
//! Connection model (verified, not assumed): `handle_connection_with_stop`
//! (`src/api/server.rs:156-183`) reads exactly one request line, dispatches
//! it, writes exactly one response line, and returns — there is no read loop
//! for a second request on the same connection for `pane.get`/`pane.scroll`
//! (those fall through the `method_body` catch-all, which writes one line and
//! returns; only the streaming methods like `events.subscribe` behave
//! differently, and they are never used here). So every call below opens a
//! fresh connection, writes one line, reads one line, and drops the stream.

use crate::runner::RunError;
use serde::Deserialize;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

/// Subset of herdr's `PaneScrollInfo` (`src/api/schema/panes.rs:563-567`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub struct ScrollInfo {
    pub offset_from_bottom: u64,
    pub max_offset_from_bottom: u64,
    pub viewport_rows: u64,
}

/// Subset of herdr's `PaneInfo` (`src/api/schema/panes.rs:527-548`) needed by
/// the scrollback runner. Other fields (cwd, labels, tokens, ...) are present
/// on the wire but ignored here; serde ignores unknown fields by default
/// (herdr's `PaneInfo` has no `#[serde(deny_unknown_fields)]`).
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct PaneInfo {
    pub terminal_id: String,
    #[serde(default)]
    pub scroll: Option<ScrollInfo>,
}

#[derive(Deserialize)]
struct RawSuccess {
    result: RawResult,
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum RawResult {
    PaneInfo {
        pane: PaneInfo,
    },
    #[serde(other)]
    Other,
}

#[derive(Deserialize)]
struct RawError {
    error: RawErrorBody,
}

#[derive(Deserialize)]
struct RawErrorBody {
    code: String,
}

/// Subset of herdr's `PaneProcessInfo` (`src/api/schema/panes.rs:490-499`)
/// needed by `winsize::real_size`. Only `shell_pid` is kept; see this
/// module's doc comment for why the other fields are ignored.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub struct PaneProcessInfo {
    #[serde(default)]
    pub shell_pid: Option<u32>,
}

#[derive(Deserialize)]
struct RawProcessInfoSuccess {
    result: RawProcessInfoResult,
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum RawProcessInfoResult {
    PaneProcessInfo {
        process_info: PaneProcessInfo,
    },
    #[serde(other)]
    Other,
}

/// Sends `pane.get` and returns the pane's `terminal_id` and scroll state.
pub fn pane_get(socket: &str, pane_id: &str, deadline: Instant) -> Result<PaneInfo, RunError> {
    let request = serde_json::json!({
        "id": "1",
        "method": "pane.get",
        "params": { "pane_id": pane_id },
    });
    let line = call(socket, &request.to_string(), deadline)?;
    parse_pane_info_response(&line)
}

/// Sends `pane.scroll` (which both moves the pane's shared scroll offset and
/// returns the resulting pane state, same result shape as `pane.get`).
pub fn pane_scroll(
    socket: &str,
    pane_id: &str,
    offset_from_bottom: u64,
    deadline: Instant,
) -> Result<PaneInfo, RunError> {
    let request = serde_json::json!({
        "id": "1",
        "method": "pane.scroll",
        "params": { "pane_id": pane_id, "offset_from_bottom": offset_from_bottom },
    });
    let line = call(socket, &request.to_string(), deadline)?;
    parse_pane_info_response(&line)
}

/// Sends `pane.process_info` and returns the pane's `shell_pid` (`None` if
/// herdr reports no shell PID for this pane, e.g. the shell has already
/// exited). Used by `winsize::real_size`'s caller to resolve the real
/// terminal cell/pixel dimensions (17/20 fail-closed Hello/Resize
/// sizing).
pub fn pane_process_info(
    socket: &str,
    pane_id: &str,
    deadline: Instant,
) -> Result<PaneProcessInfo, RunError> {
    let request = serde_json::json!({
        "id": "1",
        "method": "pane.process_info",
        "params": { "pane_id": pane_id },
    });
    let line = call(socket, &request.to_string(), deadline)?;
    parse_process_info_response(&line)
}

/// Opens a fresh connection, writes `request_line` + `\n`, reads one line back.
fn call(socket: &str, request_line: &str, deadline: Instant) -> Result<String, RunError> {
    let timeout = remaining(deadline)?;
    let stream = UnixStream::connect(socket).map_err(|_| RunError::Connect)?;
    stream.set_write_timeout(Some(timeout)).map_err(io_err)?;
    stream.set_read_timeout(Some(timeout)).map_err(io_err)?;
    {
        let mut writer = &stream;
        writer.write_all(request_line.as_bytes()).map_err(io_err)?;
        writer.write_all(b"\n").map_err(io_err)?;
        writer.flush().map_err(io_err)?;
    }
    let mut reader = BufReader::new(&stream);
    let mut line = String::new();
    let read = reader.read_line(&mut line).map_err(io_err)?;
    if read == 0 {
        // EOF before a full line arrived: the server closed the connection
        // without responding.
        return Err(RunError::Io);
    }
    Ok(line)
}

/// Parses one response line as either a `pane.get`/`pane.scroll` success or
/// an API error. Both a JSON-RPC error and malformed JSON
/// classify as `protocol_error` (this API surface has no separate
/// `decode_error` kind).
fn parse_pane_info_response(line: &str) -> Result<PaneInfo, RunError> {
    if let Ok(err) = serde_json::from_str::<RawError>(line) {
        return Err(RunError::Protocol(err.error.code));
    }
    let success: RawSuccess = serde_json::from_str(line)
        .map_err(|e| RunError::Protocol(format!("malformed response: {}", e)))?;
    match success.result {
        RawResult::PaneInfo { pane } => Ok(pane),
        RawResult::Other => Err(RunError::Protocol("unexpected result type".to_owned())),
    }
}

/// Parses one response line as either a `pane.process_info` success or an
/// API error. Same `protocol_error` classification rule as
/// `parse_pane_info_response`: both a JSON-RPC error and
/// malformed JSON map to `RunError::Protocol`.
fn parse_process_info_response(line: &str) -> Result<PaneProcessInfo, RunError> {
    if let Ok(err) = serde_json::from_str::<RawError>(line) {
        return Err(RunError::Protocol(err.error.code));
    }
    let success: RawProcessInfoSuccess = serde_json::from_str(line)
        .map_err(|e| RunError::Protocol(format!("malformed response: {}", e)))?;
    match success.result {
        RawProcessInfoResult::PaneProcessInfo { process_info } => Ok(process_info),
        RawProcessInfoResult::Other => Err(RunError::Protocol("unexpected result type".to_owned())),
    }
}

fn remaining(deadline: Instant) -> Result<Duration, RunError> {
    let now = Instant::now();
    if now >= deadline {
        Err(RunError::Timeout)
    } else {
        Ok(deadline - now)
    }
}

fn io_err(e: std::io::Error) -> RunError {
    match e.kind() {
        std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock => RunError::Timeout,
        _ => RunError::Io,
    }
}
