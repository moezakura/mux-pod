//! 17/20 writable terminal attach + scroll control
//! (`AttachTerminal` -> `AttachScroll` -> `Detach`).
//!
//! Distinct from the read-only `TerminalObserve` handshake in `runner.rs`:
//! this module performs a *writable* attach (`launch_mode: TerminalAttach`)
//! so it can move the pane's shared scroll position with `AttachScroll`.
//! Always takes over (`takeover: true`) — the herdr
//! server refuses a second attach without it, and the PC-side normal UI
//! (`ClientLaunchMode::App`) never registers as an attach owner, so it can
//! never be the target of a takeover.
//!
//! Uses `requested_encoding: TerminalAnsi`, not
//! `SemanticFrame` — this connection never reads frame *content* (windows
//! are observed separately over their own connections), it
//! only needs the handshake to complete and to detect an early rejection.

use crate::error::RunError;
use crate::winsize::Winsize;
use crate::wire::*;
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

/// Direction for `AttachScroll` (wire's `direction: u8`: 0 = Up into
/// scrollback, 1 = Down towards the bottom).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScrollDirection {
    Up,
    Down,
}

impl ScrollDirection {
    fn wire_value(self) -> u8 {
        match self {
            ScrollDirection::Up => 0,
            ScrollDirection::Down => 1,
        }
    }
}

/// A writable protocol-17 attach session, open for `scroll()` calls until
/// `detach()` is called.
#[derive(Debug)]
pub struct Attach17 {
    stream: UnixStream,
}

impl Attach17 {
    /// Connects by socket path, then performs the writable-attach handshake
    /// (see `from_stream`).
    pub fn connect(
        socket: &str,
        terminal_id: &str,
        size: Winsize,
        deadline: Instant,
    ) -> Result<Self, RunError> {
        let stream = UnixStream::connect(socket).map_err(|_| RunError::Connect)?;
        Self::from_stream(stream, terminal_id, size, deadline)
    }

    /// Like `connect`, but lets the caller pick `AttachTerminal.takeover`
    /// instead of hardcoding `true`. Measurement-only: `scrollback-links` always uses
    /// takeover:true; this exists so measurement tooling can also
    /// exercise the takeover:false reject path against a *real* PC-side
    /// client without disturbing it.
    pub fn connect_with_takeover(
        socket: &str,
        terminal_id: &str,
        size: Winsize,
        takeover: bool,
        deadline: Instant,
    ) -> Result<Self, RunError> {
        let stream = UnixStream::connect(socket).map_err(|_| RunError::Connect)?;
        Self::from_stream_with_takeover(stream, terminal_id, size, takeover, deadline)
    }

    /// Performs the writable-attach handshake over an already-connected
    /// stream: `Hello` -> `Welcome` (checked) ->
    /// `AttachTerminal{takeover:true}` -> `Resize` (render kick, same
    /// dimensions as the pane) -> wait for the first sign of success
    /// (`Terminal`) or rejection (`ServerShutdown`). Split out from
    /// `connect` so loopback tests can drive the handshake over a
    /// `UnixStream::pair()` without a filesystem socket, matching
    /// `runner.rs`'s `run`/`run_observe17` split.
    ///
    /// `terminal_id` must be the pane's *resolved* terminal_id (e.g.
    /// `"term_65c85b8010f252"`, from `pane.get`'s `terminal_id` field) --
    /// **not** pane notation (e.g. `"w1:p2"`). Real herdr servers
    /// (v0.7.5/v0.8.2 `attach_terminal_client`) match `AttachTerminal`'s
    /// `terminal_id` by exact equality only; they never resolve pane
    /// notation themselves (found on a real machine -- pane
    /// notation here is unconditionally rejected with `attach_rejected`
    /// against a real server, even though the fake sockets in this crate's
    /// own unit tests don't enforce that and would previously let it pass
    /// silently).
    pub fn from_stream(
        stream: UnixStream,
        terminal_id: &str,
        size: Winsize,
        deadline: Instant,
    ) -> Result<Self, RunError> {
        Self::from_stream_with_takeover(stream, terminal_id, size, true, deadline)
    }

