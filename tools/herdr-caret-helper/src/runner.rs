//! Connection + observe runner shared by the CLI and loopback tests.

use crate::ansi_runner::observe_terminal_ansi;
use crate::is_caret_protocol_supported;
use crate::tracker::{track_frame, TrackedFrame};
use crate::winsize::Winsize;
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

    /// The same `CaretOutput`
    /// shape protocols 17/20 already produce via `from_frame`, but built
    /// from a tracked `TerminalAnsi` frame's trailing cursor state instead
    /// of a decoded `FrameData.cursor` — the only cursor source protocol 22
    /// has, since it has no `Frame(FrameData)`/`SemanticFrame` variant at
    /// all.
    ///
    /// Used by `run_observe22` (this same module), which calls this
    /// to build protocol 22's `CaretOutput` from `run()`. The existing
    /// 17/20 `run_observe17`/`run_observe20` paths remain completely
    /// untouched by this function's existence.
    pub fn from_tracked_frame(
        tracked: &TrackedFrame,
        protocol_version: u32,
        pane_id: String,
        frame_width: u16,
        frame_height: u16,
    ) -> Self {
        Self {
            cursor: caret_cursor_state(tracked),
            frame_width,
            frame_height,
            protocol_version,
            pane_id,
        }
    }
}

/// Mirrors herdr's own trailing cursor-state emission exactly
/// (`render_ansi.rs`'s `write_host_cursor_state`, read directly from HEAD /
/// v0.9.1: CUP is always written first, so a well-formed full-redraw frame's
/// `cursor_position` is always `Some`; `?25h`/`?25l` is always written next,
/// so `cursor_visible` is likewise always `Some`; the DECSCUSR shape (`{n}
/// q`) is only written when it differs from the previous frame's shape, so
/// `cursor_shape` may legitimately be `None` — treated here as shape `0`
/// ("terminal default"), matching DECSCUSR's own convention
/// (`HostCursorState::shape`'s doc comment: "0 means terminal default").
///
/// **Why `0` is the correct "previous shape" for a fresh connection, not
/// just DECSCUSR's own convention** (verified by reading
/// herdr's source directly, all 3 tagged versions): the "previous shape" a
/// server compares against is per-*client*, not per-pane, and always starts
/// at Rust's `u8` default (`0`) for a brand-new connection — exactly what
/// this helper opens on every invocation. `BlitEncoder` (holding
/// `last_cursor_shape: u8`) derives `Default`
/// (v0.7.5 `render_ansi.rs:49-53`, v0.8.2 `:56-60`, v0.9.1 `:58-62`), and is
/// constructed fresh via `BlitEncoder::new()` inside
/// `ClientRenderState::new(render_encoding)` — explicitly documented as
/// "Per-client render baseline for the negotiated render encoding"
/// (v0.7.5 `server/render_stream.rs:12-25`, v0.8.2 `:12-29`,
/// v0.9.1 `:14-43`) — itself called from `ClientConnection::new_with_mode`
/// every time a client connects (`server/clients.rs:216-232`, confirmed
/// against the HEAD/v0.9.1 checkout). So a fresh connection's `last_shape`
/// is never inherited from another client or a prior session on the same
/// pane; it is always exactly `0`. Consequence: if the pane's *actual*
/// cursor shape at connect time is also `0`, herdr's own equality check
/// (`write_host_cursor_state`: `if cursor.shape != *last_shape`, v0.7.5
/// `:564`, v0.8.2 `:612`, v0.9.1 `:816`) suppresses the DECSCUSR token
/// entirely on the very first frame — so `cursor_shape == None` here is not
/// an unresolved ambiguity, it is *proof* the shape is `0`. If the actual
/// shape were non-zero, that same check (`0 != actual`) guarantees a
/// DECSCUSR is emitted on that first frame, so `cursor_shape` would already
/// be `Some(actual)`, never `None`. `unwrap_or(0)` is therefore not a
/// guessed fallback but the one value `None` can ever mean here.
///
/// When `cursor_visible == Some(false)`, this returns `None` — the same
/// `cursor: null` observation the existing 17/20 caret path already returns
/// for a hidden cursor (`CaretOutput`'s own doc comment above). Missing
/// `cursor_visible`/`cursor_position` (which a real herdr server's
/// full-redraw frame never produces, per the emission order above) is
/// treated the same way — fail-closed to "unknown cursor" rather than
/// guessing a position, never a panic.
fn caret_cursor_state(tracked: &TrackedFrame) -> Option<CursorState> {
    let visible = tracked.cursor_visible?;
    if !visible {
        return None;
    }
    let (row, col) = tracked.cursor_position?;
    Some(CursorState {
        x: col,
        y: row,
        visible: true,
        shape: tracked.cursor_shape.unwrap_or(0),
    })
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
///
/// Kind strings (see `json()`) follow the documented failure classification
/// verbatim: the common set (`usage_error`/`connect_failed`/`io_error`/
/// `timeout`/`welcome_rejected`/`protocol_error`/`decode_error`) plus
/// `render_rejected` (the `hyperlinks`/caret-22 tracker rejecting a frame)
/// and, for `scrollback-links` only, `busy`,
/// `unsupported_scroll`, and `attach_rejected`.
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
    /// The tracker rejected an observed `TerminalAnsi` frame (unknown escape
    /// sequence, invariant violation, wrong `full` state —
    /// fail-closed condition). Kind: `render_rejected`.
    RenderRejected(String),
    /// `AttachTerminal` was rejected, or the attach connection was
    /// disconnected mid-session (`ServerShutdown`, protocol error while
    /// attached). Used by the 17/20 `scrollback-links` attach path.
    /// Kind: `attach_rejected`.
    AttachRejected(String),
    /// The per-pane `scrollback-links` lock file could not be acquired
    /// (another invocation already holds it for this pane). Kind: `busy`.
    Busy,
    /// The connected herdr server does not support `pane.scroll`
    /// (added in v0.9.0; 17/20 servers predate it). Kind: `unsupported_scroll`.
    UnsupportedScroll,
    /// The real pty size could not be
    /// determined (`winsize::real_size` failed, or `pane.process_info`
    /// returned no `shell_pid`) for a `scrollback-links` invocation on
    /// 17/20, which needs it to avoid resizing the pane's live terminal.
    /// None of the other 11 kinds fit -- this is a local failure before any
    /// wire connection is even attempted, not a wire-level I/O/protocol
    /// issue (`Io`/`Protocol`) or a server-side rejection
    /// (`AttachRejected`). Kind: `winsize_unavailable`.
    WinsizeUnavailable(String),
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
            RunError::RenderRejected(_) => "render_rejected",
            RunError::AttachRejected(_) => "attach_rejected",
            RunError::Busy => "busy",
            RunError::UnsupportedScroll => "unsupported_scroll",
            RunError::WinsizeUnavailable(_) => "winsize_unavailable",
        };
        // The detail is macro-safe: only the reason string (no path/payload/content).
        serde_json::to_string(&serde_json::json!({ "error": kind }))
            .unwrap_or_else(|_| r#"{"error":"internal"}"#.to_owned())
    }
}

