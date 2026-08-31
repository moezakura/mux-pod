//! Connection + observe runner shared by the CLI and loopback tests.

use crate::wire::*;
use serde::{Deserialize, Serialize};
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

/// Snapshot output as a single JSON line on stdout.
///
/// `cursor: null` means the observed terminal reported a frame with no
/// visible cursor (TUI apps etc. hide it); it is a legitimate observation,
/// not an error — distinct from a timeout where no frame ever arrives.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CaretOutput {
    pub cursor: Option<CursorState>,
    pub frame_width: u16,
    pub frame_height: u16,
    pub protocol_version: u32,
    pub pane_id: String,
}

impl CaretOutput {
    fn from_frame(frame: FrameData, protocol_version: u32, pane_id: String) -> Self {
        Self {
            cursor: frame.cursor,
            frame_width: frame.width,
            frame_height: frame.height,
            protocol_version,
            pane_id,
        }
    }
}

/// CLI parameters.
#[derive(Debug, Clone)]
pub struct Params {
    pub socket: String,
    pub pane: String,
    pub protocol: u8,
    pub cols: u16,
    pub rows: u16,
    pub timeout_ms: u64,
}

/// Error kinds safe for stderr emission (never carry socket path / payload / content).
#[derive(Debug)]
pub enum RunError {
    /// Could not connect to the socket.
    Connect,
    /// An I/O failure (EOF, reset, partial frame).
    Io,
    /// Deadline elapsed before a usable frame arrived.
    Timeout,
    /// The server rejected the handshake (Welcome.error present).
    WelcomeRejected(String),
    /// Protocol-level mismatch (version, encoding, wrong message, unknown variant).
    Protocol(String),
    /// Bincode/serialization failure.
    Bincode(String),
    /// CLI usage error.
    Usage(String),
}