    /// See `from_stream`; lets the caller pick `takeover` (see
    /// `connect_with_takeover`).
    pub fn from_stream_with_takeover(
        mut stream: UnixStream,
        terminal_id: &str,
        size: Winsize,
        takeover: bool,
        deadline: Instant,
    ) -> Result<Self, RunError> {
        let Winsize {
            cols,
            rows,
            cell_width_px,
            cell_height_px,
        } = size;
        let cell_width_px: u32 = cell_width_px.into();
        let cell_height_px: u32 = cell_height_px.into();
        stream
            .set_read_timeout(Some(remaining(deadline)?))
            .map_err(|_| RunError::Io)?;

        write_frame(
            &mut stream,
            &ClientMessage17::Hello {
                version: 17,
                cols,
                rows,
                cell_width_px,
                cell_height_px,
                requested_encoding: RenderEncoding::TerminalAnsi,
                keybindings: ClientKeybindings::Server,
                launch_mode: ClientLaunchMode17::TerminalAttach,
            },
        )
        .map_err(encode_err)?;

        match read_frame_deadline::<ServerMessage17>(&stream, deadline)? {
            ServerMessage17::Welcome {
                version,
                encoding,
                error,
            } => {
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
            }
            _ => {
                return Err(RunError::Protocol(
                    "expected Welcome as first message".to_owned(),
                ))
            }
        }

        write_frame(
            &mut stream,
            &ClientMessage17::AttachTerminal {
                terminal_id: terminal_id.to_owned(),
                takeover,
            },
        )
        .map_err(encode_err)?;

        // Render kick, same dimensions as the pane itself: a differing size
        // triggers an unwanted resize (verified SIGWINCH-free
        // only when dimensions match).
        write_frame(
            &mut stream,
            &ClientMessage17::Resize {
                cols,
                rows,
                cell_width_px,
                cell_height_px,
            },
        )
        .map_err(encode_err)?;

        // Waits specifically for the first `Terminal` frame as the accept
        // signal (reverted from a broadened "first non-ServerShutdown
        // message" optimization.
        // `attach_terminal_client()` itself sends
        // nothing on accept, but `send_to_all_clients()`
        // (`src/server/headless.rs:2359` v0.7.5 / `:2682` v0.8.2, called
        // from e.g. `drain_client_config_reload_request()` ->
        // `ServerMessage::ReloadSoundConfig`) broadcasts to *every* entry
        // in `self.clients` with no filter on attach state, and a client
        // is inserted into `self.clients` at "client connected" time —
        // before `AttachTerminal` is even sent. So a broadcast can land on
        // this connection before its attach is decided, and a broadened
        // accept signal would misread that broadcast as acceptance even
        // when the attach is later rejected). Callers still confirm the
        // scroll actually moved via `pane.get` polling as a
        // safety net independent of this accept signal.
        loop {
            match read_frame_deadline::<ServerMessage17>(&stream, deadline)? {
                ServerMessage17::Terminal(_) => break,
                ServerMessage17::ServerShutdown { reason } => {
                    return Err(RunError::AttachRejected(
                        reason.unwrap_or_else(|| "attach rejected".to_owned()),
                    ));
                }
                ServerMessage17::Frame(_) => {
                    return Err(RunError::Protocol(
                        "unexpected FrameData under TerminalAnsi encoding".to_owned(),
                    ));
                }
                _ => {} // Other pushes (Notify, Clipboard, ...) are ignored.
            }
        }

        Ok(Self { stream })
    }

