//! TerminalAnsi observe runner shared across protocols 17, 20, and 22.
//!
//! Unlike `runner::run_observe17`/`run_observe20` (which request
//! `RenderEncoding::SemanticFrame` and wait for a `Frame(FrameData)`), this
//! module requests `RenderEncoding::TerminalAnsi` and waits for a
//! `Terminal(TerminalFrame)` — the encoding the hyperlink tracker and
//! the protocol-22 caret both consume.

use crate::error::RunError;
use crate::frame_io::{encode_err, read_frame_bytes_deadline, read_frame_deadline};
use crate::winsize::Winsize;
use crate::wire::{
    write_frame, ClientKeybindings, ClientLaunchMode17, ClientLaunchMode20, ClientMessage17,
    ClientMessage20, RenderEncoding, ServerMessage17, ServerMessage20, TerminalFrame,
};
use crate::wire22::{ClientMessage22, ServerMessage22Known};
use std::os::unix::net::UnixStream;
use std::time::Instant;

/// Observes a single TerminalAnsi frame over an already-connected stream.
///
/// Connecting the socket is the caller's responsibility (mirrors
/// `runner::run_observe17`/`run_observe20`): this keeps the function
/// loopback-testable with `UnixStream::pair()` mock servers, and lets a
/// caller that opens several connections in turn (e.g. `scrollback-links`'s
/// per-window observes) share one overall `deadline` across all of them
/// instead of resetting a fresh timeout per connection.
///
/// `size`:
/// every call site previously passed `cols, rows` plus `cell_width_px: 0,
/// cell_height_px: 0` (no pixel geometry) as four separate parameters;
/// this bundles them into one `winsize::Winsize`
/// value (clippy's `too_many_arguments` on the previous 8-parameter form,
/// resolved by bundling rather than `#[allow]`). A caller that resolved
/// the real pty's pixel geometry (`winsize::real_size`,
/// `hyperlinks::resolve_dimensions`, scrollback-links' fail-closed
/// resolution in `scrollback/position.rs`) passes that `Winsize`. A caller
/// with nothing resolved (the plain caret path, protocol 22, via
/// `runner::run_observe22`) passes `Winsize { cell_width_px: 0,
/// cell_height_px: 0, .. }` explicitly, keeping its Hello/Resize
/// byte-for-byte unchanged.
///
/// No argument is ever null (`pane` is borrowed; the rest are plain
/// values). Returns `Err(RunError)` on any failure; never panics.
/// Synchronous, blocking I/O bounded by `deadline`. The only side effect
/// is reading from and writing to the given socket — a read-only
/// terminal observation (no `Input`, `ControlTerminal`, or attach
/// messages are ever sent).
///
/// Checks `TerminalFrame.full` here (it must be `true` before the frame goes
/// through the tracker; `full == false` is a `render_rejected` failure)
/// rather than leaving it to
/// each caller (`hyperlinks`, caret 22, `scrollback-links`), so the check
/// cannot be forgotten or duplicated at a call site.
pub fn observe_terminal_ansi(
    stream: UnixStream,
    pane: &str,
    protocol: u8,
    size: Winsize,
    deadline: Instant,
) -> Result<TerminalFrame, RunError> {
    let frame = match protocol {
        17 => observe17_ansi(stream, pane, size, deadline),
        20 => observe20_ansi(stream, pane, size, deadline),
        22 => observe22_ansi(stream, pane, size, deadline),
        _ => Err(RunError::Usage("unsupported protocol".to_owned())),
    }?;
    if !frame.full {
        return Err(RunError::RenderRejected(
            "observed TerminalAnsi frame was not a full redraw".to_owned(),
        ));
    }
    Ok(frame)
}