impl RunError {
    pub fn json(&self) -> String {
        let kind = match self {
            RunError::Connect => "connect_failed",
            RunError::Io => "io_error",
            RunError::Timeout => "timeout",
            RunError::WelcomeRejected(_) => "welcome_rejected",
            RunError::Protocol(_) => "protocol_error",
            RunError::Bincode(_) => "decode_error",
            RunError::Usage(_) => "usage_error",
        };
        // The detail is macro-safe: only the reason string (no path/payload/content).
        serde_json::to_string(&serde_json::json!({ "error": kind }))
            .unwrap_or_else(|_| r#"{"error":"internal"}"#.to_owned())
    }
}

/// Connects to the socket and observes, returning the first cursor.
pub fn run(params: &Params) -> Result<CaretOutput, RunError> {
    if params.protocol != 17 && params.protocol != 20 {
        return Err(RunError::Usage("unsupported protocol; expected 17 or 20".to_owned()));
    }
    let stream = UnixStream::connect(&params.socket).map_err(|_| RunError::Connect)?;
    let base = Duration::from_millis(params.timeout_ms);
    stream.set_read_timeout(Some(base)).map_err(|_| RunError::Io)?;
    let deadline = Instant::now() + base;

    match params.protocol {
        17 => run_observe17(stream, params, deadline),
        20 => run_observe20(stream, params, deadline),
        _ => unreachable!(),
    }
}

/// Observes over protocol 17.
pub fn run_observe17(
    mut stream: UnixStream,
    params: &Params,
    deadline: Instant,
) -> Result<CaretOutput, RunError> {
    let hello = ClientMessage17::Hello {
        version: 17,
        cols: params.cols,
        rows: params.rows,
        cell_width_px: 0,
        cell_height_px: 0,
        requested_encoding: RenderEncoding::SemanticFrame,
        keybindings: ClientKeybindings::Server,
        launch_mode: ClientLaunchMode17::TerminalAttach,
    };
    write_frame(&mut stream, &hello).map_err(encode_err)?;

    let welcome: ServerMessage17 = read_frame_deadline(&stream, deadline)?;
    let (version, encoding, error) = match welcome {
        ServerMessage17::Welcome {
            version,
            encoding,
            error,
        } => (version, encoding, error),
        _ => return Err(RunError::Protocol("expected Welcome as first message".to_owned())),
    };
    if let Some(e) = error {
        return Err(RunError::WelcomeRejected(e));
    }
    if version != 17 {
        return Err(RunError::Protocol(format!(
            "server protocol mismatch: got {}, expected 17",
            version
        )));
    }
    if encoding != RenderEncoding::SemanticFrame {
        return Err(RunError::Protocol("unexpected render encoding".to_owned()));
    }

    write_frame(
        &mut stream,
        &ClientMessage17::ObserveTerminal {
            target: params.pane.clone(),
        },
    )
    .map_err(encode_err)?;

    // Kick the server into a render pass. TerminalObserve connections only
    // receive frames as part of a server render cycle; a Resize event forces
    // `needs_render` and the reset baseline turns that into a full frame for
    // this observer. For observe clients the server only updates the recorded
    // client size (the live terminal is never resized).
    write_frame(
        &mut stream,
        &ClientMessage17::Resize {
            cols: params.cols,
            rows: params.rows,
            cell_width_px: 0,
            cell_height_px: 0,
        },
    )
    .map_err(encode_err)?;

    loop {
        let msg: ServerMessage17 = read_frame_deadline(&stream, deadline)?;
        if let ServerMessage17::Frame(frame) = msg {
            // First frame decides: a cursor-less frame is a legitimate
            // "no visible cursor" observation (TUI apps), not a failure.
            return Ok(CaretOutput::from_frame(frame, 17, params.pane.clone()));
        }
    }
}

/// Observes over protocol 20.
pub fn run_observe20(
    mut stream: UnixStream,
    params: &Params,
    deadline: Instant,
) -> Result<CaretOutput, RunError> {
    let hello = ClientMessage20::Hello {
        version: 20,
        cols: params.cols,
        rows: params.rows,
        cell_width_px: 0,
        cell_height_px: 0,
        requested_encoding: RenderEncoding::SemanticFrame,
        keybindings: ClientKeybindings::Server,
        launch_mode: ClientLaunchMode20::TerminalAttach,
    };
    write_frame(&mut stream, &hello).map_err(encode_err)?;

    let welcome: ServerMessage20 = read_frame_deadline(&stream, deadline)?;
    let (version, encoding, error) = match welcome {
        ServerMessage20::Welcome {
            version,
            encoding,
            error,
        } => (version, encoding, error),
        _ => return Err(RunError::Protocol("expected Welcome as first message".to_owned())),
    };
    if let Some(e) = error {
        return Err(RunError::WelcomeRejected(e));
    }
    if version != 20 {
        return Err(RunError::Protocol(format!(
            "server protocol mismatch: got {}, expected 20",
            version
        )));
    }
    if encoding != RenderEncoding::SemanticFrame {
        return Err(RunError::Protocol("unexpected render encoding".to_owned()));
    }

    write_frame(
        &mut stream,
        &ClientMessage20::ObserveTerminal {
            target: params.pane.clone(),
        },
    )
    .map_err(encode_err)?;

    // Same render kick as protocol 17 (observe clients only get their client
    // size updated; the observed terminal itself is never resized).
    write_frame(
        &mut stream,
        &ClientMessage20::Resize {
            cols: params.cols,
            rows: params.rows,
            cell_width_px: 0,
            cell_height_px: 0,
        },
    )
    .map_err(encode_err)?;

    loop {
        let msg: ServerMessage20 = read_frame_deadline(&stream, deadline)?;
        if let ServerMessage20::Frame(frame) = msg {
            return Ok(CaretOutput::from_frame(frame, 20, params.pane.clone()));
        }
    }
}

fn remaining(deadline: Instant) -> Option<Duration> {
    let now = Instant::now();
    if now >= deadline {
        None
    } else {
        Some(deadline - now)
    }
}

fn read_frame_deadline<M: for<'de> Deserialize<'de>>(
    mut stream: &UnixStream,
    deadline: Instant,
) -> Result<M, RunError> {
    let rem = remaining(deadline).ok_or(RunError::Timeout)?;
    // A zero timeout would disable blocking; ensure a positive value.
    let rem = if rem.is_zero() {
        Duration::from_millis(1)
    } else {
        rem
    };
    stream.set_read_timeout(Some(rem)).map_err(|_| RunError::Io)?;
    read_frame(&mut stream, MAX_FRAME_SIZE).map_err(map_frame_err)
}

fn map_frame_err(e: String) -> RunError {
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

fn encode_err(e: String) -> RunError {
    RunError::Bincode(e)
}