    /// Sends `AttachScroll` for `lines` total lines in `direction`,
    /// splitting across multiple wire messages when `lines` exceeds
    /// `u16::MAX` (the wire's `lines` field is `u16`). Does not read a
    /// response: callers confirm movement via `api_client::pane_get`
    /// polling.
    pub fn scroll(
        &mut self,
        direction: ScrollDirection,
        mut lines: u32,
        deadline: Instant,
    ) -> Result<(), RunError> {
        self.stream
            .set_write_timeout(Some(remaining(deadline)?))
            .map_err(|_| RunError::Io)?;
        while lines > 0 {
            let chunk = lines.min(u16::MAX as u32) as u16;
            write_frame(
                &mut self.stream,
                &ClientMessage17::AttachScroll {
                    source: AttachScrollSource::PageKey { input: vec![] },
                    direction: direction.wire_value(),
                    lines: chunk,
                    column: None,
                    row: None,
                    modifiers: 0,
                },
            )
            .map_err(encode_err)?;
            lines -= chunk as u32;
        }
        Ok(())
    }

    /// Sends `Detach`, best-effort (errors are swallowed: this is the
    /// cleanup step after the restore attempt, there is nothing further to
    /// do on failure). Consumes `self` so it cannot be reused afterwards.
    pub fn detach(mut self) {
        let _ = write_frame(&mut self.stream, &ClientMessage17::Detach);
    }

    /// Measurement-only: actively reads pushes until either `ServerShutdown` (returns
    /// its `reason`) or `deadline`/an I/O error (returns `None`). Unlike
    /// `attach-hold` (which never reads after attaching and so can never
    /// observe an eviction), this lets measurement tooling confirm whether a
    /// concurrent takeover actually evicted this session.
    pub fn wait_for_shutdown(&mut self, deadline: Instant) -> Option<String> {
        loop {
            match read_frame_deadline::<ServerMessage17>(&self.stream, deadline) {
                Ok(ServerMessage17::ServerShutdown { reason }) => {
                    return Some(reason.unwrap_or_else(|| "server shutdown".to_owned()))
                }
                Ok(_) => continue,
                Err(_) => return None,
            }
        }
    }
}

/// A writable protocol-20 attach session. Identical to `Attach17` except for
/// the protocol-20 message types, mirroring the existing per-protocol
/// duplication in `runner.rs` (`run_observe17`/`run_observe20`) rather than
/// a shared generic/trait abstraction.
#[derive(Debug)]
pub struct Attach20 {
    stream: UnixStream,
}

impl Attach20 {
    /// Connects by socket path, then performs the writable-attach handshake
    /// (see `from_stream`).
    pub fn connect(
        socket: &str,
        terminal_id: &str,
        size: Winsize,
        deadline: Instant,
    ) -> Result<Self, RunError> {
        let stream = UnixStream::connect(socket).map_err(|_| RunError::Connect)?;
        Self::from_stream(stream, terminal_id, size, deadline)
    }

    /// See `Attach17::connect_with_takeover`.
    pub fn connect_with_takeover(
        socket: &str,
        terminal_id: &str,
        size: Winsize,
        takeover: bool,
        deadline: Instant,
    ) -> Result<Self, RunError> {
        let stream = UnixStream::connect(socket).map_err(|_| RunError::Connect)?;
        Self::from_stream_with_takeover(stream, terminal_id, size, takeover, deadline)
    }

    /// See `Attach17::from_stream` (including the `terminal_id`-vs-pane-notation note).
    pub fn from_stream(
        stream: UnixStream,
        terminal_id: &str,
        size: Winsize,
        deadline: Instant,
    ) -> Result<Self, RunError> {
        Self::from_stream_with_takeover(stream, terminal_id, size, true, deadline)
    }