/// Connects to the socket and observes, returning the first cursor.
pub fn run(params: &Params) -> Result<CaretOutput, RunError> {
    if !is_caret_protocol_supported(params.protocol) {
        return Err(RunError::Usage("unsupported protocol".to_owned()));
    }
    let stream = UnixStream::connect(&params.socket).map_err(|_| RunError::Connect)?;
    let base = Duration::from_millis(params.timeout_ms);
    stream
        .set_read_timeout(Some(base))
        .map_err(|_| RunError::Io)?;
    let deadline = Instant::now() + base;

    match params.protocol {
        17 => run_observe17(stream, params, deadline),
        20 => run_observe20(stream, params, deadline),
        22 => run_observe22(stream, params, deadline),
        // `is_caret_protocol_supported` (checked above) is generated from
        // `tools/herdr-protocols.json`'s `caretSupportedProtocols`, which
        // this `match` must always stay in lockstep with — any protocol
        // number the allow-list admits but this `match` doesn't handle
        // would otherwise panic here instead of failing closed.
        _ => unreachable!(
            "CARET_SUPPORTED_PROTOCOLS admitted protocol {} with no matching run_observe*",
            params.protocol
        ),
    }
}

/// Observes over protocol 22: unlike 17/20, protocol 22
/// has no `RenderEncoding::SemanticFrame`/`Frame(FrameData)` variant at all
/// so it never goes through
/// `CaretOutput::from_frame`. Instead this requests `TerminalAnsi`
/// (`ansi_runner::observe_terminal_ansi`, shared with the `hyperlinks`
/// subcommand), runs the observed frame through the same grammar tracker
/// (`tracker::track_frame`), and builds the output from its
/// trailing cursor state via the already fixture-tested
/// `CaretOutput::from_tracked_frame`. A rejected frame maps to
/// `RunError::RenderRejected`, mirroring `hyperlinks.rs::aggregate_frame`'s
/// own `TrackError` mapping — never a panic.
pub fn run_observe22(
    stream: UnixStream,
    params: &Params,
    deadline: Instant,
) -> Result<CaretOutput, RunError> {
    // Caret (protocol 22) never resolves a real pty size -- `cell_width_px: 0,
    // cell_height_px: 0` here keeps this call's Hello/Resize byte-for-byte
    // identical to before `observe_terminal_ansi` gained the cell-pixel
    // parameters, now bundled into a single `Winsize` to satisfy clippy's
    // `too_many_arguments` lint without an `#[allow]`.
    let frame = observe_terminal_ansi(
        stream,
        &params.pane,
        22,
        Winsize {
            cols: params.cols,
            rows: params.rows,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )?;
    let tracked = track_frame(&frame.bytes, frame.width, frame.height)
        .map_err(|e| RunError::RenderRejected(format!("{e:?}")))?;
    Ok(CaretOutput::from_tracked_frame(
        &tracked,
        22,
        params.pane.clone(),
        frame.width,
        frame.height,
    ))
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
        _ => {
            return Err(RunError::Protocol(
                "expected Welcome as first message".to_owned(),
            ))
        }
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
        _ => {
            return Err(RunError::Protocol(
                "expected Welcome as first message".to_owned(),
            ))
        }
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

#[cfg(test)]
mod run_error_json_tests {
    use super::RunError;

    /// One assertion per kind, so a future rename/typo in `json()` breaks a
    /// test instead of silently drifting from the documented wording.
    #[test]
    fn json_kind_matches_documented_wording() {
        let cases: &[(RunError, &str)] = &[
            (RunError::Connect, "connect_failed"),
            (RunError::Io, "io_error"),
            (RunError::Timeout, "timeout"),
            (
                RunError::WelcomeRejected("x".to_owned()),
                "welcome_rejected",
            ),
            (RunError::Protocol("x".to_owned()), "protocol_error"),
            (RunError::Bincode("x".to_owned()), "decode_error"),
            (RunError::Usage("x".to_owned()), "usage_error"),
            (RunError::RenderRejected("x".to_owned()), "render_rejected"),
            (RunError::AttachRejected("x".to_owned()), "attach_rejected"),
            (RunError::Busy, "busy"),
            (RunError::UnsupportedScroll, "unsupported_scroll"),
            (
                RunError::WinsizeUnavailable("x".to_owned()),
                "winsize_unavailable",
            ),
        ];
        for (err, expected_kind) in cases {
            assert_eq!(
                err.json(),
                format!("{{\"error\":\"{}\"}}", expected_kind),
                "kind mismatch for {:?}",
                err
            );
        }
    }
}

#[cfg(test)]
mod caret22_pure_tests {
    use super::*;

    fn tracked(
        cursor_position: Option<(u16, u16)>,
        cursor_visible: Option<bool>,
        cursor_shape: Option<u8>,
    ) -> TrackedFrame {
        TrackedFrame {
            rows: Vec::new(),
            links: Vec::new(),
            cursor_position,
            cursor_visible,
            cursor_shape,
        }
    }

    #[test]
    fn visible_cursor_with_explicit_decscusr_maps_position_and_shape() {
        let out = CaretOutput::from_tracked_frame(
            &tracked(Some((3, 7)), Some(true), Some(2)),
            22,
            "w1:p1".to_owned(),
            80,
            24,
        );
        assert_eq!(
            out,
            CaretOutput {
                cursor: Some(CursorState {
                    x: 7,
                    y: 3,
                    visible: true,
                    shape: 2
                }),
                frame_width: 80,
                frame_height: 24,
                protocol_version: 22,
                pane_id: "w1:p1".to_owned(),
            }
        );
    }

    #[test]
    fn visible_cursor_without_a_decscusr_in_this_frame_defaults_shape_to_terminal_default() {
        // herdr only writes `{n} q` when the shape *changed* from the
        // previous frame's shape (`write_host_cursor_state`) — a frame
        // whose shape didn't change from a fresh connection's baseline
        // legitimately has no DECSCUSR token at all.
        let out = CaretOutput::from_tracked_frame(
            &tracked(Some((0, 0)), Some(true), None),
            22,
            "w1:p1".to_owned(),
            80,
            24,
        );
        assert_eq!(
            out.cursor,
            Some(CursorState {
                x: 0,
                y: 0,
                visible: true,
                shape: 0
            })
        );
    }

    #[test]
    fn hidden_cursor_is_the_legitimate_null_observation_not_missing_data() {
        let out = CaretOutput::from_tracked_frame(
            &tracked(Some((5, 5)), Some(false), Some(1)),
            22,
            "w1:p1".to_owned(),
            80,
            24,
        );
        assert_eq!(out.cursor, None);
    }

    #[test]
    fn missing_visibility_token_fails_closed_to_null_not_a_guessed_position() {
        let out = CaretOutput::from_tracked_frame(
            &tracked(Some((5, 5)), None, Some(1)),
            22,
            "w1:p1".to_owned(),
            80,
            24,
        );
        assert_eq!(out.cursor, None);
    }

    #[test]
    fn missing_position_with_visible_true_fails_closed_to_null() {
        let out = CaretOutput::from_tracked_frame(
            &tracked(None, Some(true), Some(1)),
            22,
            "w1:p1".to_owned(),
            80,
            24,
        );
        assert_eq!(out.cursor, None);
    }
}