/// Observes over protocol 17 with `requested_encoding: TerminalAnsi`.
fn observe17_ansi(
    mut stream: UnixStream,
    pane: &str,
    size: Winsize,
    deadline: Instant,
) -> Result<TerminalFrame, RunError> {
    let hello = ClientMessage17::Hello {
        version: 17,
        cols: size.cols,
        rows: size.rows,
        cell_width_px: size.cell_width_px.into(),
        cell_height_px: size.cell_height_px.into(),
        requested_encoding: RenderEncoding::TerminalAnsi,
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
    if encoding != RenderEncoding::TerminalAnsi {
        return Err(RunError::Protocol("unexpected render encoding".to_owned()));
    }

    write_frame(
        &mut stream,
        &ClientMessage17::ObserveTerminal {
            target: pane.to_owned(),
        },
    )
    .map_err(encode_err)?;

    // Render kick, same role as in runner::run_observe17.
    write_frame(
        &mut stream,
        &ClientMessage17::Resize {
            cols: size.cols,
            rows: size.rows,
            cell_width_px: size.cell_width_px.into(),
            cell_height_px: size.cell_height_px.into(),
        },
    )
    .map_err(encode_err)?;

    loop {
        let msg: ServerMessage17 = read_frame_deadline(&stream, deadline)?;
        match msg {
            ServerMessage17::Terminal(frame) => return Ok(frame),
            // A TerminalAnsi request must never receive SemanticFrame data;
            // herdr changing encoding out from under a validated Welcome is a
            // protocol violation, not a legitimate "no frame yet" case.
            ServerMessage17::Frame(_) => {
                return Err(RunError::Protocol(
                    "server sent SemanticFrame data for a TerminalAnsi request".to_owned(),
                ))
            }
            // Any other real, fully-decoded message (Notify, WindowTitle,
            // ReloadSoundConfig, ...): not the frame we're waiting for.
            _ => continue,
        }
    }
}

/// Observes over protocol 20 with `requested_encoding: TerminalAnsi`.
fn observe20_ansi(
    mut stream: UnixStream,
    pane: &str,
    size: Winsize,
    deadline: Instant,
) -> Result<TerminalFrame, RunError> {
    let hello = ClientMessage20::Hello {
        version: 20,
        cols: size.cols,
        rows: size.rows,
        cell_width_px: size.cell_width_px.into(),
        cell_height_px: size.cell_height_px.into(),
        requested_encoding: RenderEncoding::TerminalAnsi,
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
    if encoding != RenderEncoding::TerminalAnsi {
        return Err(RunError::Protocol("unexpected render encoding".to_owned()));
    }

    write_frame(
        &mut stream,
        &ClientMessage20::ObserveTerminal {
            target: pane.to_owned(),
        },
    )
    .map_err(encode_err)?;

    write_frame(
        &mut stream,
        &ClientMessage20::Resize {
            cols: size.cols,
            rows: size.rows,
            cell_width_px: size.cell_width_px.into(),
            cell_height_px: size.cell_height_px.into(),
        },
    )
    .map_err(encode_err)?;

    loop {
        let msg: ServerMessage20 = read_frame_deadline(&stream, deadline)?;
        match msg {
            ServerMessage20::Terminal(frame) => return Ok(frame),
            ServerMessage20::Frame(_) => {
                return Err(RunError::Protocol(
                    "server sent SemanticFrame data for a TerminalAnsi request".to_owned(),
                ))
            }
            _ => continue,
        }
    }
}

/// Observes over protocol 22 (`TerminalHello` always negotiates TerminalAnsi
/// server-side; there is no SemanticFrame option for direct terminal
/// clients on this protocol).
fn observe22_ansi(
    mut stream: UnixStream,
    pane: &str,
    size: Winsize,
    deadline: Instant,
) -> Result<TerminalFrame, RunError> {
    let hello = ClientMessage22::TerminalHello {
        version: 22,
        cols: size.cols,
        rows: size.rows,
        cell_width_px: size.cell_width_px.into(),
        cell_height_px: size.cell_height_px.into(),
        pixel_mouse: false,
    };
    write_frame(&mut stream, &hello).map_err(encode_err)?;

    let first = decode_known22(&read_frame_bytes_deadline(&stream, deadline)?)?;
    let (version, encoding, error) = match first {
        Some(ServerMessage22Known::Welcome {
            version,
            encoding,
            error,
        }) => (version, encoding, error),
        _ => {
            return Err(RunError::Protocol(
                "expected Welcome as first message".to_owned(),
            ))
        }
    };
    if let Some(e) = error {
        return Err(RunError::WelcomeRejected(e));
    }
    if version != 22 {
        return Err(RunError::Protocol(format!(
            "server protocol mismatch: got {}, expected 22",
            version
        )));
    }
    if encoding != RenderEncoding::TerminalAnsi {
        return Err(RunError::Protocol("unexpected render encoding".to_owned()));
    }

    write_frame(
        &mut stream,
        &ClientMessage22::ObserveTerminal {
            target: pane.to_owned(),
        },
    )
    .map_err(encode_err)?;

    write_frame(
        &mut stream,
        &ClientMessage22::Resize {
            cols: size.cols,
            rows: size.rows,
            cell_width_px: size.cell_width_px.into(),
            cell_height_px: size.cell_height_px.into(),
            pixel_mouse: false,
        },
    )
    .map_err(encode_err)?;

    loop {
        let bytes = read_frame_bytes_deadline(&stream, deadline)?;
        match decode_known22(&bytes)? {
            Some(ServerMessage22Known::Terminal(frame)) => return Ok(frame),
            // A stray repeated Welcome (should not happen after a validated
            // handshake, but is not the frame we're waiting for either).
            Some(ServerMessage22Known::Welcome { .. }) => continue,
            // A real `ServerMessage` variant this helper does not decode
            // (Notify/WindowTitle/MouseCapture/...). `bytes` was already
            // fully read as one length-framed unit by
            // `read_frame_bytes_deadline`, so discarding it here never
            // misaligns the stream — the next `read_frame_bytes_deadline`
            // call starts cleanly at the next frame's length prefix.
            None => continue,
        }
    }
}

/// Attempts to decode one already length-framed payload as the reduced
/// `ServerMessage22Known` (`Welcome`/`Terminal` only).
///
/// Returns `Ok(None)` only when the *outer* tag itself is not 0 (`Welcome`)
/// or 1 (`Terminal`) — a real, well-formed `ServerMessage` variant this
/// helper does not decode (`Notify`, `WindowTitle`, ...). Any other decode
/// failure is a genuine fault and is returned as `Err`, never silently
/// skipped: bincode's own decode error for "variant index out of range"
/// (`serde`'s `invalid_value`, routed through `DecodeError::custom` ->
/// `OtherString`) is indistinguishable in shape from a failure while
/// decoding a *nested* enum inside an already-tag-0/1 message (e.g. a
/// corrupt `RenderEncoding` field inside a genuine `Welcome`), so the outer
/// tag must be inspected before attempting the full decode, not inferred
/// from whatever error the attempt produces. Silently skipping a
/// known-tag-but-malformed frame would hide the real fault until the
/// deadline's timeout, which is exactly what this check prevents.
///
/// The outer tag is always the payload's first byte for both types here:
/// `bincode::config::standard()`'s varint integer encoding (which the
/// `u32` enum-variant discriminant also goes through — see `EnumAccess::
/// variant_seed` in bincode's serde support) writes values 0..=250 as a
/// single literal byte, and both `ClientMessage22`/`ServerMessage22Known`
/// have at most 21 variants, always well under that threshold (already
/// exercised by every exact-byte codec test in this crate).
fn decode_known22(payload: &[u8]) -> Result<Option<ServerMessage22Known>, RunError> {
    match payload.first() {
        Some(0) | Some(1) => {
            match bincode::serde::decode_from_slice::<ServerMessage22Known, _>(
                payload,
                bincode::config::standard(),
            ) {
                Ok((msg, consumed)) if consumed == payload.len() => Ok(Some(msg)),
                Ok(_) => Err(RunError::Bincode(
                    "trailing_bytes: known ServerMessage22 variant did not consume the whole frame"
                        .to_owned(),
                )),
                Err(e) => Err(RunError::Bincode(format!("decode_error: {e}"))),
            }
        }
        Some(_) => Ok(None),
        None => Err(RunError::Bincode("decode_error: empty frame".to_owned())),
    }
}