    /// See `Attach17::from_stream_with_takeover`.
    pub fn from_stream_with_takeover(
        mut stream: UnixStream,
        terminal_id: &str,
        size: Winsize,
        takeover: bool,
        deadline: Instant,
    ) -> Result<Self, RunError> {
        let Winsize {
            cols,
            rows,
            cell_width_px,
            cell_height_px,
        } = size;
        let cell_width_px: u32 = cell_width_px.into();
        let cell_height_px: u32 = cell_height_px.into();
        stream
            .set_read_timeout(Some(remaining(deadline)?))
            .map_err(|_| RunError::Io)?;

        write_frame(
            &mut stream,
            &ClientMessage20::Hello {
                version: 20,
                cols,
                rows,
                cell_width_px,
                cell_height_px,
                requested_encoding: RenderEncoding::TerminalAnsi,
                keybindings: ClientKeybindings::Server,
                launch_mode: ClientLaunchMode20::TerminalAttach,
            },
        )
        .map_err(encode_err)?;

        match read_frame_deadline::<ServerMessage20>(&stream, deadline)? {
            ServerMessage20::Welcome {
                version,
                encoding,
                error,
            } => {
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
            }
            _ => {
                return Err(RunError::Protocol(
                    "expected Welcome as first message".to_owned(),
                ))
            }
        }

        write_frame(
            &mut stream,
            &ClientMessage20::AttachTerminal {
                terminal_id: terminal_id.to_owned(),
                takeover,
            },
        )
        .map_err(encode_err)?;

        write_frame(
            &mut stream,
            &ClientMessage20::Resize {
                cols,
                rows,
                cell_width_px,
                cell_height_px,
            },
        )
        .map_err(encode_err)?;

        // See the matching comment/revert rationale in
        // `Attach17::from_stream_with_takeover` — waits specifically for a
        // `Terminal` frame (v0.8.2's `send_to_all_clients()` has the same
        // unfiltered-broadcast shape as v0.7.5).
        loop {
            match read_frame_deadline::<ServerMessage20>(&stream, deadline)? {
                ServerMessage20::Terminal(_) => break,
                ServerMessage20::ServerShutdown { reason } => {
                    return Err(RunError::AttachRejected(
                        reason.unwrap_or_else(|| "attach rejected".to_owned()),
                    ));
                }
                ServerMessage20::Frame(_) => {
                    return Err(RunError::Protocol(
                        "unexpected FrameData under TerminalAnsi encoding".to_owned(),
                    ));
                }
                _ => {}
            }
        }

        Ok(Self { stream })
    }

    pub fn scroll(
        &mut self,
        direction: ScrollDirection,
        mut lines: u32,
        deadline: Instant,
    ) -> Result<(), RunError> {
        self.stream
            .set_write_timeout(Some(remaining(deadline)?))
            .map_err(|_| RunError::Io)?;
        while lines > 0 {
            let chunk = lines.min(u16::MAX as u32) as u16;
            write_frame(
                &mut self.stream,
                &ClientMessage20::AttachScroll {
                    source: AttachScrollSource::PageKey { input: vec![] },
                    direction: direction.wire_value(),
                    lines: chunk,
                    column: None,
                    row: None,
                    modifiers: 0,
                },
            )
            .map_err(encode_err)?;
            lines -= chunk as u32;
        }
        Ok(())
    }

    pub fn detach(mut self) {
        let _ = write_frame(&mut self.stream, &ClientMessage20::Detach);
    }

    /// See `Attach17::wait_for_shutdown`.
    pub fn wait_for_shutdown(&mut self, deadline: Instant) -> Option<String> {
        loop {
            match read_frame_deadline::<ServerMessage20>(&self.stream, deadline) {
                Ok(ServerMessage20::ServerShutdown { reason }) => {
                    return Some(reason.unwrap_or_else(|| "server shutdown".to_owned()))
                }
                Ok(_) => continue,
                Err(_) => return None,
            }
        }
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

fn read_frame_deadline<M: for<'de> serde::Deserialize<'de>>(
    mut stream: &UnixStream,
    deadline: Instant,
) -> Result<M, RunError> {
    let rem = remaining(deadline)?;
    // A zero timeout would disable blocking; ensure a positive value (same
    // guard as frame_io.rs's read_frame_deadline).
    let rem = if rem.is_zero() {
        Duration::from_millis(1)
    } else {
        rem
    };
    stream
        .set_read_timeout(Some(rem))
        .map_err(|_| RunError::Io)?;
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
