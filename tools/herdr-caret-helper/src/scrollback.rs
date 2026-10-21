//! `scrollback-links` subcommand.
//!
//! Argument parsing (`ScrollbackParams`) and the per-pane lock file
//! (`acquire_lock`), followed by the observe/move/restore round trip.

use crate::ansi_runner::observe_terminal_ansi;
use crate::error::RunError;
use crate::hyperlinks::{aggregate_frame, sanitize_links, AggregatedLink};
use serde::Serialize;
use std::collections::HashSet;
use std::fs::{DirBuilder, OpenOptions};
use std::os::unix::fs::DirBuilderExt;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};

mod args;

pub use args::{parse_args, ScrollbackParams};
#[cfg(test)]
use args::{DEFAULT_MAX_OUTPUT_BYTES, DEFAULT_RESTORE_BUDGET_MS, DEFAULT_TIMEOUT_MS};

/// Holds the per-pane exclusive lock for the lifetime of one
/// `scrollback-links` invocation. Dropping it (including on panic or
/// process exit) releases the OS-level lock automatically — no stale
/// lock can be left behind by a crash.
pub struct ScrollbackLock {
    _file: std::fs::File,
}

fn lock_file_path(lock_dir: &str, api_socket: &str, pane: &str) -> PathBuf {
    // `<fnv1a64(apiSocket + NUL + paneId)>.lock`.
    let mut bytes = Vec::with_capacity(api_socket.len() + 1 + pane.len());
    bytes.extend_from_slice(api_socket.as_bytes());
    bytes.push(0);
    bytes.extend_from_slice(pane.as_bytes());
    let name = crate::tracker::fnv1a64_hex(&bytes);
    Path::new(lock_dir).join(format!("{name}.lock"))
}

/// Acquires the per-pane lock: creates `lock_dir` with mode 0700 if it
/// does not already exist (an existing directory's permissions are left
/// untouched — `DirBuilder::create` with `recursive(true)` is a no-op on
/// an already-existing directory and does not chmod it, verified against
/// this toolchain), then opens (create-if-missing, **not** truncating —
/// `OpenOptions` without `.truncate(true)`) the lock file and takes a
/// non-blocking exclusive lock via `File::try_lock` (stable since Rust
/// 1.89; toolchain here is 1.94.1, `rust-toolchain.toml`).
///
/// Failure classification: a directory creation I/O failure (e.g. permission
/// denied) is `RunError::Io` (`io_error`); *only* `try_lock` contention
/// (`TryLockError::WouldBlock`, another `scrollback-links` invocation
/// already holds it for this pane) is `RunError::Busy` (`busy`). Any other
/// `try_lock` failure (`TryLockError::Error`, e.g. `ENOLCK`, a filesystem
/// that does not support locking) is `RunError::Io`, not `Busy` — the
/// caller must not blindly retry an unrelated I/O failure as if it were
/// ordinary contention.
pub fn acquire_lock(
    lock_dir: &str,
    api_socket: &str,
    pane: &str,
) -> Result<ScrollbackLock, RunError> {
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(lock_dir)
        .map_err(|_| RunError::Io)?;

    let path = lock_file_path(lock_dir, api_socket, pane);
    let file = OpenOptions::new()
        .create(true)
        .write(true)
        // Explicitly false (not the default's ambiguity): a re-run must
        // never wipe the lock file's contents, only `try_lock()` it below.
        .truncate(false)
        .open(&path)
        .map_err(|_| RunError::Io)?;
    classify_try_lock_result(file.try_lock())?;
    Ok(ScrollbackLock { _file: file })
}

fn classify_try_lock_result(result: Result<(), std::fs::TryLockError>) -> Result<(), RunError> {
    match result {
        Ok(()) => Ok(()),
        Err(std::fs::TryLockError::WouldBlock) => Err(RunError::Busy),
        Err(std::fs::TryLockError::Error(_)) => Err(RunError::Io),
    }
}

// ---------------------------------------------------------------------------
// Original position + move to a target window.
// ---------------------------------------------------------------------------

/// How many times, and how often, `pane.get` is polled to confirm a scroll
/// move actually landed (20ms x up to 10 attempts -- 200ms worst case).
const SCROLL_POLL_INTERVAL: std::time::Duration = std::time::Duration::from_millis(20);
const SCROLL_POLL_MAX_ATTEMPTS: u32 = 10;

/// The pane's scroll position, viewport height, and resolved terminal_id,
/// recorded once before any movement (`o0` in `restore_position`). `viewport_rows` also
/// becomes the row count used for 17/20's attach `Hello`/`Resize` (taken
/// from `pane.get`'s `scroll.viewport_rows`, not from the caller).
/// `terminal_id` is `open_round_trip`'s source of truth for
/// `AttachTerminal.terminal_id`: real
/// herdr servers (v0.7.5/v0.8.2 `attach_terminal_client`) match
/// `terminal_id` by exact equality only -- they never resolve pane notation
/// (`params.pane`, e.g. "w1:p2") themselves, so sending the pane notation
/// there is always rejected (`attach_rejected`) against a real server. Not
/// `Copy` (unlike before): `terminal_id: String` isn't `Copy`, and every use
/// site already goes through `&OriginalPosition`, never a bare copy.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OriginalPosition {
    pub offset_from_bottom: u64,
    /// Added for the 17/20 `o0 == 0 && max_offset_from_bottom > 0` guard
    /// (PageKey scrolling is only ever
    /// attempted when there is scrollback to move into *and* the pane
    /// is already at the bottom). Read from the same `pane.get` call as
    /// `offset_from_bottom`, so this adds no extra round trip.
    pub max_offset_from_bottom: u64,
    pub viewport_rows: u64,
    pub terminal_id: String,
}

/// Reads `pane.get` once and extracts the scroll state and terminal_id. A
/// pane with no `scroll` field is `unsupported_scroll`, not
/// `RunError::Protocol` (`protocol_error`), which would be the wrong
/// `RunError::json()` kind for this specific case.
pub fn record_original_position(
    api_socket: &str,
    pane: &str,
    deadline: std::time::Instant,
) -> Result<OriginalPosition, RunError> {
    let info = crate::api_client::pane_get(api_socket, pane, deadline)?;
    let scroll = info.scroll.ok_or(RunError::UnsupportedScroll)?;
    Ok(OriginalPosition {
        offset_from_bottom: scroll.offset_from_bottom,
        max_offset_from_bottom: scroll.max_offset_from_bottom,
        viewport_rows: scroll.viewport_rows,
        terminal_id: info.terminal_id,
    })
}

/// Resolves the real size for 17/20: `pane.process_info` -> `shell_pid` ->
/// `winsize::real_size`, fail-closed at every step. Any
/// failure here must abort the *whole* `scrollback-links` run without ever
/// attaching -- the caller propagates this `Err` directly, it does not fall
/// back to `params.cols`/`fallback_rows`. The resulting `Winsize` is reused
/// as-is for this run's attach `Hello`/`Resize` and every window's
/// `observe_terminal_ansi` call (the helper reads the real size itself;
/// `--cols` is no longer trusted blindly).
fn resolve_size_fail_closed(
    api_socket: &str,
    pane: &str,
    deadline: std::time::Instant,
) -> Result<crate::winsize::Winsize, RunError> {
    let info = crate::api_client::pane_process_info(api_socket, pane, deadline)?;
    let shell_pid = info.shell_pid.ok_or_else(|| {
        RunError::WinsizeUnavailable("pane.process_info returned no shell_pid".to_owned())
    })?;
    crate::winsize::real_size(shell_pid).map_err(|e| RunError::WinsizeUnavailable(format!("{e:?}")))
}

/// Resolves the real size for protocol 22: same `pane.process_info` ->
/// `winsize::real_size` path, but fail-*open* -- any failure at any step
/// falls back to `(fallback_cols, fallback_rows, 0, 0)` instead of erroring
/// (22 has no attach to protect; this mirrors
/// `hyperlinks.rs`'s own `resolve_dimensions`).
fn resolve_size_fail_open(
    api_socket: &str,
    pane: &str,
    fallback_cols: u16,
    fallback_rows: u16,
    deadline: std::time::Instant,
) -> crate::winsize::Winsize {
    let fallback = crate::winsize::Winsize {
        cols: fallback_cols,
        rows: fallback_rows,
        cell_width_px: 0,
        cell_height_px: 0,
    };
    let Ok(info) = crate::api_client::pane_process_info(api_socket, pane, deadline) else {
        return fallback;
    };
    let Some(shell_pid) = info.shell_pid else {
        return fallback;
    };
    crate::winsize::real_size(shell_pid).unwrap_or(fallback)
}

/// Polls `pane.get` (up to `SCROLL_POLL_MAX_ATTEMPTS` times, `SCROLL_POLL_INTERVAL`
/// apart) until `done` accepts the observed `ScrollInfo`, then returns it.
/// If `done` never accepts within the budget, returns the *last* observed
/// `ScrollInfo` rather than erroring — the caller decides how
/// to treat a position that never reached its target (e.g. a concurrent
/// PC-side input resetting to the bottom, the `skipped_reset` case);
/// this function's job is only to report the real, current position.
fn poll_scroll_until<F>(
    api_socket: &str,
    pane: &str,
    deadline: std::time::Instant,
    mut done: F,
) -> Result<crate::api_client::ScrollInfo, RunError>
where
    F: FnMut(&crate::api_client::ScrollInfo) -> bool,
{
    let mut last = None;
    for attempt in 0..SCROLL_POLL_MAX_ATTEMPTS {
        let info = crate::api_client::pane_get(api_socket, pane, deadline)?;
        let scroll = info.scroll.ok_or(RunError::UnsupportedScroll)?;
        if done(&scroll) {
            return Ok(scroll);
        }
        last = Some(scroll);
        if attempt + 1 < SCROLL_POLL_MAX_ATTEMPTS {
            std::thread::sleep(SCROLL_POLL_INTERVAL);
        }
    }
    last.ok_or(RunError::UnsupportedScroll)
}

/// Kept-open connection state for the whole `scrollback-links` round trip
/// (all windows). Protocol 22 needs nothing beyond the JSON API (each
/// `pane.scroll` call is a standalone round trip); 17/20 need one writable
/// `AttachTerminal` session held open across every window so the
/// (takeover) handshake only happens once. This attach connection is
/// used only for scrolling, separate from the per-window
/// observe connections.
pub enum RoundTripHandle {
    Api,
    Attach17(crate::attach::Attach17),
    Attach20(crate::attach::Attach20),
}

/// Opens whatever connection state `params.protocol` needs for movement.
/// For 17/20 this performs the writable attach handshake up front, using
/// `size` (the real, resolved terminal size -- `resolve_size_fail_closed`'s
/// result; `params.cols` is
/// no longer used for 17/20's Hello/Resize) and `original.terminal_id`
/// (already resolved by `record_original_position`'s `pane.get`, no extra
/// round trip) as `AttachTerminal.terminal_id` -- **not** `params.pane`
/// (see `OriginalPosition`'s doc
/// comment). Restore's own `pane.get`/`pane.scroll` calls are unaffected
/// and keep using `params.pane` (pane notation), which is what those JSON
/// API methods expect. Protocol 22 ignores `size` entirely (it has no
/// attach to size).
pub fn open_round_trip(
    params: &ScrollbackParams,
    original: &OriginalPosition,
    size: crate::winsize::Winsize,
    deadline: std::time::Instant,
) -> Result<RoundTripHandle, RunError> {
    match params.protocol {
        22 => Ok(RoundTripHandle::Api),
        17 => {
            let session = crate::attach::Attach17::connect(
                &params.socket,
                &original.terminal_id,
                size,
                deadline,
            )?;
            Ok(RoundTripHandle::Attach17(session))
        }
        20 => {
            let session = crate::attach::Attach20::connect(
                &params.socket,
                &original.terminal_id,
                size,
                deadline,
            )?;
            Ok(RoundTripHandle::Attach20(session))
        }
        // `parse_args` already rejected anything outside the allow-list
        // (usage_error, before any connection is attempted).
        other => Err(RunError::Protocol(format!("unsupported protocol {other}"))),
    }
}

/// Detaches the held attach session, if any (protocol 22 is a no-op: it
/// never held one).
pub fn close_round_trip(handle: RoundTripHandle) {
    match handle {
        RoundTripHandle::Api => {}
        RoundTripHandle::Attach17(session) => session.detach(),
        RoundTripHandle::Attach20(session) => session.detach(),
    }
}

/// Translates an absolute `current -> target` move into the relative
/// `AttachScroll` direction/line-count 17/20 need (`offset_from_bottom`
/// increasing = further from the bottom = further *up* into scrollback).
fn relative_scroll_of(current: u64, target: u64) -> Option<(crate::attach::ScrollDirection, u32)> {
    use crate::attach::ScrollDirection;
    if target > current {
        Some((
            ScrollDirection::Up,
            (target - current).min(u32::MAX as u64) as u32,
        ))
    } else if target < current {
        Some((
            ScrollDirection::Down,
            (current - target).min(u32::MAX as u64) as u32,
        ))
    } else {
        None
    }
}

/// True once a 17/20 `AttachScroll` move in `direction` can be considered
/// confirmed: the position has moved away from where it started, or
/// scrollback's own end *in that direction* was reached (`max_offset_from_bottom`
/// for `Up`, `0` for `Down`).
///
/// An earlier version of this check
/// accepted `offset_from_bottom == max_offset_from_bottom` regardless of
/// `direction`. That is wrong when the move starts *at* the max (e.g. the
/// previous window already scrolled to the oldest scrollback line) and
/// this move is `Down` (back towards the bottom): the very first poll,
/// taken before the just-sent `AttachScroll` has had any effect, still
/// reads `offset_from_bottom == started_at == max_offset_from_bottom`, so
/// the old check would report "settled" immediately without the position
/// having moved at all — a real path (the next window's move, or a
/// non-bottom restore, right after a window that scrolled all the way
/// back). Gating the end-of-scrollback shortcut on `direction` closes
/// this: a `Down` move only shortcuts on reaching `0`, so an unmoved
/// `offset_from_bottom == max` no longer satisfies it, and the loop
/// correctly waits for the next poll to observe the real change.
fn scroll_settled(
    current: &crate::api_client::ScrollInfo,
    started_at: u64,
    direction: crate::attach::ScrollDirection,
) -> bool {
    if current.offset_from_bottom != started_at {
        return true;
    }
    match direction {
        crate::attach::ScrollDirection::Up => {
            current.offset_from_bottom == current.max_offset_from_bottom
        }
        crate::attach::ScrollDirection::Down => current.offset_from_bottom == 0,
    }
}

/// Moves the pane's shared scroll position to `target_offset_from_bottom`
/// (absolute), confirms the move via `pane.get` polling, and
/// returns the confirmed resulting `ScrollInfo` — which may differ from
/// the requested target (e.g. clamped at `max_offset_from_bottom`, or
/// reset to the bottom by concurrent PC-side input).
///
/// Protocol 22: `pane.scroll` already returns the resulting state in one
/// round trip; the poll loop here is a defensive re-check that the
/// position has actually settled, not the primary confirmation.
/// Protocols 17/20: `AttachScroll` sends no response (`attach.rs`'s
/// `scroll()` doc comment), so the poll loop is the *only* confirmation.
/// The confirmation condition used to require
/// an exact `offset_from_bottom == target_offset_from_bottom` match, but
/// it is enough to confirm that the position *changed* before observing
/// — herdr may round/clamp at either end
/// of scrollback, or the position may keep moving under concurrent output
/// (`o1 = t + k` in `restore_position`), so an exact match can spuriously exhaust every
/// poll attempt (200ms × up to 3 windows) even though the move already
/// took effect. `scroll_settled` above accepts either "moved away from
/// where it started" or "hit the end of scrollback in the direction being
/// moved".
/// Returns `(attempted, result)`: `attempted` is `true` iff an actual scroll
/// command was dispatched over the wire (`pane.scroll` for protocol 22 --
/// which has no "already there" skip, so it always dispatches -- or
/// `AttachScroll` for 17/20, only when `relative_scroll_of` found a nonzero
/// delta to send). It stays `true` even if `result` is `Err` -- a send that
/// succeeded but whose *confirmation* poll then failed still means the pane
/// may have actually moved server-side (restore's finally-equivalent
/// restore guarantee: callers must not use `current_offset_from_bottom`
/// staying unchanged on error as a proxy for "nothing moved").
pub fn move_to_offset(
    handle: &mut RoundTripHandle,
    api_socket: &str,
    pane: &str,
    current_offset_from_bottom: u64,
    target_offset_from_bottom: u64,
    deadline: std::time::Instant,
) -> (bool, Result<crate::api_client::ScrollInfo, RunError>) {
    match handle {
        RoundTripHandle::Api => {
            // protocol 22 always dispatches `pane.scroll`, even when
            // target == current -- every call here is an attempted send.
            let result = (|| {
                let info = crate::api_client::pane_scroll(
                    api_socket,
                    pane,
                    target_offset_from_bottom,
                    deadline,
                )?;
                let confirmed = info.scroll.ok_or(RunError::UnsupportedScroll)?;
                poll_scroll_until(api_socket, pane, deadline, |s| {
                    s.offset_from_bottom == confirmed.offset_from_bottom
                })
            })();
            (true, result)
        }
        RoundTripHandle::Attach17(session) => {
            match relative_scroll_of(current_offset_from_bottom, target_offset_from_bottom) {
                None => (
                    false,
                    poll_scroll_until(api_socket, pane, deadline, |s| {
                        s.offset_from_bottom == current_offset_from_bottom
                    }),
                ),
                Some((direction, lines)) => {
                    let result = (|| {
                        session.scroll(direction, lines, deadline)?;
                        poll_scroll_until(api_socket, pane, deadline, |s| {
                            scroll_settled(s, current_offset_from_bottom, direction)
                        })
                    })();
                    (true, result)
                }
            }
        }
        RoundTripHandle::Attach20(session) => {
            match relative_scroll_of(current_offset_from_bottom, target_offset_from_bottom) {
                None => (
                    false,
                    poll_scroll_until(api_socket, pane, deadline, |s| {
                        s.offset_from_bottom == current_offset_from_bottom
                    }),
                ),
                Some((direction, lines)) => {
                    let result = (|| {
                        session.scroll(direction, lines, deadline)?;
                        poll_scroll_until(api_socket, pane, deadline, |s| {
                            scroll_settled(s, current_offset_from_bottom, direction)
                        })
                    })();
                    (true, result)
                }
            }
        }
    }
}

// --- Per-window observation + tracker integration + JSON assembly
// (`restore` classification's straight-line form; the finally-equivalent
// guarantee that restore always runs regardless of which step failed lives in
// `run_scrollback_links`). ---

/// Opens a fresh observe connection for one window (kept
/// deliberately separate from the movement/attach connection in
/// `RoundTripHandle` — an attach connection only ever receives differential
/// frames after the first one), reads its
/// one full `TerminalAnsi` frame, and runs it through the shared tracker +
/// aggregation pipeline (`hyperlinks::aggregate_frame`, reused
/// verbatim rather than reimplemented). `rows` is `original.viewport_rows`
/// (taken from `pane.get`'s `scroll.viewport_rows`), not `cols`/`rows` from
/// caret's `max(width, 80)` rule.
fn observe_window(
    params: &ScrollbackParams,
    size: crate::winsize::Winsize,
    deadline: std::time::Instant,
) -> Result<WindowObservation, RunError> {
    let stream = UnixStream::connect(&params.socket).map_err(|_| RunError::Connect)?;
    let frame = match observe_terminal_ansi(stream, &params.pane, params.protocol, size, deadline) {
        Ok(frame) => frame,
        // A frame that is not a full redraw rejects this window only; no
        // frame exists, so the size used for the observation is reported.
        Err(RunError::RenderRejected(_)) => {
            return Ok(WindowObservation::Rejected {
                width: size.cols,
                height: size.rows,
            })
        }
        Err(e) => return Err(e),
    };
    match aggregate_frame(&frame.bytes, frame.width, frame.height) {
        Ok(links) => Ok(WindowObservation::Observed {
            links,
            width: frame.width,
            height: frame.height,
        }),
        Err(_) => Ok(WindowObservation::Rejected {
            width: frame.width,
            height: frame.height,
        }),
    }
}

/// `observe_window`'s result. Only a rendering rejection (not a full
/// redraw, or a grammar rejection by the tracker) is localized to the
/// window; connection/protocol/timeout errors still fail the whole run.
enum WindowObservation {
    Observed {
        links: crate::hyperlinks::FrameLinks,
        width: u16,
        height: u16,
    },
    /// `width`/`height`: the observed frame's own size for a tracker
    /// rejection; the requested size for a non-full frame.
    Rejected { width: u16, height: u16 },
}

/// One window's fully-assembled, pre-truncation result (the
/// `windows[]` element, before `--max-output-bytes` packing is applied).
#[derive(Debug, Clone)]
struct WindowFetch {
    requested_offset: u64,
    actual_offset: u64,
    frame_width: u16,
    frame_height: u16,
    links: Vec<AggregatedLink>,
    row_hashes: Vec<(u16, String)>,
    /// The window's frame was rejected (`WindowObservation::Rejected`):
    /// emitted as an empty window with `truncated: true`.
    rejected: bool,
}

/// Outcome classification for the position-restore step —
/// the JSON contract's `restore` field. A failed restore is not
/// itself a `scrollback-links` failure (the window data already collected
/// is still returned; the pane is simply left scrolled);
/// it is reported through this classification instead of `RunError`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RestoreOutcome {
    Exact,
    Approximate,
    SkippedReset,
    Failed,
}

impl RestoreOutcome {
    fn as_json_str(self) -> &'static str {
        match self {
            RestoreOutcome::Exact => "exact",
            RestoreOutcome::Approximate => "approximate",
            RestoreOutcome::SkippedReset => "skipped_reset",
            RestoreOutcome::Failed => "failed",
        }
    }
}

/// Groups `restore_position`'s inputs beyond the connection/target
/// arguments, purely to keep its argument count within clippy's limit. See
/// `restore_position`'s doc comment for what each field means.
struct RestorePlan {
    o0: u64,
    t: u64,
    moved: bool,
    last_move_confirmed: bool,
}

/// Restores the pane's shared scroll position (see the branches below).
/// `o0` = position before any movement (`OriginalPosition::offset_from_bottom`),
/// `t` = the position the round trip's final window move was *aiming for*
/// (used only for the approximate-restore delta calculation below) -- the
/// *confirmed* offset when that move's poll succeeded, or the *attempted*
/// target when it didn't (`run_scrollback_links` keeps `t` accurate for
/// both cases; see its loop).
///
/// `moved` = whether a scroll command was *attempted to be sent* at least
/// once (see `move_to_offset`'s return) -- the finally-equivalent
/// guarantee is judged on this, not on `t`/observed-position comparisons.
/// When `moved` is `false`, no restore command is sent at all --
/// classification is `exact` (after confirming via `pane.get`) only when
/// `o0 == 0`, and `approximate` for any `o0 > 0` (the
/// contract's `exact` is reserved for "was at the bottom and confirmed back
/// at the bottom").
///
/// `last_move_confirmed` = whether the *last attempted* move's own poll
/// actually observed a definitive resulting position (`Ok` from
/// `move_to_offset`), as opposed to that poll itself hitting the deadline
/// (`Err`). This matters because `AttachScroll` (17/20) and `pane.get` (the
/// restore's own read of `o1`) travel over *different* sockets with no
/// ordering guarantee between them: if the last
/// move's own confirmation never landed, reading `o1 == 0` here could be a
/// stale pre-effect snapshot rather than a genuine concurrent reset, so
/// `skipped_reset` (which sends nothing) must not be reached in that case --
/// restore is sent unconditionally instead, regardless of what `o1` reads.
/// Only when the last move *was* confirmed can `o1 == 0 && t > 0` be
/// trusted as a real concurrent reset (the `skipped_reset` rule).
///
/// Called once, after the window loop, on whatever
/// `RoundTripHandle` state exists at that point. The call to
/// this function is unconditional across every early-return path in
/// `run_scrollback_links` (the finally-equivalent guarantee).
///
/// `o0`/`t`/`moved`/`last_move_confirmed` are grouped into `RestorePlan`
/// purely to keep this function's argument count within clippy's limit --
/// see the doc comment above for what each field means.
fn restore_position(
    mut handle: RoundTripHandle,
    api_socket: &str,
    pane: &str,
    plan: RestorePlan,
    deadline: std::time::Instant,
) -> (RoundTripHandle, RestoreOutcome) {
    let RestorePlan {
        o0,
        t,
        moved,
        last_move_confirmed,
    } = plan;
    if !moved {
        // No scroll command was ever dispatched over the wire -- nothing to
        // restore, and no restore command is sent.
        if o0 == 0 {
            return match crate::api_client::pane_get(api_socket, pane, deadline) {
                Ok(info) => match info.scroll {
                    Some(s) if s.offset_from_bottom == 0 => (handle, RestoreOutcome::Exact),
                    _ => (handle, RestoreOutcome::Failed),
                },
                Err(_) => (handle, RestoreOutcome::Failed),
            };
        }
        return (handle, RestoreOutcome::Approximate);
    }

    if last_move_confirmed {
        // The last move's own poll observed a real, current position, so a
        // fresh `pane.get` read here is safe to trust for the
        // `skipped_reset` concurrent-reset check.
        let o1 = match crate::api_client::pane_get(api_socket, pane, deadline) {
            Ok(info) => match info.scroll {
                Some(scroll) => scroll.offset_from_bottom,
                None => return (handle, RestoreOutcome::Failed),
            },
            Err(_) => return (handle, RestoreOutcome::Failed),
        };
        if o1 == 0 && t > 0 {
            // The `skipped_reset` rule, literally: `o1 = 0, t > 0` --
            // concurrent PC-side input already reset the position to the
            // bottom during the round trip, so restore never drags the
            // user's own scrolling back up. Deliberately keyed on `t > 0`
            // (not `o0 > 0`): if the round trip's own last window already
            // confirmed landing at the bottom (`t == 0`), `o1 == 0` simply
            // confirms we're already where we intended to be, not an
            // unrelated concurrent reset.
            return (handle, RestoreOutcome::SkippedReset);
        }
        if o0 == 0 {
            let outcome = attempt_bottom_restore(&mut handle, api_socket, pane, deadline);
            (handle, outcome)
        } else {
            let outcome =
                attempt_approximate_restore(&mut handle, api_socket, pane, o0, t, o1, deadline);
            (handle, outcome)
        }
    } else {
        // The last attempted move's own confirmation never landed (its poll
        // hit the deadline). Since `AttachScroll`/`pane.scroll` and this
        // restore's own `pane.get` travel over different sockets with no
        // ordering guarantee, a stale `o1` here could look identical to a
        // genuine concurrent reset -- so restore is sent unconditionally,
        // never short-circuited by `skipped_reset`.
        if o0 == 0 {
            // Idempotent either way (herdr clamps at the end), so sending
            // it regardless of `o1`'s (possibly stale) value is safe.
            let outcome = attempt_bottom_restore(&mut handle, api_socket, pane, deadline);
            (handle, outcome)
        } else {
            let o1 = match crate::api_client::pane_get(api_socket, pane, deadline) {
                Ok(info) => match info.scroll {
                    Some(scroll) => scroll.offset_from_bottom,
                    None => return (handle, RestoreOutcome::Failed),
                },
                Err(_) => return (handle, RestoreOutcome::Failed),
            };
            let outcome =
                attempt_approximate_restore(&mut handle, api_socket, pane, o0, t, o1, deadline);
            (handle, outcome)
        }
    }
}

/// Exact bottom restore: 22 uses `pane.scroll(0)`; 17/20 send the maximal
/// `AttachScroll{Down, 65535}` rather than a computed relative delta
/// -- deliberately overshooting past the bottom (herdr clamps
/// at the end) is more robust than trusting
/// a possibly-stale `o1` to be exact, and is sent unconditionally by both of
/// `restore_position`'s `o0 == 0` branches (idempotent either way).
fn attempt_bottom_restore(
    handle: &mut RoundTripHandle,
    api_socket: &str,
    pane: &str,
    deadline: std::time::Instant,
) -> RestoreOutcome {
    match handle {
        RoundTripHandle::Api => match crate::api_client::pane_scroll(api_socket, pane, 0, deadline)
        {
            Ok(info) => match info.scroll {
                Some(s) if s.offset_from_bottom == 0 => RestoreOutcome::Exact,
                _ => RestoreOutcome::Failed,
            },
            Err(_) => RestoreOutcome::Failed,
        },
        RoundTripHandle::Attach17(session) => restore_to_bottom_via_attach(
            |dir, lines, dl| session.scroll(dir, lines, dl),
            api_socket,
            pane,
            deadline,
        ),
        RoundTripHandle::Attach20(session) => restore_to_bottom_via_attach(
            |dir, lines, dl| session.scroll(dir, lines, dl),
            api_socket,
            pane,
            deadline,
        ),
    }
}

/// Approximate restore: move by the same delta the round trip's own output
/// pushed in (`o1 - t` extra lines), landing back near the row the user was
/// originally looking at. Reuses `move_to_offset`
/// unchanged -- for protocol 22 this is exactly the table's
/// `pane.scroll(o0 + (o1-t))`; for 17/20 it is the same relative-delta
/// `AttachScroll` `move_to_offset` already sends for any other window move.
fn attempt_approximate_restore(
    handle: &mut RoundTripHandle,
    api_socket: &str,
    pane: &str,
    o0: u64,
    t: u64,
    o1: u64,
    deadline: std::time::Instant,
) -> RestoreOutcome {
    let target = o0.saturating_add(o1.saturating_sub(t));
    let (_, result) = move_to_offset(handle, api_socket, pane, o1, target, deadline);
    match result {
        Ok(_) => RestoreOutcome::Approximate,
        Err(_) => RestoreOutcome::Failed,
    }
}

/// Shared tail of the two `Attach17`/`Attach20` bottom-restore branches:
/// sends the maximal `AttachScroll{Down, 65535}` via `scroll_fn`, then
/// confirms via `pane.get` polling. Generic over the closure instead of
/// `RoundTripHandle` directly so both protocol variants can share this body
/// despite `Attach17`/`Attach20` being distinct, non-trait types.
fn restore_to_bottom_via_attach(
    mut scroll_fn: impl FnMut(
        crate::attach::ScrollDirection,
        u32,
        std::time::Instant,
    ) -> Result<(), RunError>,
    api_socket: &str,
    pane: &str,
    deadline: std::time::Instant,
) -> RestoreOutcome {
    match scroll_fn(
        crate::attach::ScrollDirection::Down,
        u32::from(u16::MAX),
        deadline,
    ) {
        Ok(()) => {
            match poll_scroll_until(api_socket, pane, deadline, |s| s.offset_from_bottom == 0) {
                Ok(s) if s.offset_from_bottom == 0 => RestoreOutcome::Exact,
                _ => RestoreOutcome::Failed,
            }
        }
        Err(_) => RestoreOutcome::Failed,
    }
}

/// `windows[]` element in the JSON contract's exact camelCase shape.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct WindowOutput {
    requested_offset: u64,
    actual_offset: u64,
    frame_width: u16,
    frame_height: u16,
    truncated: bool,
    links: Vec<AggregatedLink>,
    row_hashes: Vec<(u16, String)>,
}

/// `scrollback-links` output contract's top level.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ScrollbackOutput {
    pane_id: String,
    protocol_version: u32,
    restore: String,
    windows: Vec<WindowOutput>,
}

/// A window's row-selection state during output-size truncation: `None` =
/// every observed row, untouched; `Some(rows)` = only these row numbers
/// survive (mirrors `hyperlinks.rs`'s `render_output`/`filtered_output`
/// row-keeping shape, applied per-window here since `--max-output-bytes`
/// bounds the whole `scrollback-links` line rather than each window
/// independently).
type KeptRows = Option<HashSet<u16>>;

fn window_output(fetch: &WindowFetch, kept: &KeptRows) -> WindowOutput {
    let (links, row_hashes, truncated) = match kept {
        None => (fetch.links.clone(), fetch.row_hashes.clone(), false),
        Some(rows) => {
            let row_hashes: Vec<(u16, String)> = fetch
                .row_hashes
                .iter()
                .filter(|(r, _)| rows.contains(r))
                .cloned()
                .collect();
            let links: Vec<AggregatedLink> = fetch
                .links
                .iter()
                .filter_map(|link| {
                    let ranges: Vec<(u16, u16, u16)> = link
                        .ranges
                        .iter()
                        .filter(|(r, _, _)| rows.contains(r))
                        .cloned()
                        .collect();
                    if ranges.is_empty() {
                        None
                    } else {
                        Some(AggregatedLink {
                            url: link.url.clone(),
                            ranges,
                        })
                    }
                })
                .collect();
            let ranges_kept: usize = links.iter().map(|l| l.ranges.len()).sum();
            let ranges_total: usize = fetch.links.iter().map(|l| l.ranges.len()).sum();
            let truncated = row_hashes.len() < fetch.row_hashes.len() || ranges_kept < ranges_total;
            (links, row_hashes, truncated)
        }
    };
    WindowOutput {
        requested_offset: fetch.requested_offset,
        actual_offset: fetch.actual_offset,
        frame_width: fetch.frame_width,
        frame_height: fetch.frame_height,
        truncated: truncated || fetch.rejected,
        links,
        row_hashes,
    }
}

fn build_scrollback_json(
    pane_id: &str,
    protocol: u8,
    fetches: &[WindowFetch],
    restore: RestoreOutcome,
    kept: &[KeptRows],
) -> String {
    let out = ScrollbackOutput {
        pane_id: pane_id.to_owned(),
        protocol_version: protocol as u32,
        restore: restore.as_json_str().to_owned(),
        windows: fetches
            .iter()
            .zip(kept.iter())
            .map(|(f, k)| window_output(f, k))
            .collect(),
    };
    serde_json::to_string(&out).unwrap_or_else(|_| r#"{"error":"internal"}"#.to_owned())
}

/// Renders the final `scrollback-links` JSON line, applying
/// `--max-output-bytes` truncation across *all* windows combined when
/// needed (the budget is for the whole stdout line,
/// matching the 60000-byte stdout limit and the executor's 64KB
/// cap, not a separate budget per window). Never panics, never returns
/// invalid/partial JSON.
fn render_scrollback_output(
    pane_id: &str,
    protocol: u8,
    fetches: &[WindowFetch],
    restore: RestoreOutcome,
    max_output_bytes: usize,
) -> String {
    let full_kept: Vec<KeptRows> = vec![None; fetches.len()];
    let full = build_scrollback_json(pane_id, protocol, fetches, restore, &full_kept);
    if full.len() <= max_output_bytes {
        return full;
    }

    // Truncate windows in requested order (bottom-first
    // packing, applied window by window): window 0 gets first claim on the
    // budget, then window 1 gets whatever is left, and so on -- windows not
    // yet reached stay at `Some(empty set)` (rendered as `links: []`, empty
    // `rowHashes`, `truncated: true`) rather than being dropped from the
    // array (callers verify that the returned window count/order matches
    // the request).
    let mut kept: Vec<KeptRows> = vec![Some(HashSet::new()); fetches.len()];
    for i in 0..fetches.len() {
        let mut rows: Vec<u16> = fetches[i]
            .row_hashes
            .iter()
            .map(|(r, _)| *r)
            .chain(
                fetches[i]
                    .links
                    .iter()
                    .flat_map(|l| l.ranges.iter().map(|(r, _, _)| *r)),
            )
            .collect();
        rows.sort_unstable();
        rows.dedup();
        rows.reverse(); // bottom of the viewport (highest row number) first

        let mut accepted: HashSet<u16> = HashSet::new();
        for row in rows {
            let mut candidate = accepted.clone();
            candidate.insert(row);
            kept[i] = Some(candidate.clone());
            let json = build_scrollback_json(pane_id, protocol, fetches, restore, &kept);
            if json.len() <= max_output_bytes {
                accepted = candidate;
            } else {
                break;
            }
        }
        kept[i] = Some(accepted);
    }
    build_scrollback_json(pane_id, protocol, fetches, restore, &kept)
}

/// The `scrollback-links` subcommand's end-to-end pipeline:
/// lock -> record the original position -> open the movement connection ->
/// move to and observe each requested window in order -> restore -> render.
///
/// Finally-equivalent restore: if a window's move or observe
/// fails partway through, the loop stops and restore is still attempted
/// using whatever position was last confirmed. Whether the pane needs
/// restoring at all is judged by `move_attempted` -- whether a scroll
/// command was ever dispatched over the wire, per `move_to_offset`'s
/// return -- not by comparing tracked/observed offsets (a send whose
/// *confirmation* poll then failed must still be
/// treated as "moved").
pub fn run_scrollback_links(params: &ScrollbackParams) -> Result<String, RunError> {
    let _lock = acquire_lock(&params.lock_dir, &params.api_socket, &params.pane)?;

    let fetch_deadline =
        std::time::Instant::now() + std::time::Duration::from_millis(params.timeout_ms);
    let original = record_original_position(&params.api_socket, &params.pane, fetch_deadline)?;
    let fallback_rows: u16 = original
        .viewport_rows
        .try_into()
        .map_err(|_| RunError::Protocol("viewport_rows out of range".to_owned()))?;

    // 17/20-only guard: PageKey scrolling
    // is only ever attempted when the pane is already at the bottom *and*
    // there is scrollback to move into. When this does not hold, skip the
    // whole round trip -- no `pane.process_info`/`winsize::real_size`
    // call, no attach, no `AttachScroll` -- and return with `windows: []`.
    // Protocol 22 (`pane.scroll`) is unaffected: it never held this guard.
    //
    // KNOWN LIMITATION:
    // no new `RestoreOutcome`/`fetchKind` variant was added to distinguish
    // "skipped by this guard, no round trip was ever opened" from the
    // ordinary post-move restore outcomes. `moved: false` is passed
    // unconditionally below, so `restore_position`'s existing `!moved`
    // branch already classifies both guard-skip cases without any new
    // variant: `o0 == 0` (guard failed only because there was no
    // scrollback to move into) re-reads via `pane.get` and reports
    // `Exact`/`Failed`; `o0 != 0` (guard failed because the pane was not
    // already at the bottom) reports `Approximate` with no extra call.
    // Either way, the caller must infer "no links were fetched" from
    // `windows` being empty rather than from a dedicated field. Rejected:
    // adding a `fetchKind` field would change the output contract and
    // is unnecessary (Dart can already tell from an empty
    // `windows` array).
    if params.protocol == 17 || params.protocol == 20 {
        let guard_ok = original.offset_from_bottom == 0 && original.max_offset_from_bottom > 0;
        if !guard_ok {
            let restore_deadline = std::time::Instant::now()
                + std::time::Duration::from_millis(params.restore_budget_ms);
            // `RoundTripHandle::Api` is a placeholder here, not a real API
            // round trip -- `restore_position`'s `moved == false` branch
            // (the only branch reachable with `moved: false` below) never
            // dereferences `handle`, so this is safe; `close_round_trip`
            // on `Api` is a no-op either way.
            let (handle, restore) = restore_position(
                RoundTripHandle::Api,
                &params.api_socket,
                &params.pane,
                RestorePlan {
                    o0: original.offset_from_bottom,
                    t: original.offset_from_bottom,
                    moved: false,
                    last_move_confirmed: true,
                },
                restore_deadline,
            );
            close_round_trip(handle);
            return Ok(render_scrollback_output(
                &params.pane,
                params.protocol,
                &[],
                restore,
                params.max_output_bytes,
            ));
        }
    }

    let size = match params.protocol {
        17 | 20 => resolve_size_fail_closed(&params.api_socket, &params.pane, fetch_deadline)?,
        _ => resolve_size_fail_open(
            &params.api_socket,
            &params.pane,
            params.cols,
            fallback_rows,
            fetch_deadline,
        ),
    };
    let mut handle = open_round_trip(params, &original, size, fetch_deadline)?;

    let mut current_offset = original.offset_from_bottom;
    let mut move_attempted = false;
    // Whether *any* window in this run genuinely changed the pane's
    // position (as opposed to `move_attempted`, which is true the moment a
    // move is merely *dispatched* over the wire, success or not). The
    // discard rule below needs this distinction: a window
    // whose dispatched move had no effect must not, by itself, make
    // `restore_position` think a real restore is owed.
    let mut any_window_moved = false;
    // Whether the *last attempted* move's own poll actually confirmed a
    // resulting position -- starts
    // `true` vacuously (unused unless `move_attempted` ends up `true`).
    let mut last_move_confirmed = true;
    let mut fetches: Vec<WindowFetch> = Vec::new();
    let mut loop_err: Option<RunError> = None;

    for &target in &params.windows {
        let pre_move_offset = current_offset;
        let (attempted, moved) = move_to_offset(
            &mut handle,
            &params.api_socket,
            &params.pane,
            current_offset,
            target,
            fetch_deadline,
        );
        move_attempted = move_attempted || attempted;
        let scroll = match moved {
            Ok(scroll) => {
                last_move_confirmed = true;
                scroll
            }
            Err(e) => {
                last_move_confirmed = false;
                if attempted {
                    // A send that was
                    // attempted but never confirmed (e.g. the wire-level
                    // `AttachScroll`/`pane.scroll` went out, but the
                    // subsequent `pane.get` poll then timed out) must not
                    // leave `current_offset` (this loop's `t`) stale at the
                    // pre-move value -- `restore_position`'s approximate
                    // delta math (`o0 + (o1 - t)`) needs its best estimate
                    // of where the move was headed, or it silently computes
                    // a no-op target. `relative_scroll_of`'s delta is
                    // defined to close exactly the gap to `target`, for
                    // both protocol 22 (`target_offset_from_bottom` is what
                    // was requested outright) and 17/20 (the attempted
                    // direction+lines close exactly that gap) -- so `target`
                    // itself is that best estimate in every case.
                    current_offset = target;
                }
                loop_err = Some(e);
                break;
            }
        };
        current_offset = scroll.offset_from_bottom;

        // Discard rule (17/20 only -- protocol 22's
        // `pane.scroll` path is unaffected): a move was dispatched
        // (`attempted`) for this window, but the position
        // `poll_scroll_until` ultimately confirmed -- including the
        // "gave up and returned the last observed value" case after a
        // timeout, which is `Ok`, not `Err` -- is unchanged from this
        // window's own pre-move position. The pane is stuck (e.g. an
        // alt-screen/mouse-tracking/DECCKM mode absorbing the scroll
        // input) rather than genuinely having "already been there": do
        // not observe this window, do not add it to `fetches`, and stop
        // processing any further windows entirely (continuing would only
        // dispatch more moves against a pane that is not responding to
        // them). This is not a failure of the run: `loop_err` stays
        // `None` and whatever fetches were already collected are still
        // returned.
        if params.protocol != 22 && attempted && current_offset == pre_move_offset {
            break;
        }
        any_window_moved = any_window_moved || (attempted && current_offset != pre_move_offset);

        match observe_window(params, size, fetch_deadline) {
            Ok(WindowObservation::Observed {
                links: frame_links,
                width,
                height,
            }) => {
                fetches.push(WindowFetch {
                    requested_offset: target,
                    actual_offset: current_offset,
                    frame_width: width,
                    frame_height: height,
                    links: sanitize_links(frame_links.links),
                    row_hashes: frame_links.row_hashes,
                    rejected: false,
                });
            }
            Ok(WindowObservation::Rejected { width, height }) => {
                fetches.push(WindowFetch {
                    requested_offset: target,
                    actual_offset: current_offset,
                    frame_width: width,
                    frame_height: height,
                    links: Vec::new(),
                    row_hashes: Vec::new(),
                    rejected: true,
                });
            }
            Err(e) => {
                loop_err = Some(e);
                break;
            }
        }
    }

    // Restore's `moved` input: for an error path or protocol 22, keep the
    // existing `move_attempted` ("a move was dispatched") semantics
    // (22 is unaffected by the discard rule, and no
    // existing error-path behavior should change). For a 17/20 success
    // path, use `any_window_moved` instead, so a run where every
    // dispatched move turned out to be a no-op is treated by
    // `restore_position` exactly like "no scroll command was ever
    // dispatched" (nothing moved -> do nothing).
    let moved_for_restore = if loop_err.is_some() || params.protocol == 22 {
        move_attempted
    } else {
        any_window_moved
    };

    let restore_deadline =
        std::time::Instant::now() + std::time::Duration::from_millis(params.restore_budget_ms);
    let (handle, restore) = restore_position(
        handle,
        &params.api_socket,
        &params.pane,
        RestorePlan {
            o0: original.offset_from_bottom,
            t: current_offset,
            moved: moved_for_restore,
            last_move_confirmed,
        },
        restore_deadline,
    );
    close_round_trip(handle);

    if let Some(e) = loop_err {
        return Err(e);
    }

    // Every observed window was rejected: nothing usable to return.
    if !fetches.is_empty() && fetches.iter().all(|f| f.rejected) {
        return Err(RunError::RenderRejected(
            "every observed window was rejected".to_owned(),
        ));
    }

    Ok(render_scrollback_output(
        &params.pane,
        params.protocol,
        &fetches,
        restore,
        params.max_output_bytes,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn acquire_lock_creates_missing_lock_dir_as_0700() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = std::env::temp_dir().join(format!(
            "scrollback-lock-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let lock_dir = tmp.join("locks");
        let _lock = acquire_lock(lock_dir.to_str().unwrap(), "api.sock", "w1:p1").expect("lock");
        let mode = std::fs::metadata(&lock_dir).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o700);
        drop(_lock);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn acquire_lock_does_not_change_permissions_of_an_existing_lock_dir() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = std::env::temp_dir().join(format!(
            "scrollback-lock-test-existing-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&tmp).unwrap();
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o755)).unwrap();
        let _lock = acquire_lock(tmp.to_str().unwrap(), "api.sock", "w1:p1").expect("lock");
        let mode = std::fs::metadata(&tmp).unwrap().permissions().mode() & 0o777;
        assert_eq!(
            mode, 0o755,
            "pre-existing directory permissions must be left untouched"
        );
        drop(_lock);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn acquire_lock_second_holder_for_the_same_pane_is_busy() {
        let tmp = std::env::temp_dir().join(format!(
            "scrollback-lock-test-busy-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let lock_dir = tmp.to_str().unwrap();
        let first = acquire_lock(lock_dir, "api.sock", "w1:p1").expect("first lock");
        let second = acquire_lock(lock_dir, "api.sock", "w1:p1");
        assert!(matches!(second, Err(RunError::Busy)));
        drop(first);
        // Once released, a fresh acquire succeeds again.
        let third = acquire_lock(lock_dir, "api.sock", "w1:p1");
        assert!(third.is_ok());
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn acquire_lock_different_panes_do_not_contend() {
        let tmp = std::env::temp_dir().join(format!(
            "scrollback-lock-test-multi-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let lock_dir = tmp.to_str().unwrap();
        let a = acquire_lock(lock_dir, "api.sock", "w1:p1").expect("lock pane 1");
        let b = acquire_lock(lock_dir, "api.sock", "w1:p2").expect("lock pane 2 (different pane)");
        drop(a);
        drop(b);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn acquire_lock_preserves_existing_lock_file_contents() {
        // The lock file must be `create`d, not
        // truncated — a re-run must not wipe any content that might
        // already be there (even though this module never writes to it
        // today, the open mode itself must not truncate).
        let tmp = std::env::temp_dir().join(format!(
            "scrollback-lock-test-notrunc-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&tmp).unwrap();
        let path = lock_file_path(tmp.to_str().unwrap(), "api.sock", "w1:p1");
        std::fs::write(&path, b"marker").unwrap();
        let _lock = acquire_lock(tmp.to_str().unwrap(), "api.sock", "w1:p1").expect("lock");
        let contents = std::fs::read(&path).unwrap();
        assert_eq!(contents, b"marker");
        drop(_lock);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn try_lock_would_block_classifies_as_busy() {
        // Only WouldBlock (genuine contention) is Busy.
        let r = classify_try_lock_result(Err(std::fs::TryLockError::WouldBlock));
        assert!(matches!(r, Err(RunError::Busy)));
    }

    #[test]
    fn try_lock_other_error_classifies_as_io_not_busy() {
        // A non-contention try_lock failure (e.g. ENOLCK, a filesystem
        // without lock support) must not be reported as `busy` — the
        // caller would otherwise retry it as if another invocation held
        // the lock, which is not what happened.
        let io_err = std::io::Error::other("simulated");
        let r = classify_try_lock_result(Err(std::fs::TryLockError::Error(io_err)));
        assert!(matches!(r, Err(RunError::Io)));
    }

    #[test]
    fn try_lock_ok_classifies_as_ok() {
        let r = classify_try_lock_result(Ok(()));
        assert!(r.is_ok());
    }

    // -----------------------------------------------------------------
    // Tests for the move/position logic. A local fake JSON-line server for `pane.get`/
    // `pane.scroll` (mirrors tests/api_client.rs's `serve_one`),
    // plus reuse of `attach::Attach17`/`Attach20`'s own
    // `from_stream` (over `UnixStream::pair()`, no filesystem socket
    // needed) for the 17/20 cases.
    // -----------------------------------------------------------------

    use crate::attach::{Attach17, Attach20, ScrollDirection};
    use crate::frame_io::read_frame_deadline;
    use crate::wire::*;
    use std::io::{BufRead, BufReader, Write};
    use std::os::unix::net::{UnixListener, UnixStream};

    /// RAII guard for a test's unique Unix-socket bind path (see
    /// `json_socket_path`): removes the socket file on drop, including
    /// when a test panics partway through -- the same cleanup `LockDirGuard`
    /// does for `--lock-dir` paths. A plain-`PathBuf` version would only be
    /// cleaned up by each test's own end-of-function
    /// `std::fs::remove_file(&path)`, which a panic skips, leaving
    /// `/tmp/herdr-caret-helper-scrollback-test-*.sock` files behind.
    ///
    /// Implements `Deref<Target = Path>` and `AsRef<Path>` so every
    /// existing call site (`UnixListener::bind(&path)`, `path.to_str()`,
    /// the now-redundant-but-harmless end-of-test
    /// `std::fs::remove_file(&path)`) keeps compiling completely
    /// unchanged -- only `json_socket_path` itself changes.
    struct SocketPathGuard(PathBuf);

    impl std::ops::Deref for SocketPathGuard {
        type Target = Path;
        fn deref(&self) -> &Path {
            &self.0
        }
    }

    impl AsRef<Path> for SocketPathGuard {
        fn as_ref(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for SocketPathGuard {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.0);
        }
    }

    fn json_socket_path(name: &str) -> SocketPathGuard {
        let mut path = std::env::temp_dir();
        path.push(format!(
            "herdr-caret-helper-scrollback-test-{}-{}-{}.sock",
            name,
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = std::fs::remove_file(&path);
        SocketPathGuard(path)
    }

    /// Bound for `accept_with_deadline`: generous relative to every
    /// `timeout_ms`/`restore_budget_ms` used by these tests (at most
    /// 5000ms), so it never fires under normal timing, but still finite.
    const STUB_ACCEPT_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);

    /// Accepts one connection within `STUB_ACCEPT_TIMEOUT`, instead of
    /// blocking forever. Under
    /// some regressions (e.g. calling `pane.process_info`
    /// before the 17/20 attach guard and so starves `resolve_size_fail_
    /// closed`'s own call of its queued response) the code under test can
    /// fail and return *before ever reaching this connection*. A plain
    /// `listener.accept().unwrap()` then blocks forever, and the test's
    /// own unconditional `client_thread.join().unwrap()` hangs with it --
    /// a regression then shows up as the whole test process timing out
    /// (rc=124), not as a named FAILED test, and is much harder to
    /// attribute. This turns that into an ordinary, named test failure: a
    /// stub whose connection never arrives now panics with a clear
    /// message instead of hanging, and `client_thread.join().unwrap()`
    /// then also fails (propagating the panic), without hanging the test
    /// process at all.
    fn accept_with_deadline(listener: &UnixListener) -> UnixStream {
        let deadline = std::time::Instant::now() + STUB_ACCEPT_TIMEOUT;
        listener.set_nonblocking(true).expect("set_nonblocking");
        loop {
            match listener.accept() {
                Ok((stream, _addr)) => {
                    stream
                        .set_nonblocking(false)
                        .expect("set_nonblocking(stream)");
                    return stream;
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    assert!(
                        std::time::Instant::now() < deadline,
                        "accept_with_deadline: no connection within {STUB_ACCEPT_TIMEOUT:?} -- \
                         the code under test likely failed/returned before ever reaching \
                         this connection"
                    );
                    std::thread::sleep(std::time::Duration::from_millis(20));
                }
                Err(e) => panic!("accept_with_deadline: {e}"),
            }
        }
    }

    /// Accepts `responses.len()` connections in sequence, one request line
    /// each, replying with the matching response. Returns every request
    /// line received, in order.
    fn serve_sequence(listener: UnixListener, responses: &[&str]) -> Vec<String> {
        let mut received = Vec::new();
        for response in responses {
            let stream = accept_with_deadline(&listener);
            let mut reader = BufReader::new(&stream);
            let mut line = String::new();
            reader.read_line(&mut line).expect("read request line");
            received.push(line);
            let mut writer = &stream;
            writer.write_all(response.as_bytes()).unwrap();
            writer.write_all(b"\n").unwrap();
            writer.flush().unwrap();
        }
        received
    }

    /// Like `serve_sequence`, but each entry is `Some(response)` (answer
    /// normally) or `None` (read the request, then deliberately never
    /// respond -- the caller's own `set_read_timeout`/deadline must fire
    /// first). Used for the "send succeeded, confirmation wait timed
    /// out" regression tests, mirroring `tests/api_client.rs`'s
    /// `no_response_before_deadline_is_timeout`.
    fn serve_sequence_with_stall(listener: UnixListener, entries: &[Option<&str>]) -> Vec<String> {
        let mut received = Vec::new();
        for entry in entries {
            let stream = accept_with_deadline(&listener);
            let mut reader = BufReader::new(&stream);
            let mut line = String::new();
            reader.read_line(&mut line).expect("read request line");
            received.push(line);
            match entry {
                Some(response) => {
                    let mut writer = &stream;
                    writer.write_all(response.as_bytes()).unwrap();
                    writer.write_all(b"\n").unwrap();
                    writer.flush().unwrap();
                }
                None => {
                    // Never respond -- hold the connection until the
                    // caller's read side times out and moves on. Sleeping
                    // here just keeps this thread (and the connection)
                    // alive long enough for that to happen deterministically.
                    std::thread::sleep(std::time::Duration::from_millis(500));
                }
            }
        }
        received
    }

    fn pane_info_response(offset_from_bottom: u64) -> String {
        pane_info_response_with_max(offset_from_bottom, 9999)
    }

    fn pane_info_response_with_max(offset_from_bottom: u64, max_offset_from_bottom: u64) -> String {
        format!(
            r#"{{"id":"1","result":{{"type":"pane_info","pane":{{"pane_id":"w1:p2","terminal_id":"term-abc","workspace_id":"w1","tab_id":"t1","focused":true,"agent_status":"idle","revision":1,"scroll":{{"offset_from_bottom":{offset_from_bottom},"max_offset_from_bottom":{max_offset_from_bottom},"viewport_rows":24}}}}}}}}"#
        )
    }

    fn pane_info_response_without_scroll() -> String {
        r#"{"id":"1","result":{"type":"pane_info","pane":{"pane_id":"w1:p2","terminal_id":"term-abc","workspace_id":"w1","tab_id":"t1","focused":true,"agent_status":"idle","revision":1}}}"#.to_owned()
    }

    /// A genuine `pane.process_info` success response (`shell_pid` set).
    /// Used by the 17/20 fail-closed `resolve_size_fail_closed` tests,
    /// paired with `spawn_real_pty_process` below so the follow-up
    /// `winsize::real_size(shell_pid)` call succeeds for real.
    fn pane_process_info_response(shell_pid: u32) -> String {
        format!(
            r#"{{"id":"1","result":{{"type":"pane_process_info","process_info":{{"pane_id":"w1:p2","shell_pid":{shell_pid}}}}}}}"#
        )
    }

    // -- Real-pty test helper for `winsize::real_size` (17/20 fail-closed
    // real-size resolution) --------------------------------------------
    //
    // `resolve_size_fail_closed` genuinely calls `winsize::real_size`, which
    // needs a *real* process with a *real* controlling pty -- there is no
    // way to satisfy it with a JSON-level fake alone. This duplicates the
    // minimal FFI `winsize.rs`'s own `#[cfg(test)]` helpers already use
    // (`open`/`ioctl`/`TIOCSPTLCK`/`TIOCGPTN`/`TIOCSWINSZ`), since that
    // module's helpers are private to its own test block, plus `setsid`+a
    // fresh `open()` of the slave in the child's `pre_exec` (the standard
    // way a process acquires a real controlling terminal) so
    // `/proc/<pid>/stat`'s `tty_nr` resolves to this pty, exactly as a real
    // shell would. Verified empirically that this
    // combination makes `winsize::real_size(child.id())` succeed end-to-end.
    #[repr(C)]
    #[derive(Default)]
    struct TestRawWinsize {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    }

    // `ioctl`/`open`'s real C prototypes are variadic (`int ioctl(int,
    // unsigned long, ...)` / `int open(const char *, int, ...)`); declaring
    // them with a fixed trailing argument is unsound per the Rustonomicon's
    // FFI chapter and clashes (`clashing_extern_declarations`) with
    // `winsize.rs`'s own correctly-variadic test-only declarations of the
    // same two symbols once both modules are linked into the same test
    // binary -- see that file's matching doc comment for the full
    // rationale. Declared variadic here too, always passing exactly one
    // trailing argument at every call site below, matching the real
    // prototype exactly.
    extern "C" {
        fn ioctl(fd: i32, request: u64, ...) -> i32;
        fn open(path: *const i8, flags: i32, ...) -> i32;
        fn setsid() -> i32;
        fn dup2(oldfd: i32, newfd: i32) -> i32;
        fn close(fd: i32) -> i32;
    }

    const TEST_O_RDWR: i32 = 0o2;
    const TEST_O_NOCTTY: i32 = 0o400;
    const TEST_TIOCSPTLCK: u64 = 0x4004_5431;
    const TEST_TIOCGPTN: u64 = 0x8004_5430;
    const TEST_TIOCSWINSZ: u64 = 0x5414;

    /// Spawns a real `sleep` child with a real pty as its controlling
    /// terminal, sized `rows`x`cols` (`xpixel`/`ypixel` in pixels, `0` for
    /// "none", same meaning as `winsize::Winsize`'s own fields), so
    /// `winsize::real_size(child.id())` succeeds for real. Returns the
    /// `Child` (caller must `.kill()` + `.wait()` it) and the pty master
    /// `File` (must be kept alive for the pty pair to stay valid -- dropping
    /// it closes the pair).
    fn spawn_real_pty_process(
        rows: u16,
        cols: u16,
        xpixel: u16,
        ypixel: u16,
    ) -> (std::process::Child, std::fs::File) {
        use std::os::unix::io::FromRawFd;
        use std::os::unix::process::CommandExt;

        let ptmx = std::ffi::CString::new("/dev/ptmx").unwrap();
        let master_fd = unsafe { open(ptmx.as_ptr(), TEST_O_RDWR | TEST_O_NOCTTY) };
        assert!(master_fd >= 0, "open /dev/ptmx failed");
        let mut unlock: i32 = 0;
        assert_eq!(
            unsafe {
                ioctl(
                    master_fd,
                    TEST_TIOCSPTLCK,
                    &mut unlock as *mut i32 as *mut std::ffi::c_void,
                )
            },
            0,
            "TIOCSPTLCK failed"
        );
        let mut n: i32 = 0;
        assert_eq!(
            unsafe {
                ioctl(
                    master_fd,
                    TEST_TIOCGPTN,
                    &mut n as *mut i32 as *mut std::ffi::c_void,
                )
            },
            0,
            "TIOCGPTN failed"
        );
        let mut ws = TestRawWinsize {
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: xpixel,
            ws_ypixel: ypixel,
        };
        assert_eq!(
            unsafe {
                ioctl(
                    master_fd,
                    TEST_TIOCSWINSZ,
                    &mut ws as *mut TestRawWinsize as *mut std::ffi::c_void,
                )
            },
            0,
            "TIOCSWINSZ on the master side failed"
        );
        // SAFETY: `master_fd` is a freshly opened, valid, uniquely-owned fd
        // from the successful `open()` above.
        let master = unsafe { std::fs::File::from_raw_fd(master_fd) };

        let slave_path = std::ffi::CString::new(format!("/dev/pts/{n}")).unwrap();
        let mut cmd = std::process::Command::new("sleep");
        cmd.arg("30");
        cmd.stdin(std::process::Stdio::null());
        cmd.stdout(std::process::Stdio::null());
        cmd.stderr(std::process::Stdio::null());
        // SAFETY: the closure only calls `setsid`/`open`/`dup2`/`close`
        // (all async-signal-safe) between fork and exec, as `pre_exec`
        // requires; `slave_path` is a valid, null-terminated `CString`
        // moved into the closure.
        unsafe {
            cmd.pre_exec(move || {
                if setsid() == -1 {
                    return Err(std::io::Error::last_os_error());
                }
                // A fresh `open()` of the pty slave, by a session leader
                // with no controlling terminal (just established above),
                // is what makes the kernel assign it as this process's
                // controlling terminal -- an inherited, already-open fd
                // would not trigger that assignment.
                let fd = open(slave_path.as_ptr(), TEST_O_RDWR);
                if fd < 0 {
                    return Err(std::io::Error::last_os_error());
                }
                dup2(fd, 0);
                dup2(fd, 1);
                dup2(fd, 2);
                if fd > 2 {
                    close(fd);
                }
                Ok(())
            });
        }
        let child = cmd.spawn().expect("spawn sleep for a real controlling pty");
        // Give the child a brief moment to run its `pre_exec` (setsid+open)
        // before any caller reads `/proc/<pid>/stat`.
        std::thread::sleep(std::time::Duration::from_millis(50));
        (child, master)
    }

    #[test]
    fn relative_scroll_of_moves_up_when_target_is_further_from_bottom() {
        let (dir, lines) = relative_scroll_of(5, 20).expect("should move");
        assert_eq!(dir, ScrollDirection::Up);
        assert_eq!(lines, 15);
    }

    #[test]
    fn relative_scroll_of_moves_down_when_target_is_closer_to_bottom() {
        let (dir, lines) = relative_scroll_of(20, 5).expect("should move");
        assert_eq!(dir, ScrollDirection::Down);
        assert_eq!(lines, 15);
    }

    #[test]
    fn relative_scroll_of_is_none_when_already_at_target() {
        assert!(relative_scroll_of(7, 7).is_none());
    }

    #[test]
    fn record_original_position_reads_offset_and_viewport_rows() {
        let path = json_socket_path("record-original");
        let listener = UnixListener::bind(&path).unwrap();
        let response = pane_info_response(31);
        let t = std::thread::spawn(move || serve_sequence(listener, &[&response]));
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let original = record_original_position(path.to_str().unwrap(), "w1:p2", deadline)
            .expect("record_original_position");
        assert_eq!(original.offset_from_bottom, 31);
        assert_eq!(original.viewport_rows, 24);
        assert_eq!(
            original.terminal_id, "term-abc",
            "must carry pane_info's terminal_id"
        );
        let sent = t.join().unwrap();
        assert!(sent[0].contains("\"method\":\"pane.get\""));
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn move_to_offset_protocol22_sends_absolute_pane_scroll_then_confirms() {
        let path = json_socket_path("move22");
        let listener = UnixListener::bind(&path).unwrap();
        // First response: `pane.scroll`'s own result. Second: the
        // defensive `pane.get` re-check poll (settled on the first try).
        let scroll_resp = pane_info_response(12);
        let poll_resp = pane_info_response(12);
        let t = std::thread::spawn(move || serve_sequence(listener, &[&scroll_resp, &poll_resp]));
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let mut handle = RoundTripHandle::Api;
        let (attempted, result) = move_to_offset(
            &mut handle,
            path.to_str().unwrap(),
            "w1:p2",
            0,
            12,
            deadline,
        );
        let confirmed = result.expect("move_to_offset");
        assert!(attempted, "protocol 22 always dispatches pane.scroll");
        assert_eq!(confirmed.offset_from_bottom, 12);
        let sent = t.join().unwrap();
        assert!(sent[0].contains("\"method\":\"pane.scroll\""));
        assert!(sent[0].contains("\"offset_from_bottom\":12"));
        assert!(sent[1].contains("\"method\":\"pane.get\""));
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn move_to_offset_protocol17_sends_attach_scroll_up_and_confirms_via_poll() {
        // Fake attach server (like tests/attach.rs's accept_and_confirm17)
        // over UnixStream::pair(), plus a separate fake JSON listener for
        // the confirmation poll (move_to_offset's poll connects by path,
        // independent of the attach session's own stream).
        let (client, mut server) = UnixStream::pair().unwrap();
        let attach_thread = std::thread::spawn(move || {
            let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let _attach: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            let _resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();
            // Now expect the AttachScroll this test's move_to_offset call
            // should send (current=5, target=20 -> Up, 15 lines).
            let scroll_msg: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            scroll_msg
        });
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let session = Attach17::from_stream(
            client,
            "w1:p2",
            crate::winsize::Winsize {
                cols: 80,
                rows: 24,
                cell_width_px: 0,
                cell_height_px: 0,
            },
            deadline,
        )
        .expect("attach17");
        let mut handle = RoundTripHandle::Attach17(session);

        let path = json_socket_path("move17");
        let listener = UnixListener::bind(&path).unwrap();
        let poll_resp = pane_info_response(20);
        let poll_thread = std::thread::spawn(move || serve_sequence(listener, &[&poll_resp]));

        let (attempted, result) = move_to_offset(
            &mut handle,
            path.to_str().unwrap(),
            "w1:p2",
            5,
            20,
            deadline,
        );
        let confirmed = result.expect("move_to_offset");
        assert!(attempted, "a nonzero relative delta must be dispatched");
        assert_eq!(confirmed.offset_from_bottom, 20);

        let scroll_msg = attach_thread.join().unwrap();
        match scroll_msg {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 0, "0 = Up into scrollback");
                assert_eq!(lines, 15);
            }
            other => panic!("expected AttachScroll, got {:?}", other),
        }
        let sent = poll_thread.join().unwrap();
        assert!(sent[0].contains("\"method\":\"pane.get\""));
        let _ = std::fs::remove_file(&path);
        close_round_trip(handle);
    }

    #[test]
    fn move_to_offset_protocol20_sends_attach_scroll_down_and_confirms_via_poll() {
        let (client, mut server) = UnixStream::pair().unwrap();
        let attach_thread = std::thread::spawn(move || {
            let _hello: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage20::Welcome {
                    version: 20,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let _attach: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            let _resize: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage20::Terminal(TerminalFrame {
                    seq: 1,
                    width: 100,
                    height: 30,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();
            let scroll_msg: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            scroll_msg
        });
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let session = Attach20::from_stream(
            client,
            "w1:p3",
            crate::winsize::Winsize {
                cols: 100,
                rows: 30,
                cell_width_px: 0,
                cell_height_px: 0,
            },
            deadline,
        )
        .expect("attach20");
        let mut handle = RoundTripHandle::Attach20(session);

        let path = json_socket_path("move20");
        let listener = UnixListener::bind(&path).unwrap();
        let poll_resp = pane_info_response(5);
        let poll_thread = std::thread::spawn(move || serve_sequence(listener, &[&poll_resp]));

        // current=20 (further from bottom), target=5 (closer) -> Down.
        let (attempted, result) = move_to_offset(
            &mut handle,
            path.to_str().unwrap(),
            "w1:p3",
            20,
            5,
            deadline,
        );
        let confirmed = result.expect("move_to_offset");
        assert!(attempted);
        assert_eq!(confirmed.offset_from_bottom, 5);

        let scroll_msg = attach_thread.join().unwrap();
        match scroll_msg {
            ClientMessage20::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 1, "1 = Down towards the bottom");
                assert_eq!(lines, 15);
            }
            other => panic!("expected AttachScroll, got {:?}", other),
        }
        let _ = poll_thread.join().unwrap();
        let _ = std::fs::remove_file(&path);
        close_round_trip(handle);
    }

    #[test]
    fn move_to_offset_protocol17_skips_attach_scroll_when_already_at_target() {
        // relative_scroll_of returns None when current == target: no
        // AttachScroll should be sent at all, just the confirmation poll.
        let (client, mut server) = UnixStream::pair().unwrap();
        let attach_thread = std::thread::spawn(move || {
            let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let _attach: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            let _resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();
            // No AttachScroll should arrive; confirm the connection stays
            // idle (best-effort — reading with a short deadline should
            // time out rather than yield a frame).
            let short_deadline = std::time::Instant::now() + std::time::Duration::from_millis(150);
            let result = read_frame_deadline::<ClientMessage17>(&server, short_deadline);
            assert!(
                result.is_err(),
                "no AttachScroll expected, got {:?}",
                result
            );
        });
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let session = Attach17::from_stream(
            client,
            "w1:p2",
            crate::winsize::Winsize {
                cols: 80,
                rows: 24,
                cell_width_px: 0,
                cell_height_px: 0,
            },
            deadline,
        )
        .expect("attach17");
        let mut handle = RoundTripHandle::Attach17(session);

        let path = json_socket_path("move17-noop");
        let listener = UnixListener::bind(&path).unwrap();
        let poll_resp = pane_info_response(10);
        let poll_thread = std::thread::spawn(move || serve_sequence(listener, &[&poll_resp]));

        let (attempted, result) = move_to_offset(
            &mut handle,
            path.to_str().unwrap(),
            "w1:p2",
            10,
            10,
            deadline,
        );
        let confirmed = result.expect("move_to_offset");
        assert!(
            !attempted,
            "already at target -- relative_scroll_of is None, nothing should be dispatched"
        );
        assert_eq!(confirmed.offset_from_bottom, 10);

        attach_thread.join().unwrap();
        let _ = poll_thread.join().unwrap();
        let _ = std::fs::remove_file(&path);
        close_round_trip(handle);
    }

    // -----------------------------------------------------------------
    // Regression test (the
    // direction-agnostic `scroll_settled` false-positive) plus the
    // coverage of (unsupported_scroll, a
    // non-exact-but-changed confirmation, and a multi-poll settle).
    // -----------------------------------------------------------------

    #[test]
    fn move_to_offset_protocol17_down_from_max_does_not_settle_on_the_unmoved_first_poll() {
        // Regression: starting exactly at max_offset_from_bottom
        // and moving Down (back towards the bottom) -- the old
        // direction-agnostic `scroll_settled` would treat the very first
        // poll (still reading offset == max, before AttachScroll took
        // effect) as "settled" without the position having moved. This
        // must now wait for the second poll, where the position actually
        // changed.
        let (client, mut server) = UnixStream::pair().unwrap();
        let attach_thread = std::thread::spawn(move || {
            let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let _attach: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            let _resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();
            // current=500=max, target=100 -> Down, 400 lines.
            let scroll_msg: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            scroll_msg
        });
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let session = Attach17::from_stream(
            client,
            "w1:p2",
            crate::winsize::Winsize {
                cols: 80,
                rows: 24,
                cell_width_px: 0,
                cell_height_px: 0,
            },
            deadline,
        )
        .expect("attach17");
        let mut handle = RoundTripHandle::Attach17(session);

        let path = json_socket_path("move17-down-from-max");
        let listener = UnixListener::bind(&path).unwrap();
        // Poll 1: AttachScroll not yet applied -- still at max (500),
        // unchanged from the start. Must NOT be accepted as settled.
        let poll1 = pane_info_response_with_max(500, 500);
        // Poll 2: the move has now taken effect.
        let poll2 = pane_info_response_with_max(300, 500);
        let poll_thread = std::thread::spawn(move || serve_sequence(listener, &[&poll1, &poll2]));

        let (_, result) = move_to_offset(
            &mut handle,
            path.to_str().unwrap(),
            "w1:p2",
            500,
            100,
            deadline,
        );
        let confirmed = result.expect("move_to_offset");
        assert_eq!(
            confirmed.offset_from_bottom, 300,
            "must keep polling past the unmoved first response"
        );

        let scroll_msg = attach_thread.join().unwrap();
        match scroll_msg {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 1, "1 = Down towards the bottom");
                assert_eq!(lines, 400);
            }
            other => panic!("expected AttachScroll, got {:?}", other),
        }
        let sent = poll_thread.join().unwrap();
        assert_eq!(
            sent.len(),
            2,
            "must have polled exactly twice, not settled on the first"
        );
        let _ = std::fs::remove_file(&path);
        close_round_trip(handle);
    }

    #[test]
    fn move_to_offset_protocol17_settles_on_a_changed_but_not_exact_target_match() {
        // herdr may round/clamp so the confirmed position
        // differs from the requested target (18, not the requested 20) --
        // `move_to_offset` must still accept it (report the *actual*
        // position) rather than treating it as unsettled.
        let (client, mut server) = UnixStream::pair().unwrap();
        let attach_thread = std::thread::spawn(move || {
            let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let _attach: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            let _resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();
            let _scroll: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        });
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let session = Attach17::from_stream(
            client,
            "w1:p2",
            crate::winsize::Winsize {
                cols: 80,
                rows: 24,
                cell_width_px: 0,
                cell_height_px: 0,
            },
            deadline,
        )
        .expect("attach17");
        let mut handle = RoundTripHandle::Attach17(session);

        let path = json_socket_path("move17-inexact");
        let listener = UnixListener::bind(&path).unwrap();
        let poll_resp = pane_info_response(18); // requested target is 20
        let poll_thread = std::thread::spawn(move || serve_sequence(listener, &[&poll_resp]));

        let (_, result) = move_to_offset(
            &mut handle,
            path.to_str().unwrap(),
            "w1:p2",
            5,
            20,
            deadline,
        );
        let confirmed = result.expect("move_to_offset");
        assert_eq!(
            confirmed.offset_from_bottom, 18,
            "must report the real (clamped/rounded) position"
        );

        attach_thread.join().unwrap();
        let _ = poll_thread.join().unwrap();
        let _ = std::fs::remove_file(&path);
        close_round_trip(handle);
    }

    #[test]
    fn record_original_position_is_unsupported_scroll_when_pane_has_no_scroll_field() {
        let path = json_socket_path("record-unsupported");
        let listener = UnixListener::bind(&path).unwrap();
        let response = pane_info_response_without_scroll();
        let t = std::thread::spawn(move || serve_sequence(listener, &[&response]));
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let err = record_original_position(path.to_str().unwrap(), "w1:p2", deadline)
            .expect_err("must fail without a scroll field");
        assert!(matches!(err, RunError::UnsupportedScroll));
        t.join().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn move_to_offset_protocol22_is_unsupported_scroll_when_pane_scroll_response_has_no_scroll_field(
    ) {
        let path = json_socket_path("move22-unsupported");
        let listener = UnixListener::bind(&path).unwrap();
        let response = pane_info_response_without_scroll();
        let t = std::thread::spawn(move || serve_sequence(listener, &[&response]));
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let mut handle = RoundTripHandle::Api;
        let (attempted, result) = move_to_offset(
            &mut handle,
            path.to_str().unwrap(),
            "w1:p2",
            0,
            12,
            deadline,
        );
        let err = result.expect_err("must fail without a scroll field");
        assert!(
            attempted,
            "the send was attempted even though it then failed to confirm"
        );
        assert!(matches!(err, RunError::UnsupportedScroll));
        t.join().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    // -----------------------------------------------------------------
    // `open_round_trip` must pass
    // (params.cols, original.viewport_rows) as both `Hello`'s and
    // `Resize`'s dimensions — a mismatch resizes the user's real terminal
    // and triggers an unwanted SIGWINCH. These go through
    // `open_round_trip` itself (not `Attach17::from_stream` directly, like
    // the `move_to_offset_*` tests above) over a real socket path, since
    // `open_round_trip` only exposes `Attach17::connect`/`Attach20::connect`.
    // -----------------------------------------------------------------

    fn scrollback_params(socket: &str, protocol: u8, cols: u16) -> ScrollbackParams {
        ScrollbackParams {
            api_socket: "unused".to_owned(),
            socket: socket.to_owned(),
            pane: "w1:p2".to_owned(),
            protocol,
            cols,
            windows: vec![5],
            timeout_ms: DEFAULT_TIMEOUT_MS,
            restore_budget_ms: DEFAULT_RESTORE_BUDGET_MS,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: "/tmp".to_owned(),
        }
    }

    #[test]
    fn open_round_trip_protocol17_sends_pane_width_and_viewport_rows_as_attach_dims() {
        let path = json_socket_path("open-round-trip17");
        let listener = UnixListener::bind(&path).unwrap();
        let server_thread = std::thread::spawn(move || {
            let mut server = accept_with_deadline(&listener);
            let hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let attach: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            let resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 73,
                    height: 29,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();
            (hello, attach, resize)
        });

        let path_str = path.to_str().unwrap().to_owned();
        let params = scrollback_params(&path_str, 17, 73);
        let original = OriginalPosition {
            offset_from_bottom: 0,
            max_offset_from_bottom: 0,
            viewport_rows: 29,
            terminal_id: "term-abc".to_owned(),
        };
        let size = crate::winsize::Winsize {
            cols: 73,
            rows: 29,
            cell_width_px: 480,
            cell_height_px: 290,
        };
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let handle = open_round_trip(&params, &original, size, deadline).expect("open_round_trip");

        let (hello, attach, resize) = server_thread.join().unwrap();
        match attach {
            ClientMessage17::AttachTerminal { terminal_id, .. } => {
                assert_eq!(
                    terminal_id, "term-abc",
                    "AttachTerminal.terminal_id must be original.terminal_id, not params.pane"
                );
            }
            other => panic!("expected AttachTerminal, got {:?}", other),
        }
        match hello {
            ClientMessage17::Hello {
                cols,
                rows,
                cell_width_px,
                cell_height_px,
                ..
            } => {
                assert_eq!(
                    cols, 73,
                    "Hello cols must come from the resolved real size, not params.cols"
                );
                assert_eq!(rows, 29, "Hello rows must come from the resolved real size");
                assert_eq!(
                    cell_width_px, 480,
                    "Hello cell_width_px must come from the resolved real size"
                );
                assert_eq!(
                    cell_height_px, 290,
                    "Hello cell_height_px must come from the resolved real size"
                );
            }
            other => panic!("expected Hello, got {:?}", other),
        }
        match resize {
            ClientMessage17::Resize {
                cols,
                rows,
                cell_width_px,
                cell_height_px,
            } => {
                assert_eq!(cols, 73);
                assert_eq!(rows, 29);
                assert_eq!(
                    cell_width_px, 480,
                    "Resize cell_width_px must match Hello's"
                );
                assert_eq!(
                    cell_height_px, 290,
                    "Resize cell_height_px must match Hello's"
                );
            }
            other => panic!("expected Resize, got {:?}", other),
        }
        close_round_trip(handle);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn open_round_trip_protocol20_sends_pane_width_and_viewport_rows_as_attach_dims() {
        let path = json_socket_path("open-round-trip20");
        let listener = UnixListener::bind(&path).unwrap();
        let server_thread = std::thread::spawn(move || {
            let mut server = accept_with_deadline(&listener);
            let hello: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage20::Welcome {
                    version: 20,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let attach: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            let resize: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage20::Terminal(TerminalFrame {
                    seq: 1,
                    width: 54,
                    height: 23,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();
            (hello, attach, resize)
        });

        let path_str = path.to_str().unwrap().to_owned();
        let params = scrollback_params(&path_str, 20, 54);
        let original = OriginalPosition {
            offset_from_bottom: 0,
            max_offset_from_bottom: 0,
            viewport_rows: 23,
            terminal_id: "term-abc".to_owned(),
        };
        let size = crate::winsize::Winsize {
            cols: 54,
            rows: 23,
            cell_width_px: 378,
            cell_height_px: 230,
        };
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let handle = open_round_trip(&params, &original, size, deadline).expect("open_round_trip");

        let (hello, attach, resize) = server_thread.join().unwrap();
        match attach {
            ClientMessage20::AttachTerminal { terminal_id, .. } => {
                assert_eq!(
                    terminal_id, "term-abc",
                    "AttachTerminal.terminal_id must be original.terminal_id, not params.pane"
                );
            }
            other => panic!("expected AttachTerminal, got {:?}", other),
        }
        match hello {
            ClientMessage20::Hello {
                cols,
                rows,
                cell_width_px,
                cell_height_px,
                ..
            } => {
                assert_eq!(
                    cols, 54,
                    "Hello cols must come from the resolved real size, not params.cols"
                );
                assert_eq!(rows, 23, "Hello rows must come from the resolved real size");
                assert_eq!(
                    cell_width_px, 378,
                    "Hello cell_width_px must come from the resolved real size"
                );
                assert_eq!(
                    cell_height_px, 230,
                    "Hello cell_height_px must come from the resolved real size"
                );
            }
            other => panic!("expected Hello, got {:?}", other),
        }
        match resize {
            ClientMessage20::Resize {
                cols,
                rows,
                cell_width_px,
                cell_height_px,
            } => {
                assert_eq!(cols, 54);
                assert_eq!(rows, 23);
                assert_eq!(
                    cell_width_px, 378,
                    "Resize cell_width_px must match Hello's"
                );
                assert_eq!(
                    cell_height_px, 230,
                    "Resize cell_height_px must match Hello's"
                );
            }
            other => panic!("expected Resize, got {:?}", other),
        }
        close_round_trip(handle);
        let _ = std::fs::remove_file(&path);
    }

    // -----------------------------------------------------------------
    // Tests for `restore_position`'s classification (straight-line
    // form), `render_scrollback_output`'s truncation boundary cases,
    // and one end-to-end `run_scrollback_links` happy path.
    // -----------------------------------------------------------------

    use crate::wire22::{ClientMessage22, ServerMessage22Known};

    /// RAII guard around a test's unique `--lock-dir` path: removes the
    /// directory (and anything `run_scrollback_links`'s `acquire_lock`
    /// created under it) on drop, including when a test panics partway
    /// through (an `assert!`/`expect` failure before the old manual
    /// `remove_dir_all` call would otherwise skip cleanup entirely).
    /// Without it, the manual
    /// end-of-test cleanup leaves `/tmp/scrollback-test-locks-*`
    /// directories behind from failed runs; this guard makes
    /// cleanup unconditional instead of reachable only on the success
    /// path.
    struct LockDirGuard(PathBuf);

    impl LockDirGuard {
        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for LockDirGuard {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn fresh_lock_dir(name: &str) -> LockDirGuard {
        LockDirGuard(std::env::temp_dir().join(format!(
            "scrollback-test-locks-{}-{}-{}",
            name,
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        )))
    }

    #[test]
    fn restore_position_not_moved_and_originally_at_bottom_confirms_exact() {
        // `moved = false` (no scroll
        // command was ever dispatched, judged by `move_to_offset`'s own
        // "attempted" flag -- not by comparing `t`/`o0`) with `o0 == 0`
        // still confirms via a single `pane.get` read; if it reads back 0,
        // the outcome is `Exact`.
        let path = json_socket_path("restore-not-moved-bottom");
        let listener = UnixListener::bind(&path).unwrap();
        let o1_resp = pane_info_response(0);
        let t = std::thread::spawn(move || serve_sequence(listener, &[&o1_resp]));
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            path.to_str().unwrap(),
            "w1:p2",
            RestorePlan {
                o0: 0,
                t: 0,
                moved: false,
                last_move_confirmed: true,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::Exact);
        let sent = t.join().unwrap();
        assert_eq!(
            sent.len(),
            1,
            "must not issue any call beyond the single pane.get read"
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn restore_position_not_moved_and_originally_at_bottom_but_now_elsewhere_is_failed() {
        // moved=false, o0=0, but the confirming pane.get reads back
        // something other than 0 (e.g. concurrent PC-side scroll) -- must
        // not be reported as Exact.
        let path = json_socket_path("restore-not-moved-bottom-drifted");
        let listener = UnixListener::bind(&path).unwrap();
        let o1_resp = pane_info_response(3);
        let t = std::thread::spawn(move || serve_sequence(listener, &[&o1_resp]));
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            path.to_str().unwrap(),
            "w1:p2",
            RestorePlan {
                o0: 0,
                t: 0,
                moved: false,
                last_move_confirmed: true,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::Failed);
        t.join().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn restore_position_not_moved_and_nonzero_origin_is_approximate_without_any_call() {
        // moved=false with o0 > 0 classifies as
        // `approximate` directly (the contract's `exact` is reserved for
        // "was at the bottom and confirmed back at the bottom") -- and, since
        // nothing moved, no
        // restore command AND no confirming `pane.get` call is sent at all.
        // An unreachable socket proves this: any attempted call would
        // surface as `RestoreOutcome::Failed`, not `Approximate`.
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            "/dev/null/unreachable.sock",
            "w1:p2",
            RestorePlan {
                o0: 7,
                t: 7,
                moved: false,
                last_move_confirmed: true,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::Approximate);
    }

    #[test]
    fn restore_position_moved_o0_gt_0_always_attempts_a_real_call_never_a_noop_shortcut() {
        // `restore_position` is a pure function of its inputs: it cannot
        // itself tell whether `t` accurately reflects the last window
        // move's attempted target (keeping that accurate on an unconfirmed
        // failure is `run_scrollback_links`'s job -- see the
        // `current_offset = target` fix on the loop's `Err` arm).
        // What this level *can* and must guarantee: once `moved = true`,
        // the `o0 > 0` branch always issues a real `move_to_offset` call
        // and classifies the result -- it never takes a "nothing to do"
        // shortcut just because the computed target happens to equal `o1`
        // (as it does here: o0=5, t=5, o1=25 -> target = o0+(o1-t) = 25).
        let path = json_socket_path("restore-o0-gt-0-real-call");
        let listener = UnixListener::bind(&path).unwrap();
        let o1_resp = pane_info_response(25);
        let scroll_resp = pane_info_response(25);
        let poll_resp = pane_info_response(25);
        let t = std::thread::spawn(move || {
            serve_sequence(listener, &[&o1_resp, &scroll_resp, &poll_resp])
        });
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            path.to_str().unwrap(),
            "w1:p2",
            RestorePlan {
                o0: 5,
                t: 5,
                moved: true,
                last_move_confirmed: true,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::Approximate);
        let sent = t.join().unwrap();
        assert!(
            sent.len() >= 2,
            "must issue a real move_to_offset call, not skip because o1==target"
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn restore_position_protocol22_bottom_restore_is_exact() {
        let path = json_socket_path("restore22-bottom");
        let listener = UnixListener::bind(&path).unwrap();
        // 1: read o1 (pane.get). 2: pane.scroll(0) -> offset 0.
        let o1_resp = pane_info_response(12);
        let scroll_resp = pane_info_response(0);
        let t = std::thread::spawn(move || serve_sequence(listener, &[&o1_resp, &scroll_resp]));
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            path.to_str().unwrap(),
            "w1:p2",
            RestorePlan {
                o0: 0,
                t: 12,
                moved: true,
                last_move_confirmed: true,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::Exact);
        let sent = t.join().unwrap();
        assert!(sent[1].contains("\"method\":\"pane.scroll\""));
        assert!(sent[1].contains("\"offset_from_bottom\":0"));
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn restore_position_protocol17_bottom_restore_sends_max_attach_scroll_down() {
        let (client, mut server) = UnixStream::pair().unwrap();
        let attach_thread = std::thread::spawn(move || {
            let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let _attach: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            let _resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut server,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 54,
                    height: 23,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();
            let scroll_msg: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            scroll_msg
        });
        let handshake_deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let session = Attach17::from_stream(
            client,
            "w1:p2",
            crate::winsize::Winsize {
                cols: 54,
                rows: 23,
                cell_width_px: 0,
                cell_height_px: 0,
            },
            handshake_deadline,
        )
        .expect("attach17");

        let path = json_socket_path("restore17-bottom");
        let listener = UnixListener::bind(&path).unwrap();
        let o1_resp = pane_info_response(9);
        let poll_resp = pane_info_response(0);
        let poll_thread =
            std::thread::spawn(move || serve_sequence(listener, &[&o1_resp, &poll_resp]));

        let (handle, outcome) = restore_position(
            RoundTripHandle::Attach17(session),
            path.to_str().unwrap(),
            "w1:p2",
            RestorePlan {
                o0: 0,
                t: 9,
                moved: true,
                last_move_confirmed: true,
            },
            handshake_deadline,
        );
        assert_eq!(outcome, RestoreOutcome::Exact);

        let scroll_msg = attach_thread.join().unwrap();
        match scroll_msg {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 1, "1 = Down towards the bottom");
                assert_eq!(lines, 65535, "maximal Down, not a computed relative delta");
            }
            other => panic!("expected AttachScroll, got {:?}", other),
        }
        let _ = poll_thread.join().unwrap();
        let _ = std::fs::remove_file(&path);
        close_round_trip(handle);
    }

    #[test]
    fn restore_position_protocol22_nonzero_origin_is_approximate() {
        let path = json_socket_path("restore22-approx");
        let listener = UnixListener::bind(&path).unwrap();
        // o0=5, t=20 (last confirmed window position), o1=25 (3 lines of
        // output flowed in during the round trip -- o1 = t + k).
        // target = o0 + (o1 - t) = 5 + (25-20) = 10.
        let o1_resp = pane_info_response(25);
        let scroll_resp = pane_info_response(10);
        let poll_resp = pane_info_response(10);
        let t = std::thread::spawn(move || {
            serve_sequence(listener, &[&o1_resp, &scroll_resp, &poll_resp])
        });
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            path.to_str().unwrap(),
            "w1:p2",
            RestorePlan {
                o0: 5,
                t: 20,
                moved: true,
                last_move_confirmed: true,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::Approximate);
        let sent = t.join().unwrap();
        assert!(
            sent[1].contains("\"offset_from_bottom\":10"),
            "must target o0+(o1-t) = 10, got {:?}",
            sent[1]
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn restore_position_skipped_reset_when_already_back_at_bottom() {
        // o1=0 but t>0: concurrent PC-side input already reset to the
        // bottom during the round trip -- must not move (no second call at
        // all beyond the o1 read).
        let path = json_socket_path("restore-skipped");
        let listener = UnixListener::bind(&path).unwrap();
        let o1_resp = pane_info_response(0);
        let t = std::thread::spawn(move || serve_sequence(listener, &[&o1_resp]));
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            path.to_str().unwrap(),
            "w1:p2",
            RestorePlan {
                o0: 8,
                t: 15,
                moved: true,
                last_move_confirmed: true,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::SkippedReset);
        t.join().unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn restore_position_not_skipped_reset_when_o0_gt_0_but_t_already_confirmed_bottom() {
        // The skipped_reset condition must be
        // keyed on `t > 0`, not `o0 > 0`.
        // Here o0=5 (>0) but the round trip's last window already
        // *confirmed* landing at the bottom (t=0), and o1=0 simply agrees
        // with that -- this is not an unrelated concurrent reset to detect
        // and avoid, so it must fall through to a real approximate-restore
        // attempt (target = o0+(o1-t) = 5), not `SkippedReset`.
        let path = json_socket_path("restore-not-skipped-t-zero");
        let listener = UnixListener::bind(&path).unwrap();
        let o1_resp = pane_info_response(0);
        let move_resp = pane_info_response(5);
        let poll_resp = pane_info_response(5);
        let t = std::thread::spawn(move || {
            serve_sequence(listener, &[&o1_resp, &move_resp, &poll_resp])
        });
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            path.to_str().unwrap(),
            "w1:p2",
            RestorePlan {
                o0: 5,
                t: 0,
                moved: true,
                last_move_confirmed: true,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::Approximate);
        let sent = t.join().unwrap();
        assert!(
            sent[1].contains("\"offset_from_bottom\":5"),
            "must target o0+(o1-t) = 5, got {:?}",
            sent[1]
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn restore_position_confirmed_last_move_with_o0_zero_and_o1_zero_is_skipped_reset() {
        // The `skipped_reset` rule applies just as much when o0=0: the round
        // trip's last window *confirmed* landing away from the bottom
        // (t=10 > 0), and the restore's own fresh o1 read now finds it back
        // at 0 -- a genuine concurrent PC-side reset (trustworthy here
        // specifically because the last move *was* confirmed) --
        // so restore must send nothing, not the usual unconditional bottom
        // restore.
        let path = json_socket_path("restore-confirmed-o0-zero-skipped");
        let listener = UnixListener::bind(&path).unwrap();
        let o1_resp = pane_info_response(0);
        let t = std::thread::spawn(move || serve_sequence(listener, &[&o1_resp]));
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            path.to_str().unwrap(),
            "w1:p2",
            RestorePlan {
                o0: 0,
                t: 10,
                moved: true,
                last_move_confirmed: true,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::SkippedReset);
        let sent = t.join().unwrap();
        assert_eq!(
            sent.len(),
            1,
            "must not send a bottom-restore call once skipped_reset is detected"
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn restore_position_unconfirmed_last_move_with_o0_zero_sends_bottom_restore_without_reading_o1()
    {
        // When the last attempted move's own
        // confirmation never landed (last_move_confirmed=false), the
        // AttachScroll/pane.scroll send and this restore's own pane.get
        // travel over different sockets with no ordering guarantee, so an
        // o1 read here could return a stale pre-effect snapshot. With
        // o0=0 the bottom restore is sent unconditionally instead --
        // without even reading o1 first, since the decision does not
        // depend on it and the send is idempotent either way.
        let path = json_socket_path("restore-unconfirmed-o0-zero");
        let listener = UnixListener::bind(&path).unwrap();
        let scroll_resp = pane_info_response(0);
        let t = std::thread::spawn(move || serve_sequence(listener, &[&scroll_resp]));
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            path.to_str().unwrap(),
            "w1:p2",
            RestorePlan {
                o0: 0,
                t: 10,
                moved: true,
                last_move_confirmed: false,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::Exact);
        let sent = t.join().unwrap();
        assert_eq!(
            sent.len(),
            1,
            "must send the bottom restore directly, no preceding o1 read"
        );
        assert!(sent[0].contains("\"method\":\"pane.scroll\""));
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn restore_position_unconfirmed_last_move_with_o1_zero_is_not_skipped_reset() {
        // With o0=5 (>0) and last_move_confirmed=
        // false, a restore-time o1 read of 0 must NOT be trusted as a
        // genuine concurrent reset (it could be a stale pre-effect
        // snapshot of the still-unconfirmed move) -- so `skipped_reset`
        // must not fire here; restore is attempted regardless (approximate
        // target = o0 + (o1-t) = 5 + (0-20), saturating to 5).
        let path = json_socket_path("restore-unconfirmed-o1-zero");
        let listener = UnixListener::bind(&path).unwrap();
        let o1_resp = pane_info_response(0);
        let move_resp = pane_info_response(5);
        let poll_resp = pane_info_response(5);
        let t = std::thread::spawn(move || {
            serve_sequence(listener, &[&o1_resp, &move_resp, &poll_resp])
        });
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            path.to_str().unwrap(),
            "w1:p2",
            RestorePlan {
                o0: 5,
                t: 20,
                moved: true,
                last_move_confirmed: false,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::Approximate);
        let sent = t.join().unwrap();
        assert!(
            sent.len() >= 2,
            "must not short-circuit to SkippedReset when the last move was unconfirmed"
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn restore_position_is_failed_when_reading_o1_fails() {
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let (_, outcome) = restore_position(
            RoundTripHandle::Api,
            "/dev/null/unreachable.sock",
            "w1:p2",
            RestorePlan {
                o0: 0,
                t: 9,
                moved: true,
                last_move_confirmed: true,
            },
            deadline,
        );
        assert_eq!(outcome, RestoreOutcome::Failed);
    }

    // -- render_scrollback_output truncation (boundary cases) --

    fn sample_fetch(offset: u64, url: &str, row_count: u16) -> WindowFetch {
        let row_hashes: Vec<(u16, String)> = (0..row_count)
            .map(|r| (r, crate::tracker::row_fingerprint("x").unwrap()))
            .collect();
        WindowFetch {
            requested_offset: offset,
            actual_offset: offset,
            frame_width: 80,
            frame_height: row_count,
            links: vec![AggregatedLink {
                url: url.to_owned(),
                ranges: vec![(0, 0, 5)],
            }],
            row_hashes,
            rejected: false,
        }
    }

    #[test]
    fn render_scrollback_output_fits_within_budget_keeps_every_window_untruncated() {
        let fetches = vec![
            sample_fetch(10, "https://a/", 3),
            sample_fetch(20, "https://b/", 3),
        ];
        let json = render_scrollback_output("w1:p2", 22, &fetches, RestoreOutcome::Exact, 60_000);
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        let windows = parsed["windows"].as_array().unwrap();
        assert_eq!(windows.len(), 2);
        assert_eq!(windows[0]["truncated"], false);
        assert_eq!(windows[1]["truncated"], false);
        assert_eq!(windows[0]["rowHashes"].as_array().unwrap().len(), 3);
        assert_eq!(windows[1]["rowHashes"].as_array().unwrap().len(), 3);
    }

    #[test]
    fn render_scrollback_output_tight_budget_keeps_only_the_first_window_full() {
        // Budget just large enough for window 0's full content plus the
        // skeleton of an empty window 1 -- window 1 must survive in the
        // array (not be dropped) with empty links/rowHashes and truncated:true.
        let fetches = vec![
            sample_fetch(10, "https://a/", 3),
            sample_fetch(20, "https://b/", 3),
        ];
        let full = render_scrollback_output("w1:p2", 22, &fetches, RestoreOutcome::Exact, 60_000);
        let empty_second = {
            let only_first = vec![sample_fetch(10, "https://a/", 3)];
            // Skeleton size with window 1 fully empty: build via the same
            // truncation path by giving a budget between "window0 full +
            // window1 empty" and "both full".
            render_scrollback_output("w1:p2", 22, &only_first, RestoreOutcome::Exact, 60_000).len()
        };
        let _ = empty_second; // sanity anchor only, not asserted directly
        let budget = full.len() - 40; // tight enough to force window 1 down
        let json = render_scrollback_output("w1:p2", 22, &fetches, RestoreOutcome::Exact, budget);
        assert!(json.len() <= budget, "must never exceed the budget");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        let windows = parsed["windows"].as_array().unwrap();
        assert_eq!(
            windows.len(),
            2,
            "window 1 must stay in the array, not be dropped"
        );
        assert_eq!(
            windows[0]["truncated"], false,
            "window 0 (requested first) keeps its full content"
        );
        assert_eq!(windows[1]["truncated"], true);
    }

    #[test]
    fn render_scrollback_output_second_window_is_cut_mid_way_bottom_row_first() {
        // A budget between "window0 full + window1 fully empty" and
        // "window0 full + window1 fully full": window1 must keep its
        // bottom rows (highest row numbers) and drop its top rows first,
        // mirroring hyperlinks.rs's own packing rule.
        let fetches = vec![
            sample_fetch(10, "https://a/", 1),
            sample_fetch(20, "https://b/", 6),
        ];
        let full = render_scrollback_output("w1:p2", 22, &fetches, RestoreOutcome::Exact, 60_000);
        let budget = full.len() - 60;
        let json = render_scrollback_output("w1:p2", 22, &fetches, RestoreOutcome::Exact, budget);
        assert!(json.len() <= budget);
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        let windows = parsed["windows"].as_array().unwrap();
        assert_eq!(windows.len(), 2);
        assert_eq!(windows[0]["truncated"], false);
        assert_eq!(windows[1]["truncated"], true);
        let kept_rows: Vec<u64> = windows[1]["rowHashes"]
            .as_array()
            .unwrap()
            .iter()
            .map(|pair| pair[0].as_u64().unwrap())
            .collect();
        assert!(
            kept_rows.len() < 6,
            "window 1 must have lost at least one row"
        );
        let max_row = kept_rows.iter().copied().max();
        if let Some(max_row) = max_row {
            assert_eq!(max_row, 5, "the bottom-most row (5) must be kept first");
        }
    }

    #[test]
    fn render_scrollback_output_skeleton_only_is_still_complete_valid_json() {
        // An impossibly tight budget: every window collapses to an empty
        // skeleton, but the JSON itself must still parse and every window
        // must still be present.
        let fetches = vec![
            sample_fetch(10, "https://a/", 3),
            sample_fetch(20, "https://b/", 3),
        ];
        let json = render_scrollback_output("w1:p2", 22, &fetches, RestoreOutcome::Exact, 1);
        let parsed: serde_json::Value =
            serde_json::from_str(&json).expect("must still be valid json");
        let windows = parsed["windows"].as_array().unwrap();
        assert_eq!(
            windows.len(),
            2,
            "windows must never be dropped from the array"
        );
        for w in windows {
            assert_eq!(w["truncated"], true);
            assert_eq!(w["links"].as_array().unwrap().len(), 0);
        }
    }

    // -- end-to-end `run_scrollback_links` happy path (protocol 22) --

    #[test]
    fn run_scrollback_links_protocol22_happy_path_two_windows_restores_to_bottom() {
        let api_path = json_socket_path("run22-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses: Vec<String> = vec![
            pane_info_response(0), // 1. record_original_position: o0=0
            pane_info_response(0), // 2. resolve_size_fail_open's pane.process_info: wrong
            //    `type` tag (this is a `pane_info` shape) -> treated
            //    as a failure -> falls back to params.cols/viewport_rows
            //    (protocol 22 is fail-*open*, not fail-closed).
            pane_info_response(10), // 3. window1 move: pane.scroll -> offset 10
            pane_info_response(10), // 4. window1 move: confirm poll
            pane_info_response(20), // 5. window2 move: pane.scroll -> offset 20
            pane_info_response(20), // 6. window2 move: confirm poll
            pane_info_response(20), // 7. restore: read o1 (t=20, o1=20 -- no
            //    output flowed in)
            pane_info_response(0), // 8. restore: pane.scroll(0) -> offset 0
        ];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        let client_path = json_socket_path("run22-client");
        let client_listener = UnixListener::bind(&client_path).unwrap();
        let observe_thread = std::thread::spawn(move || {
            for i in 0..2u16 {
                let mut stream = accept_with_deadline(&client_listener);
                // Allow-list: only TerminalHello/ObserveTerminal/Resize
                // are allowed on this connection -- exhaustive matches below
                // fail closed on any other variant (Input/ClipboardImage/
                // ControlTerminal/GraphicsTransmissionResult/AttachTerminal/
                // AttachScroll/Detach).
                let hello: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
                match hello {
                    ClientMessage22::TerminalHello { cols, rows, .. } => {
                        assert_eq!(cols, 80, "TerminalHello cols must be params.cols");
                        assert_eq!(
                            rows, 24,
                            "TerminalHello rows must be pane.get's viewport_rows"
                        );
                    }
                    other => panic!("disallowed message type (allow-list): {:?}", other),
                }
                write_frame(
                    &mut stream,
                    &ServerMessage22Known::Welcome {
                        version: 22,
                        encoding: RenderEncoding::TerminalAnsi,
                        error: None,
                    },
                )
                .unwrap();
                let observe: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
                match observe {
                    ClientMessage22::ObserveTerminal { .. } => {}
                    other => panic!("disallowed message type (allow-list): {:?}", other),
                }
                let resize: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
                match resize {
                    ClientMessage22::Resize { cols, rows, .. } => {
                        assert_eq!(cols, 80, "Resize cols must be params.cols");
                        assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
                    }
                    other => panic!("disallowed message type (allow-list): {:?}", other),
                }
                let bytes =
                    format!("\x1b[1;1H\x1b]8;;https://example.com/w{i}\x1b\\link{i}\x1b]8;;\x1b\\")
                        .into_bytes();
                write_frame(
                    &mut stream,
                    &ServerMessage22Known::Terminal(TerminalFrame {
                        seq: 1,
                        width: 80,
                        height: 24,
                        full: true,
                        bytes,
                    }),
                )
                .unwrap();

                // The observe connection sends
                // nothing further -- it is simply dropped once
                // `observe_window` returns (protocol 22 never sends `Detach`
                // at all: scrolling goes through `pane.scroll` on the api
                // socket, not this client socket).
                stream
                    .set_read_timeout(Some(std::time::Duration::from_secs(2)))
                    .unwrap();
                let extra: Result<ClientMessage22, String> =
                    read_frame(&mut stream, MAX_FRAME_SIZE);
                assert_eq!(
                    extra.unwrap_err(),
                    "unexpected_eof",
                    "observe connection must close after the frame, got a different error"
                );
            }
        });

        let lock_dir = fresh_lock_dir("run22");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: client_path.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 22,
            cols: 80,
            windows: vec![10, 20],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let json = run_scrollback_links(&params).expect("run_scrollback_links");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        assert_eq!(parsed["paneId"], "w1:p2");
        assert_eq!(parsed["protocolVersion"], 22);
        assert_eq!(parsed["restore"], "exact");
        let windows = parsed["windows"].as_array().unwrap();
        assert_eq!(windows.len(), 2);
        assert_eq!(windows[0]["requestedOffset"], 10);
        assert_eq!(windows[0]["actualOffset"], 10);
        assert_eq!(windows[0]["links"][0]["url"], "https://example.com/w0");
        assert_eq!(windows[1]["requestedOffset"], 20);
        assert_eq!(windows[1]["actualOffset"], 20);
        assert_eq!(windows[1]["links"][0]["url"], "https://example.com/w1");

        // Parse each api_socket request line as
        // JSON and compare `method` by exact equality, not substring match.
        let sent = api_thread.join().unwrap();
        for line in &sent {
            let value: serde_json::Value =
                serde_json::from_str(line).expect("valid json request line");
            let method = value["method"].as_str().expect("method field present");
            assert!(
                method == "pane.get" || method == "pane.scroll" || method == "pane.process_info",
                "disallowed api method (allow-list): {method}"
            );
        }
        observe_thread.join().unwrap();
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&client_path);
    }

    // -- 17/20 end-to-end integration (the happy-path integration test
    // previously only
    // covered protocol 22) --

    #[test]
    fn run_scrollback_links_protocol17_happy_path_two_windows_restores_to_bottom() {
        // A real pty+process, sized exactly 80x24 with no pixel geometry
        // (xpixel/ypixel=0), so `resolve_size_fail_closed`'s
        // `winsize::real_size` call succeeds for real and returns exactly
        // the same cols/rows/cell_px this test already asserted when the
        // dimensions were still hardcoded -- see `spawn_real_pty_process`.
        let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
        let api_path = json_socket_path("run17-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses = [
            pane_info_response(0), // 1. record_original_position: o0=0
            pane_process_info_response(real_shell.id()), // 2. resolve_size_fail_closed's pane.process_info
            pane_info_response(10), // 3. window1 move: confirm poll (AttachScroll has no response)
            pane_info_response(20), // 4. window2 move: confirm poll
            pane_info_response(20), // 5. restore: read o1 -> 20 (o0=0 -> bottom restore)
            pane_info_response(0),  // 6. restore: confirm poll -> 0
        ];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        // `params.socket`: one persistent attach connection (open_round_trip,
        // held for both window moves and the final restore's AttachScroll),
        // plus one fresh connection per window for `observe_window`).
        let client_path = json_socket_path("run17-client");
        let client_listener = UnixListener::bind(&client_path).unwrap();
        let client_thread = std::thread::spawn(move || {
            // Allow-list: every frame read on this connection is
            // matched against an exhaustive allow-list (Hello/AttachTerminal/
            // AttachScroll/ObserveTerminal/Resize/Detach) -- `other => panic!`
            // fails closed on Input/ClipboardImage/InputEvents/ControlTerminal.
            let mut attach = accept_with_deadline(&client_listener);
            let hello: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match hello {
                ClientMessage17::Hello { cols, rows, .. } => {
                    assert_eq!(cols, 80, "Hello cols must be params.cols");
                    assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            write_frame(
                &mut attach,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let attach_terminal: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match attach_terminal {
                ClientMessage17::AttachTerminal { terminal_id, .. } => {
                    // Note: this
                    // representative happy-path test's fake previously
                    // didn't check terminal_id at all, which is exactly how
                    // the pane-notation-vs-terminal_id bug slipped past
                    // the other tests before the dedicated regression tests existed.
                    assert_eq!(
                        terminal_id, "term-abc",
                        "AttachTerminal.terminal_id must be pane.get's terminal_id, not params.pane"
                    );
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let resize: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match resize {
                ClientMessage17::Resize { cols, rows, .. } => {
                    assert_eq!(cols, 80, "Resize cols must be params.cols");
                    assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            write_frame(
                &mut attach,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();

            // window1 move: 0 -> 10 (further from bottom) -> Up, 10 lines.
            let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match scroll_msg {
                ClientMessage17::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 0, "0 = Up into scrollback");
                    assert_eq!(lines, 10);
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }

            let mut obs1 = accept_with_deadline(&client_listener);
            let hello: ClientMessage17 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
            match hello {
                ClientMessage17::Hello { cols, rows, .. } => {
                    assert_eq!(cols, 80, "Hello cols must be params.cols");
                    assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            write_frame(
                &mut obs1,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let observe: ClientMessage17 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
            match observe {
                ClientMessage17::ObserveTerminal { .. } => {}
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let resize: ClientMessage17 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
            match resize {
                ClientMessage17::Resize { cols, rows, .. } => {
                    assert_eq!(cols, 80, "Resize cols must be params.cols");
                    assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let bytes0 =
                b"\x1b[1;1H\x1b]8;;https://example.com/w0\x1b\\link0\x1b]8;;\x1b\\".to_vec();
            write_frame(
                &mut obs1,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: bytes0,
                }),
            )
            .unwrap();
            // The observe connection is simply
            // dropped once `observe_window` returns -- never `Detach`.
            obs1.set_read_timeout(Some(std::time::Duration::from_secs(2)))
                .unwrap();
            let extra: Result<ClientMessage17, String> = read_frame(&mut obs1, MAX_FRAME_SIZE);
            assert_eq!(
                extra.unwrap_err(),
                "unexpected_eof",
                "obs1 must close after the frame, got a different error"
            );

            // window2 move: 10 -> 20 -> Up, 10 lines.
            let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match scroll_msg {
                ClientMessage17::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 0);
                    assert_eq!(lines, 10);
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }

            let mut obs2 = accept_with_deadline(&client_listener);
            let hello: ClientMessage17 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
            match hello {
                ClientMessage17::Hello { cols, rows, .. } => {
                    assert_eq!(cols, 80, "Hello cols must be params.cols");
                    assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            write_frame(
                &mut obs2,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let observe: ClientMessage17 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
            match observe {
                ClientMessage17::ObserveTerminal { .. } => {}
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let resize: ClientMessage17 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
            match resize {
                ClientMessage17::Resize { cols, rows, .. } => {
                    assert_eq!(cols, 80, "Resize cols must be params.cols");
                    assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let bytes1 =
                b"\x1b[1;1H\x1b]8;;https://example.com/w1\x1b\\link1\x1b]8;;\x1b\\".to_vec();
            write_frame(
                &mut obs2,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: bytes1,
                }),
            )
            .unwrap();
            obs2.set_read_timeout(Some(std::time::Duration::from_secs(2)))
                .unwrap();
            let extra: Result<ClientMessage17, String> = read_frame(&mut obs2, MAX_FRAME_SIZE);
            assert_eq!(
                extra.unwrap_err(),
                "unexpected_eof",
                "obs2 must close after the frame, got a different error"
            );

            // restore: bottom -> AttachScroll{Down, 65535}.
            let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match scroll_msg {
                ClientMessage17::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 1, "1 = Down towards the bottom");
                    assert_eq!(lines, 65535);
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }

            // `close_round_trip` sends `Detach` and
            // nothing after it.
            let detach: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(detach, ClientMessage17::Detach),
                "expected Detach, got {:?}",
                detach
            );
            attach
                .set_read_timeout(Some(std::time::Duration::from_secs(2)))
                .unwrap();
            let extra: Result<ClientMessage17, String> = read_frame(&mut attach, MAX_FRAME_SIZE);
            assert_eq!(
                extra.unwrap_err(),
                "unexpected_eof",
                "attach connection must close after Detach, got a different error"
            );
        });

        let lock_dir = fresh_lock_dir("run17");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: client_path.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 17,
            cols: 80,
            windows: vec![10, 20],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let json = run_scrollback_links(&params).expect("run_scrollback_links");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        assert_eq!(parsed["paneId"], "w1:p2");
        assert_eq!(parsed["protocolVersion"], 17);
        assert_eq!(parsed["restore"], "exact");
        let windows = parsed["windows"].as_array().unwrap();
        assert_eq!(windows.len(), 2);
        assert_eq!(windows[0]["requestedOffset"], 10);
        assert_eq!(windows[0]["actualOffset"], 10);
        assert_eq!(windows[0]["links"][0]["url"], "https://example.com/w0");
        assert_eq!(windows[1]["requestedOffset"], 20);
        assert_eq!(windows[1]["actualOffset"], 20);
        assert_eq!(windows[1]["links"][0]["url"], "https://example.com/w1");

        // Parse each api_socket request line as
        // JSON and compare `method` by exact equality, not substring match.
        let sent = api_thread.join().unwrap();
        for line in &sent {
            let value: serde_json::Value =
                serde_json::from_str(line).expect("valid json request line");
            let method = value["method"].as_str().expect("method field present");
            assert!(
                method == "pane.get" || method == "pane.scroll" || method == "pane.process_info",
                "disallowed api method (allow-list): {method}"
            );
        }
        client_thread.join().unwrap();
        let _ = real_shell.kill();
        let _ = real_shell.wait();
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&client_path);
    }

    #[test]
    fn run_scrollback_links_protocol20_happy_path_two_windows_restores_to_bottom() {
        let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 100, 0, 0);
        let api_path = json_socket_path("run20-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses = [
            pane_info_response(0), // 1. record_original_position: o0=0
            pane_process_info_response(real_shell.id()), // 2. resolve_size_fail_closed's pane.process_info
            pane_info_response(10),                      // 3. window1 move: confirm poll
            pane_info_response(20),                      // 4. window2 move: confirm poll
            pane_info_response(20), // 5. restore: read o1 -> 20 (o0=0 -> bottom restore)
            pane_info_response(0),  // 6. restore: confirm poll -> 0
        ];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        let client_path = json_socket_path("run20-client");
        let client_listener = UnixListener::bind(&client_path).unwrap();
        let client_thread = std::thread::spawn(move || {
            // Allow-list: every frame read on this connection is
            // matched against an exhaustive allow-list (Hello/AttachTerminal/
            // AttachScroll/ObserveTerminal/Resize/Detach) -- `other => panic!`
            // fails closed on Input/ClipboardImage/InputEvents/ControlTerminal.
            let mut attach = accept_with_deadline(&client_listener);
            let hello: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match hello {
                ClientMessage20::Hello { cols, rows, .. } => {
                    assert_eq!(cols, 100, "Hello cols must be params.cols");
                    assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            write_frame(
                &mut attach,
                &ServerMessage20::Welcome {
                    version: 20,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let attach_terminal: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match attach_terminal {
                ClientMessage20::AttachTerminal { terminal_id, .. } => {
                    // As in the protocol17 happy-path test above: the fake checks terminal_id.
                    assert_eq!(
                        terminal_id, "term-abc",
                        "AttachTerminal.terminal_id must be pane.get's terminal_id, not params.pane"
                    );
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let resize: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match resize {
                ClientMessage20::Resize { cols, rows, .. } => {
                    assert_eq!(cols, 100, "Resize cols must be params.cols");
                    assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            write_frame(
                &mut attach,
                &ServerMessage20::Terminal(TerminalFrame {
                    seq: 1,
                    width: 100,
                    height: 24,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();

            let scroll_msg: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match scroll_msg {
                ClientMessage20::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 0, "0 = Up into scrollback");
                    assert_eq!(lines, 10);
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }

            let mut obs1 = accept_with_deadline(&client_listener);
            let hello: ClientMessage20 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
            match hello {
                ClientMessage20::Hello { cols, rows, .. } => {
                    assert_eq!(cols, 100, "Hello cols must be params.cols");
                    assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            write_frame(
                &mut obs1,
                &ServerMessage20::Welcome {
                    version: 20,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let observe: ClientMessage20 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
            match observe {
                ClientMessage20::ObserveTerminal { .. } => {}
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let resize: ClientMessage20 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
            match resize {
                ClientMessage20::Resize { cols, rows, .. } => {
                    assert_eq!(cols, 100, "Resize cols must be params.cols");
                    assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let bytes0 =
                b"\x1b[1;1H\x1b]8;;https://example.com/w0\x1b\\link0\x1b]8;;\x1b\\".to_vec();
            write_frame(
                &mut obs1,
                &ServerMessage20::Terminal(TerminalFrame {
                    seq: 1,
                    width: 100,
                    height: 24,
                    full: true,
                    bytes: bytes0,
                }),
            )
            .unwrap();
            // The observe connection is simply
            // dropped once `observe_window` returns -- never `Detach`.
            obs1.set_read_timeout(Some(std::time::Duration::from_secs(2)))
                .unwrap();
            let extra: Result<ClientMessage20, String> = read_frame(&mut obs1, MAX_FRAME_SIZE);
            assert_eq!(
                extra.unwrap_err(),
                "unexpected_eof",
                "obs1 must close after the frame, got a different error"
            );

            let scroll_msg: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match scroll_msg {
                ClientMessage20::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 0);
                    assert_eq!(lines, 10);
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }

            let mut obs2 = accept_with_deadline(&client_listener);
            let hello: ClientMessage20 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
            match hello {
                ClientMessage20::Hello { cols, rows, .. } => {
                    assert_eq!(cols, 100, "Hello cols must be params.cols");
                    assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            write_frame(
                &mut obs2,
                &ServerMessage20::Welcome {
                    version: 20,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let observe: ClientMessage20 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
            match observe {
                ClientMessage20::ObserveTerminal { .. } => {}
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let resize: ClientMessage20 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
            match resize {
                ClientMessage20::Resize { cols, rows, .. } => {
                    assert_eq!(cols, 100, "Resize cols must be params.cols");
                    assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let bytes1 =
                b"\x1b[1;1H\x1b]8;;https://example.com/w1\x1b\\link1\x1b]8;;\x1b\\".to_vec();
            write_frame(
                &mut obs2,
                &ServerMessage20::Terminal(TerminalFrame {
                    seq: 1,
                    width: 100,
                    height: 24,
                    full: true,
                    bytes: bytes1,
                }),
            )
            .unwrap();
            obs2.set_read_timeout(Some(std::time::Duration::from_secs(2)))
                .unwrap();
            let extra: Result<ClientMessage20, String> = read_frame(&mut obs2, MAX_FRAME_SIZE);
            assert_eq!(
                extra.unwrap_err(),
                "unexpected_eof",
                "obs2 must close after the frame, got a different error"
            );

            let scroll_msg: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match scroll_msg {
                ClientMessage20::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 1, "1 = Down towards the bottom");
                    assert_eq!(lines, 65535);
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }

            // `close_round_trip` sends `Detach` and
            // nothing after it.
            let detach: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(detach, ClientMessage20::Detach),
                "expected Detach, got {:?}",
                detach
            );
            attach
                .set_read_timeout(Some(std::time::Duration::from_secs(2)))
                .unwrap();
            let extra: Result<ClientMessage20, String> = read_frame(&mut attach, MAX_FRAME_SIZE);
            assert_eq!(
                extra.unwrap_err(),
                "unexpected_eof",
                "attach connection must close after Detach, got a different error"
            );
        });

        let lock_dir = fresh_lock_dir("run20");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: client_path.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 20,
            cols: 100,
            windows: vec![10, 20],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let json = run_scrollback_links(&params).expect("run_scrollback_links");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        assert_eq!(parsed["paneId"], "w1:p2");
        assert_eq!(parsed["protocolVersion"], 20);
        assert_eq!(parsed["restore"], "exact");
        let windows = parsed["windows"].as_array().unwrap();
        assert_eq!(windows.len(), 2);
        assert_eq!(windows[0]["requestedOffset"], 10);
        assert_eq!(windows[0]["actualOffset"], 10);
        assert_eq!(windows[0]["links"][0]["url"], "https://example.com/w0");
        assert_eq!(windows[1]["requestedOffset"], 20);
        assert_eq!(windows[1]["actualOffset"], 20);
        assert_eq!(windows[1]["links"][0]["url"], "https://example.com/w1");

        // Parse each api_socket request line as
        // JSON and compare `method` by exact equality, not substring match.
        let sent = api_thread.join().unwrap();
        for line in &sent {
            let value: serde_json::Value =
                serde_json::from_str(line).expect("valid json request line");
            let method = value["method"].as_str().expect("method field present");
            assert!(
                method == "pane.get" || method == "pane.scroll" || method == "pane.process_info",
                "disallowed api method (allow-list): {method}"
            );
        }
        client_thread.join().unwrap();
        let _ = real_shell.kill();
        let _ = real_shell.wait();
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&client_path);
    }

    // -- Guard/fail-closed tests ------------------------------------------
    //
    // Both tests below deliberately do *not* bind a `UnixListener` on
    // `params.socket` at all: if a regression ever made `open_round_trip`
    // reachable in either scenario, `UnixStream::connect` would fail with
    // `RunError::Connect` (no listener exists at that path) rather than the
    // test hanging -- so a would-be-attach regression fails loudly as a
    // *different*, immediately-visible error variant instead of silently
    // passing or deadlocking.

    #[test]
    fn run_scrollback_links_protocol17_guard_skip_sends_no_attach_and_returns_empty_windows() {
        // o0 = 5 (not already at the bottom) -> the 17/20 guard
        // (`o0 == 0 && max_offset_from_bottom > 0`) fails on its first
        // condition. No `pane.process_info`/`winsize::real_size` call, no
        // attach, no `AttachScroll` -- just the one `record_original_position`
        // `pane.get` read, then an immediate return with `windows: []`.
        let api_path = json_socket_path("run17-guardskip-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses = [pane_info_response(5)];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        let lock_dir = fresh_lock_dir("run17-guardskip");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: "/nonexistent/no-listener-here.sock".to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 17,
            cols: 80,
            windows: vec![10, 20],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let json = run_scrollback_links(&params).expect(
            "guard-skip must succeed (no attach attempted) even though params.socket has no listener",
        );
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        assert_eq!(parsed["paneId"], "w1:p2");
        assert_eq!(parsed["protocolVersion"], 17);
        assert_eq!(parsed["restore"], "approximate");
        assert_eq!(
            parsed["windows"].as_array().unwrap().len(),
            0,
            "guard-skip must fetch no windows at all"
        );

        let sent = api_thread.join().unwrap();
        assert_eq!(
            sent.len(),
            1,
            "guard-skip must make exactly one pane.get call and nothing else"
        );
        let value: serde_json::Value = serde_json::from_str(&sent[0]).expect("valid json request");
        assert_eq!(value["method"], "pane.get");

        let _ = std::fs::remove_file(&api_path);
    }

    #[test]
    fn run_scrollback_links_protocol17_guard_skip_on_zero_max_offset_sends_no_attach() {
        // The test
        // above only exercises the guard's *first* condition (`o0 == 0`)
        // failing -- it never exercises the second condition
        // (`max_offset_from_bottom > 0`) on its own, so a mutation that
        // drops the `max_offset_from_bottom > 0` check entirely would still
        // pass every existing test. Here `o0 == 0` (already at the bottom)
        // but `max_offset_from_bottom == 0` (no scrollback at all to move
        // into) -- the guard must still fail and skip the whole round
        // trip: no `pane.process_info`/`winsize::real_size` call, no
        // attach, no `AttachScroll`, `windows: []`.
        let api_path = json_socket_path("run17-guardskip-zeromax-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses = [
            pane_info_response_with_max(0, 0), // 1. record_original_position: o0=0, max=0
            pane_info_response_with_max(0, 0), // 2. restore's `!moved, o0==0` confirmatory pane.get -> still 0 -> Exact
        ];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        let lock_dir = fresh_lock_dir("run17-guardskip-zeromax");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: "/nonexistent/no-listener-here.sock".to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 17,
            cols: 80,
            windows: vec![10, 20],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let json = run_scrollback_links(&params).expect(
            "guard-skip (max_offset_from_bottom == 0) must succeed with no attach attempted",
        );
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        assert_eq!(parsed["restore"], "exact");
        assert_eq!(
            parsed["windows"].as_array().unwrap().len(),
            0,
            "guard-skip must fetch no windows at all"
        );

        let sent = api_thread.join().unwrap();
        assert_eq!(
            sent.len(),
            2,
            "must make exactly record_original_position's pane.get plus restore's \
             confirmatory pane.get -- no pane.process_info call at all"
        );
        for line in &sent {
            let value: serde_json::Value = serde_json::from_str(line).expect("valid json request");
            assert_eq!(
                value["method"], "pane.get",
                "guard-skip must never call pane.process_info"
            );
        }

        let _ = std::fs::remove_file(&api_path);
    }

    #[test]
    fn run_scrollback_links_protocol17_winsize_failure_fails_closed_with_no_attach() {
        // o0 = 0, max_offset_from_bottom = 9999 (default) -> the guard
        // passes, so `resolve_size_fail_closed` is reached and calls
        // `pane.process_info`. Its response names a `shell_pid` that
        // (practically) never corresponds to a running process, so
        // `winsize::real_size` genuinely fails with `ProcessNotRunning` --
        // this is a real failure of the real function, not a mocked-away
        // shortcut. Per the fail-closed rule, this must fail the
        // *whole* run with `RunError::WinsizeUnavailable` before any attach
        // is attempted.
        let bogus_shell_pid: u32 = u32::MAX;
        let api_path = json_socket_path("run17-winsizefail-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses = [
            pane_info_response(0),
            pane_process_info_response(bogus_shell_pid),
        ];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        let lock_dir = fresh_lock_dir("run17-winsizefail");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: "/nonexistent/no-listener-here.sock".to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 17,
            cols: 80,
            windows: vec![10, 20],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let err = run_scrollback_links(&params)
            .expect_err("a winsize::real_size failure must fail the whole run");
        assert!(
            matches!(err, RunError::WinsizeUnavailable(_)),
            "expected WinsizeUnavailable, got {:?}",
            err
        );
        assert!(
            err.json().contains("winsize_unavailable"),
            "RunError::json() kind must be winsize_unavailable, got {}",
            err.json()
        );

        let sent = api_thread.join().unwrap();
        assert_eq!(
            sent.len(),
            2,
            "must make exactly pane.get + pane.process_info, no attach-adjacent calls"
        );
        let v0: serde_json::Value = serde_json::from_str(&sent[0]).expect("valid json request");
        assert_eq!(v0["method"], "pane.get");
        let v1: serde_json::Value = serde_json::from_str(&sent[1]).expect("valid json request");
        assert_eq!(v1["method"], "pane.process_info");

        let _ = std::fs::remove_file(&api_path);
    }

    // -- Discard rule:
    // 17/20 only; condition is "a move was dispatched
    // but the confirmed offset (including a poll timeout's last-observed
    // value) is unchanged from this window's own pre-move offset" -- not
    // "actual != requested" (hitting the scrollback's range end is a
    // legitimate, non-discarded outcome).

    #[test]
    fn run_scrollback_links_protocol17_first_window_never_moves_is_discarded_with_no_restore_sent()
    {
        // Single window (target 10); every poll of its AttachScroll Up(10)
        // confirms the offset is still 0 (stuck -- e.g. an alt-screen/
        // mouse-tracking mode absorbing the input), so `poll_scroll_until`
        // exhausts its budget and returns the last-observed value (`Ok`,
        // not `Err`). Expected: the window is discarded (not observed, not
        // in `fetches`), and since nothing in this run ever genuinely
        // moved, `restore_position` must take the "nothing to restore, no
        // restore command sent" branch -- confirmed here by the
        // attach connection never seeing anything beyond the dispatched
        // AttachScroll and the final `Detach`.
        let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
        let api_path = json_socket_path("run17-discard1-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let stuck_at_zero = pane_info_response_with_max(0, 9999);
        let mut responses: Vec<String> = vec![
            pane_info_response_with_max(0, 9999), // 1. record_original_position: o0=0, max=9999
            pane_process_info_response(real_shell.id()), // 2. resolve_size_fail_closed
        ];
        for _ in 0..10 {
            // 3..=12. window1's AttachScroll Up(10) poll: stuck at 0 for
            // every one of SCROLL_POLL_MAX_ATTEMPTS attempts.
            responses.push(stuck_at_zero.clone());
        }
        responses.push(stuck_at_zero.clone()); // 13. restore's `!moved, o0==0` confirmatory pane.get -> still 0 -> Exact
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        let client_path = json_socket_path("run17-discard1-client");
        let client_listener = UnixListener::bind(&client_path).unwrap();
        let client_thread = std::thread::spawn(move || {
            let mut attach = accept_with_deadline(&client_listener);
            let hello: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(hello, ClientMessage17::Hello { .. }),
                "{:?}",
                hello
            );
            write_frame(
                &mut attach,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let attach_terminal: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(attach_terminal, ClientMessage17::AttachTerminal { .. }),
                "{:?}",
                attach_terminal
            );
            let resize: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(resize, ClientMessage17::Resize { .. }),
                "{:?}",
                resize
            );
            write_frame(
                &mut attach,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();

            let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match scroll_msg {
                ClientMessage17::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 0, "0 = Up into scrollback");
                    assert_eq!(lines, 10);
                }
                other => panic!("expected AttachScroll, got {:?}", other),
            }

            // The discarded window must never be observed: `close_round_trip`
            // sends `Detach` directly next, with no intervening ObserveTerminal
            // handshake and no restore AttachScroll (restore never touches this
            // attach session at all for the `!moved, o0 == 0` branch -- it is
            // pure `pane.get` over the api socket).
            let detach: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(matches!(detach, ClientMessage17::Detach), "{:?}", detach);
            attach
                .set_read_timeout(Some(std::time::Duration::from_secs(2)))
                .unwrap();
            let extra: Result<ClientMessage17, String> = read_frame(&mut attach, MAX_FRAME_SIZE);
            assert_eq!(extra.unwrap_err(), "unexpected_eof");

            // No second connection (an observe attempt) must ever arrive.
            client_listener.set_nonblocking(true).unwrap();
            assert!(
                client_listener.accept().is_err(),
                "a discarded window must never open an observe connection"
            );
        });

        let lock_dir = fresh_lock_dir("run17-discard1");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: client_path.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 17,
            cols: 80,
            windows: vec![10],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let json = run_scrollback_links(&params).expect("run_scrollback_links");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        assert_eq!(
            parsed["windows"].as_array().unwrap().len(),
            0,
            "the only window never moved, so it must be discarded, not fetched"
        );
        assert_eq!(
            parsed["restore"], "exact",
            "nothing ever moved, so restore must take the no-op `!moved, o0 == 0` branch"
        );

        client_thread.join().unwrap();
        let _ = api_thread.join().unwrap();
        let _ = real_shell.kill();
        let _ = real_shell.wait();
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&client_path);
    }

    #[test]
    fn run_scrollback_links_protocol17_second_window_never_moves_keeps_first_and_restores_bottom_once(
    ) {
        // window1 (target 10) genuinely moves 0 -> 10; window2 (target 20)
        // is stuck at 10 for every poll attempt (same "last-observed value"
        // timeout shape as the single-window test above). Expected: only
        // window1's fetch survives, window2 is never observed, processing
        // stops after window2 (no further windows -- none exist here, but
        // the discard `break` is what stops it), and because window1 did
        // genuinely move, restore still runs its normal bottom-restore
        // (`AttachScroll{Down, 65535}`) exactly once.
        let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
        let api_path = json_socket_path("run17-discard2-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let stuck_at_ten = pane_info_response_with_max(10, 9999);
        let mut responses: Vec<String> = vec![
            pane_info_response_with_max(0, 9999), // 1. record_original_position: o0=0
            pane_process_info_response(real_shell.id()), // 2. resolve_size_fail_closed
            pane_info_response_with_max(10, 9999), // 3. window1 move poll: settles at 10 immediately
        ];
        for _ in 0..10 {
            // 4..=13. window2's AttachScroll Up(10) poll: stuck at 10 (its
            // own pre-move offset) for every attempt.
            responses.push(stuck_at_ten.clone());
        }
        responses.push(pane_info_response_with_max(10, 9999)); // 14. restore: read o1 -> 10 (t=10, no concurrent reset)
        responses.push(pane_info_response_with_max(0, 9999)); // 15. restore: confirm poll after Down 65535 -> 0
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        let client_path = json_socket_path("run17-discard2-client");
        let client_listener = UnixListener::bind(&client_path).unwrap();
        let client_thread = std::thread::spawn(move || {
            let mut attach = accept_with_deadline(&client_listener);
            let hello: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(hello, ClientMessage17::Hello { .. }),
                "{:?}",
                hello
            );
            write_frame(
                &mut attach,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let attach_terminal: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(attach_terminal, ClientMessage17::AttachTerminal { .. }),
                "{:?}",
                attach_terminal
            );
            let resize: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(resize, ClientMessage17::Resize { .. }),
                "{:?}",
                resize
            );
            write_frame(
                &mut attach,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();

            // window1: AttachScroll Up(10), 0 -> 10.
            let scroll1: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match scroll1 {
                ClientMessage17::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 0);
                    assert_eq!(lines, 10);
                }
                other => panic!("expected AttachScroll, got {:?}", other),
            }

            // window1's observe (it genuinely moved, so it must be fetched).
            let mut obs1 = accept_with_deadline(&client_listener);
            let hello: ClientMessage17 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(hello, ClientMessage17::Hello { .. }),
                "{:?}",
                hello
            );
            write_frame(
                &mut obs1,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let observe: ClientMessage17 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(observe, ClientMessage17::ObserveTerminal { .. }),
                "{:?}",
                observe
            );
            let resize: ClientMessage17 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(resize, ClientMessage17::Resize { .. }),
                "{:?}",
                resize
            );
            let bytes0 =
                b"\x1b[1;1H\x1b]8;;https://example.com/w0\x1b\\link0\x1b]8;;\x1b\\".to_vec();
            write_frame(
                &mut obs1,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: bytes0,
                }),
            )
            .unwrap();
            obs1.set_read_timeout(Some(std::time::Duration::from_secs(2)))
                .unwrap();
            let extra: Result<ClientMessage17, String> = read_frame(&mut obs1, MAX_FRAME_SIZE);
            assert_eq!(extra.unwrap_err(), "unexpected_eof");

            // window2: AttachScroll Up(10), stuck at 10 -- never observed.
            let scroll2: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match scroll2 {
                ClientMessage17::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 0);
                    assert_eq!(lines, 10);
                }
                other => panic!("expected AttachScroll, got {:?}", other),
            }

            // Restore: window1 genuinely moved, so a real bottom restore is
            // still sent exactly once (`AttachScroll{Down, 65535}`), then
            // `Detach`. No third connection (window2's would-be observe)
            // is ever accepted.
            let restore_scroll: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match restore_scroll {
                ClientMessage17::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 1, "1 = Down towards the bottom");
                    assert_eq!(lines, 65535);
                }
                other => panic!("expected the bottom-restore AttachScroll, got {:?}", other),
            }
            let detach: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(matches!(detach, ClientMessage17::Detach), "{:?}", detach);

            client_listener.set_nonblocking(true).unwrap();
            assert!(
                client_listener.accept().is_err(),
                "window2 was discarded, so it must never open an observe connection"
            );
        });

        let lock_dir = fresh_lock_dir("run17-discard2");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: client_path.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 17,
            cols: 80,
            windows: vec![10, 20],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let json = run_scrollback_links(&params).expect("run_scrollback_links");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        let windows = parsed["windows"].as_array().unwrap();
        assert_eq!(
            windows.len(),
            1,
            "only window1 must survive; window2 is discarded"
        );
        assert_eq!(windows[0]["requestedOffset"], 10);
        assert_eq!(windows[0]["actualOffset"], 10);
        assert_eq!(windows[0]["links"][0]["url"], "https://example.com/w0");
        assert_eq!(
            parsed["restore"], "exact",
            "window1 genuinely moved, so a real bottom restore must still run"
        );

        client_thread.join().unwrap();
        let _ = api_thread.join().unwrap();
        let _ = real_shell.kill();
        let _ = real_shell.wait();
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&client_path);
    }

    #[test]
    fn run_scrollback_links_protocol22_window_that_does_not_move_is_still_observed_not_discarded() {
        // Note: the
        // discard rule is 17/20-only; protocol 22's
        // `pane.scroll` path always dispatches a request (`attempted` is
        // unconditionally `true` in `move_to_offset`'s `RoundTripHandle::
        // Api` branch) and, when the requested target already equals the
        // pane's current position, the confirmed offset is trivially
        // unchanged from the pre-move offset -- exactly the shape the
        // 17/20 discard condition checks for. This must *not* discard the
        // window for protocol 22: it must still be observed and kept in
        // `fetches`.
        let api_path = json_socket_path("run22-nodiscard-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses = [
            pane_info_response_with_max(15, 9999), // 1. record_original_position: o0=15
            pane_info_response(0), // 2. resolve_size_fail_open's pane.process_info: wrong `type` -> fallback
            pane_info_response_with_max(15, 9999), // 3. window0's pane.scroll(target=15) -> still 15
            pane_info_response_with_max(15, 9999), // 4. window0's defensive re-check poll -> still 15
            pane_info_response_with_max(15, 9999), // 5. restore: read o1 -> 15 (t=15, no concurrent reset)
            pane_info_response_with_max(15, 9999), // 6. restore: approximate target o0+(o1-t)=15 -> pane.scroll
            pane_info_response_with_max(15, 9999), // 7. restore: approximate's poll confirm -> 15
        ];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        let client_path = json_socket_path("run22-nodiscard-client");
        let client_listener = UnixListener::bind(&client_path).unwrap();
        let client_thread = std::thread::spawn(move || {
            // Protocol 22 has no persistent attach session: this is the
            // one-shot observe connection for window0, which must be
            // reached even though the pane never moved.
            let mut obs = accept_with_deadline(&client_listener);
            let hello: ClientMessage22 = read_frame(&mut obs, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(hello, ClientMessage22::TerminalHello { .. }),
                "{:?}",
                hello
            );
            write_frame(
                &mut obs,
                &ServerMessage22Known::Welcome {
                    version: 22,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let observe: ClientMessage22 = read_frame(&mut obs, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(observe, ClientMessage22::ObserveTerminal { .. }),
                "{:?}",
                observe
            );
            let resize: ClientMessage22 = read_frame(&mut obs, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(resize, ClientMessage22::Resize { .. }),
                "{:?}",
                resize
            );
            let bytes0 =
                b"\x1b[1;1H\x1b]8;;https://example.com/w0\x1b\\link0\x1b]8;;\x1b\\".to_vec();
            write_frame(
                &mut obs,
                &ServerMessage22Known::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: bytes0,
                }),
            )
            .unwrap();
        });

        let lock_dir = fresh_lock_dir("run22-nodiscard");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: client_path.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 22,
            cols: 80,
            windows: vec![15],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let json = run_scrollback_links(&params).expect("run_scrollback_links");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        let windows = parsed["windows"].as_array().unwrap();
        assert_eq!(
            windows.len(),
            1,
            "protocol 22 must never discard a window that didn't move"
        );
        assert_eq!(windows[0]["requestedOffset"], 15);
        assert_eq!(windows[0]["actualOffset"], 15);
        assert_eq!(windows[0]["links"][0]["url"], "https://example.com/w0");

        client_thread.join().unwrap();
        let _ = api_thread.join().unwrap();
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&client_path);
    }

    // -- Regression: `AttachTerminal.terminal_id`
    // must be the resolved terminal_id from `pane.get`, never the raw
    // `--pane` (pane-target) notation. Real herdr servers (v0.7.5/v0.8.2
    // `attach_terminal_client`) match `terminal_id` by exact equality only
    // -- they never resolve pane notation themselves (confirmed by reading the
    // herdr v0.7.5/v0.8.2 sources and by attaching to a real herdr server).
    // Before the fix,
    // `open_round_trip` passed `params.pane` ("w1:p2") straight through,
    // which a real server rejects with `attach_rejected`; these fake
    // servers reproduce that exact real-server behavior (mirroring the
    // observed `"terminal attach failed: terminal <id> not found"` reason
    // text) so a regression here fails loudly instead of silently passing
    // against the previously-lenient fake sockets.
    //
    // `--window` is deliberately empty in both tests below: this keeps each
    // test to exactly one `pane.get` round trip (`record_original_position`
    // only -- `restore_position`'s `!moved && o0 != 0` branch then returns
    // `Approximate` without any further API call, since `o0` is set to a
    // non-zero 5 below), regardless of whether AttachTerminal is accepted
    // or rejected, so the fake API server thread never blocks forever
    // waiting for a second request that a rejected run would never send.
    // An empty `--window` list does *not* skip the attach handshake itself
    // (`open_round_trip` runs unconditionally, before the window loop) --
    // `attach_reached` below asserts that directly, so a future change that
    // accidentally short-circuits attach for an empty window list cannot
    // slip past this test as a false GREEN.

    #[test]
    fn run_scrollback_links_protocol17_attach_terminal_uses_resolved_terminal_id_not_pane_notation()
    {
        // o0 must be 0 (not the test's original 5): the 17/20 guard
        // now gates attaching at all on
        // `o0 == 0 && max_offset_from_bottom > 0` -- this test's purpose
        // (terminal_id resolution during attach) is
        // independent of the o0 value, so using 0 keeps the regression
        // coverage while still reaching the attach handshake this test
        // asserts on.
        let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
        let api_path = json_socket_path("run17-termid-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses = [
            pane_info_response(0),
            pane_process_info_response(real_shell.id()),
        ];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        let client_path = json_socket_path("run17-termid-client");
        let client_listener = UnixListener::bind(&client_path).unwrap();
        let client_thread = std::thread::spawn(move || {
            let mut attach = accept_with_deadline(&client_listener);
            let hello: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(hello, ClientMessage17::Hello { .. }),
                "expected Hello, got {:?}",
                hello
            );
            write_frame(
                &mut attach,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();

            let attach_terminal: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            let terminal_id = match attach_terminal {
                ClientMessage17::AttachTerminal { terminal_id, .. } => terminal_id,
                other => panic!("expected AttachTerminal, got {:?}", other),
            };
            // Explicit proof the attach handshake
            // was actually reached (not just inferred from the overall
            // Result), so an accidental short-circuit for an empty
            // `--window` list cannot pass this test as a false GREEN.
            let attach_reached = true;
            let resize: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(resize, ClientMessage17::Resize { .. }),
                "expected Resize, got {:?}",
                resize
            );

            // Mirrors the real herdr server: exact match against the
            // resolved terminal_id ("term-abc", `pane_info_response`'s
            // fixture value) only -- pane notation ("w1:p2", `params.pane`
            // below) is never resolved server-side.
            if terminal_id == "term-abc" {
                write_frame(
                    &mut attach,
                    &ServerMessage17::Terminal(TerminalFrame {
                        seq: 1,
                        width: 80,
                        height: 24,
                        full: true,
                        bytes: vec![],
                    }),
                )
                .unwrap();
                let detach: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
                assert!(
                    matches!(detach, ClientMessage17::Detach),
                    "expected Detach, got {:?}",
                    detach
                );
            } else {
                write_frame(
                    &mut attach,
                    &ServerMessage17::ServerShutdown {
                        reason: Some(format!(
                            "terminal attach failed: terminal {terminal_id} not found"
                        )),
                    },
                )
                .unwrap();
            }
            (terminal_id, attach_reached)
        });

        let lock_dir = fresh_lock_dir("run17-termid");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: client_path.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 17,
            cols: 80,
            windows: vec![],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let result = run_scrollback_links(&params);
        let (sent_terminal_id, attach_reached) = client_thread.join().unwrap();
        assert!(
            attach_reached,
            "open_round_trip must attach even when --window is empty"
        );
        // Checked before the terminal_id equality below so a regression's
        // raw test output shows the *classified* `RunError` (e.g.
        // `AttachRejected("terminal attach failed: terminal w1:p2 not
        // found")`, matching the real server's exact wording) together with
        // what was actually sent, not just a bare string mismatch.
        assert!(
            result.is_ok(),
            "expected success once AttachTerminal carries the resolved terminal_id, \
             got {:?} (sent_terminal_id was {:?}, expected \"term-abc\")",
            result,
            sent_terminal_id
        );
        assert_eq!(
            sent_terminal_id, "term-abc",
            "AttachTerminal.terminal_id must be the resolved terminal_id from pane.get \
             (\"term-abc\"), not the raw --pane notation (\"w1:p2\")"
        );

        api_thread.join().unwrap();
        let _ = real_shell.kill();
        let _ = real_shell.wait();
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&client_path);
    }

    #[test]
    fn run_scrollback_links_protocol20_attach_terminal_uses_resolved_terminal_id_not_pane_notation()
    {
        // See the matching comment in the protocol17 version of this test:
        // o0 must be 0 to satisfy the 17/20 attach guard.
        let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
        let api_path = json_socket_path("run20-termid-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses = [
            pane_info_response(0),
            pane_process_info_response(real_shell.id()),
        ];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        let client_path = json_socket_path("run20-termid-client");
        let client_listener = UnixListener::bind(&client_path).unwrap();
        let client_thread = std::thread::spawn(move || {
            let mut attach = accept_with_deadline(&client_listener);
            let hello: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(hello, ClientMessage20::Hello { .. }),
                "expected Hello, got {:?}",
                hello
            );
            write_frame(
                &mut attach,
                &ServerMessage20::Welcome {
                    version: 20,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();

            let attach_terminal: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            let terminal_id = match attach_terminal {
                ClientMessage20::AttachTerminal { terminal_id, .. } => terminal_id,
                other => panic!("expected AttachTerminal, got {:?}", other),
            };
            let attach_reached = true;
            let resize: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(resize, ClientMessage20::Resize { .. }),
                "expected Resize, got {:?}",
                resize
            );

            if terminal_id == "term-abc" {
                write_frame(
                    &mut attach,
                    &ServerMessage20::Terminal(TerminalFrame {
                        seq: 1,
                        width: 80,
                        height: 24,
                        full: true,
                        bytes: vec![],
                    }),
                )
                .unwrap();
                let detach: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
                assert!(
                    matches!(detach, ClientMessage20::Detach),
                    "expected Detach, got {:?}",
                    detach
                );
            } else {
                write_frame(
                    &mut attach,
                    &ServerMessage20::ServerShutdown {
                        reason: Some(format!(
                            "terminal attach failed: terminal {terminal_id} not found"
                        )),
                    },
                )
                .unwrap();
            }
            (terminal_id, attach_reached)
        });

        let lock_dir = fresh_lock_dir("run20-termid");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: client_path.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 20,
            cols: 80,
            windows: vec![],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let result = run_scrollback_links(&params);
        let (sent_terminal_id, attach_reached) = client_thread.join().unwrap();
        assert!(
            attach_reached,
            "open_round_trip must attach even when --window is empty"
        );
        // Checked before the terminal_id equality below so a regression's
        // raw test output shows the *classified* `RunError` (e.g.
        // `AttachRejected("terminal attach failed: terminal w1:p2 not
        // found")`, matching the real server's exact wording) together with
        // what was actually sent, not just a bare string mismatch.
        assert!(
            result.is_ok(),
            "expected success once AttachTerminal carries the resolved terminal_id, \
             got {:?} (sent_terminal_id was {:?}, expected \"term-abc\")",
            result,
            sent_terminal_id
        );
        assert_eq!(
            sent_terminal_id, "term-abc",
            "AttachTerminal.terminal_id must be the resolved terminal_id from pane.get \
             (\"term-abc\"), not the raw --pane notation (\"w1:p2\")"
        );

        api_thread.join().unwrap();
        let _ = real_shell.kill();
        let _ = real_shell.wait();
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&client_path);
    }

    // -- Finally-equivalent restore across failure paths --

    #[test]
    fn run_scrollback_links_window1_move_failure_still_restores_before_returning_err() {
        // window1's `pane.scroll` fails (no `scroll` field in the response,
        // classified `UnsupportedScroll`) before any window is
        // ever observed. Restore must still run (finally-equivalent)
        // even though nothing was ever confirmed to have moved -- and since
        // nothing actually moved, restore must land on `Exact` via its own
        // fresh `pane.get` read, not by (incorrectly) skipping straight to
        // "nothing to do". `observe_window` must never be reached: the
        // `socket` path below has no listener bound at all, so any attempt
        // to connect to it would itself surface as `RunError::Connect`.
        let api_path = json_socket_path("run22-move-fail-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses = [
            pane_info_response(0), // 1. record_original_position: o0=0
            pane_info_response(0), // 2. resolve_size_fail_open's pane.process_info: wrong
            //    `type` tag -> falls back to params.cols/viewport_rows
            pane_info_response_without_scroll(), // 3. window1 move: pane.scroll -> no `scroll` field
            pane_info_response(0), // 4. restore: read o1 -> 0 == o0 -> Exact, no further call
        ];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        let observe_socket = json_socket_path("run22-move-fail-observe-unbound");
        let lock_dir = fresh_lock_dir("run22-move-fail");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: observe_socket.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 22,
            cols: 80,
            windows: vec![10, 20],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let err = run_scrollback_links(&params).expect_err("window1 move must fail");
        assert!(
            matches!(err, RunError::UnsupportedScroll),
            "expected UnsupportedScroll, got {err:?}"
        );

        // All 4 API responses were consumed (o0 read, the fail-open
        // pane.process_info, the failing move, and the restore's own o1
        // read) -- proving restore ran to completion after the loop's
        // early break, not skipped.
        let sent = api_thread.join().unwrap();
        assert_eq!(sent.len(), 4);
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&observe_socket);
    }

    #[test]
    fn run_scrollback_links_window2_observe_failure_still_restores_from_the_moved_position() {
        // window1's move+observe succeed (position moves to 10, offset
        // tracked); window2's move succeeds (position moves to 20) but its
        // observe connect fails (each window uses its own fresh connection
        // -- no listener is available for the second connection).
        // Restore (finally-equivalent) must still run using the real
        // moved position (20), not the original (0), and must actually
        // attempt a bottom restore rather than treating this as "nothing
        // moved".
        let api_path = json_socket_path("run22-observe-fail-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses = [
            pane_info_response(0), // 1. record_original_position: o0=0
            pane_info_response(0), // 2. resolve_size_fail_open's pane.process_info: wrong `type`
            //    tag -> falls back to params.cols/viewport_rows
            pane_info_response(10), // 3. window1 move: pane.scroll -> 10
            pane_info_response(10), // 4. window1 move: confirm poll
            pane_info_response(20), // 5. window2 move: pane.scroll -> 20
            pane_info_response(20), // 6. window2 move: confirm poll
            pane_info_response(20), // 7. restore: read o1 -> 20 (t=20, o0=0 -> not equal -> bottom restore)
            pane_info_response(0),  // 8. restore: pane.scroll(0) -> 0
        ];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });

        // Accepts exactly one connection (window1's observe), then the
        // listener is dropped immediately -- window2's connect then fails
        // with `RunError::Connect` (ECONNREFUSED against the orphaned
        // socket file), simulating an observation failure mid-loop.
        //
        // Race (flaky under host
        // load): the listener used to be dropped only implicitly, at the
        // end of this closure -- i.e. *after* the full window1 Hello/
        // Welcome/Observe/Resize/Terminal exchange below. Window2's
        // connect() happens on the main thread as soon as it reads back
        // window1's Terminal frame, which races this thread's own
        // (possibly descheduled, under load) return from that last
        // `write_frame` call back to the implicit listener drop. If
        // window2's connect() lands first, it can be queued into the
        // kernel's listen backlog while the socket is still nominally
        // open, succeeding instead of failing with ECONNREFUSED, and the
        // run then times out waiting for a reply instead of returning
        // `RunError::Connect` -- an intermittent failure with no code
        // defect, just a wider-than-necessary window for the race.
        // Dropping the listener right after `accept()` (before doing any
        // of the window1 IO) closes that window entirely: by the time
        // window2 is attempted, window1's full synchronous exchange has
        // already completed (the main thread's read returned), so the
        // listener has unconditionally been closed long before.
        let client_path = json_socket_path("run22-observe-fail-client");
        let client_listener = UnixListener::bind(&client_path).unwrap();
        let observe_thread = std::thread::spawn(move || {
            let mut stream = accept_with_deadline(&client_listener);
            drop(client_listener);
            let _hello: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut stream,
                &ServerMessage22Known::Welcome {
                    version: 22,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let _observe: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
            let _resize: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
            let bytes =
                b"\x1b[1;1H\x1b]8;;https://example.com/w0\x1b\\link0\x1b]8;;\x1b\\".to_vec();
            write_frame(
                &mut stream,
                &ServerMessage22Known::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes,
                }),
            )
            .unwrap();
            // (listener was already dropped right after accept(), above)
        });

        let lock_dir = fresh_lock_dir("run22-observe-fail");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: client_path.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 22,
            cols: 80,
            windows: vec![10, 20],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let err = run_scrollback_links(&params).expect_err("window2 observe must fail");
        assert!(
            matches!(err, RunError::Connect),
            "expected Connect, got {err:?}"
        );

        // All 8 API responses were consumed, including the fail-open
        // pane.process_info, the restore's o1 read, and the
        // bottom-restore `pane.scroll(0)` call -- proving restore ran
        // using the real moved-to position (20), not skipped and not
        // restored from the stale original (0).
        let sent = api_thread.join().unwrap();
        assert_eq!(sent.len(), 8);
        assert!(
            sent[7].contains("\"offset_from_bottom\":0"),
            "restore must target the bottom (o0=0)"
        );
        observe_thread.join().unwrap();
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&client_path);
    }

    // -- A window whose frame the tracker rejects (or that is not a
    // full redraw) becomes an empty `truncated` window; the other windows
    // and the restore carry on. Only when every window is rejected does
    // the run fail with `render_rejected`. --

    /// Protocol 22, two windows (offsets 10 and 20): serves `frames[i]`
    /// (`bytes`, `full`) as window i's `TerminalAnsi` frame, with the same
    /// 8-call api sequence as the happy-path test. Returns the run result
    /// and the api requests actually sent.
    fn run22_two_windows_with_frames(
        tag: &str,
        frames: [(&'static [u8], bool); 2],
    ) -> (Result<String, RunError>, Vec<String>) {
        let api_path = json_socket_path(&format!("run22-f3-{tag}-api"));
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let responses: Vec<String> = vec![
            pane_info_response(0),
            pane_info_response(0),
            pane_info_response(10),
            pane_info_response(10),
            pane_info_response(20),
            pane_info_response(20),
            pane_info_response(20),
            pane_info_response(0),
        ];
        let api_thread = std::thread::spawn(move || {
            let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
            serve_sequence(api_listener, &response_refs)
        });
        let client_path = json_socket_path(&format!("run22-f3-{tag}-client"));
        let client_listener = UnixListener::bind(&client_path).unwrap();
        let observe_thread = std::thread::spawn(move || {
            for (bytes, full) in frames {
                let mut stream = accept_with_deadline(&client_listener);
                let _hello: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
                write_frame(
                    &mut stream,
                    &ServerMessage22Known::Welcome {
                        version: 22,
                        encoding: RenderEncoding::TerminalAnsi,
                        error: None,
                    },
                )
                .unwrap();
                let _observe: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
                let _resize: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
                write_frame(
                    &mut stream,
                    &ServerMessage22Known::Terminal(TerminalFrame {
                        seq: 1,
                        width: 80,
                        height: 24,
                        full,
                        bytes: bytes.to_vec(),
                    }),
                )
                .unwrap();
                stream
                    .set_read_timeout(Some(std::time::Duration::from_secs(2)))
                    .unwrap();
                let _: Result<ClientMessage22, String> = read_frame(&mut stream, MAX_FRAME_SIZE);
            }
        });
        let lock_dir = fresh_lock_dir(&format!("run22-f3-{tag}"));
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: client_path.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 22,
            cols: 80,
            windows: vec![10, 20],
            timeout_ms: 5000,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };
        let result = run_scrollback_links(&params);
        let sent = api_thread.join().unwrap();
        observe_thread.join().unwrap();
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&client_path);
        (result, sent)
    }

    const F3_GOOD: &[u8] = b"\x1b[1;1H\x1b]8;;https://example.com/ok\x1b\\link\x1b]8;;\x1b\\";
    // An unknown CSI final byte: `TrackError::UnknownSequence` (not
    // localizable to one link).
    const F3_BAD: &[u8] = b"\x1b[1;1H\x1b[5x";

    #[test]
    fn run_scrollback_links_one_tracker_rejected_window_becomes_truncated_others_and_restore_continue(
    ) {
        let (result, sent) =
            run22_two_windows_with_frames("trk", [(F3_BAD, true), (F3_GOOD, true)]);
        let json = result.expect("a single rejected window must not fail the run");
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed["restore"], "exact");
        let w = parsed["windows"].as_array().unwrap();
        assert_eq!(w.len(), 2);
        assert_eq!(w[0]["requestedOffset"], 10);
        assert_eq!(w[0]["truncated"], true);
        assert_eq!(w[0]["links"].as_array().unwrap().len(), 0);
        assert_eq!(w[0]["rowHashes"].as_array().unwrap().len(), 0);
        // Frame size of a tracker-rejected window is the real frame's.
        assert_eq!(w[0]["frameWidth"], 80);
        assert_eq!(w[0]["frameHeight"], 24);
        assert_eq!(w[1]["truncated"], false);
        assert_eq!(w[1]["links"][0]["url"], "https://example.com/ok");
        // The restore (read o1 + scroll to bottom) was still sent.
        assert_eq!(sent.len(), 8);
        assert!(sent[7].contains("\"offset_from_bottom\":0"));
    }

    #[test]
    fn run_scrollback_links_one_non_full_window_becomes_truncated_with_requested_size() {
        let (result, sent) =
            run22_two_windows_with_frames("nf", [(F3_GOOD, true), (F3_GOOD, false)]);
        let json = result.expect("a non-full window must not fail the run");
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        let w = parsed["windows"].as_array().unwrap();
        assert_eq!(w.len(), 2);
        assert_eq!(w[0]["truncated"], false);
        assert_eq!(w[0]["links"][0]["url"], "https://example.com/ok");
        assert_eq!(w[1]["requestedOffset"], 20);
        assert_eq!(w[1]["truncated"], true);
        assert_eq!(w[1]["links"].as_array().unwrap().len(), 0);
        assert_eq!(w[1]["rowHashes"].as_array().unwrap().len(), 0);
        // No frame is available: the size used for the observation
        // (params.cols = 80, pane.get viewport_rows = 24) is reported.
        assert_eq!(w[1]["frameWidth"], 80);
        assert_eq!(w[1]["frameHeight"], 24);
        assert_eq!(sent.len(), 8);
        assert!(sent[7].contains("\"offset_from_bottom\":0"));
    }

    #[test]
    fn run_scrollback_links_all_windows_rejected_fails_with_render_rejected_after_restore() {
        let (result, sent) =
            run22_two_windows_with_frames("all", [(F3_BAD, true), (F3_GOOD, false)]);
        let err = result.expect_err("every window rejected must fail the run");
        assert!(matches!(err, RunError::RenderRejected(_)), "got {err:?}");
        assert_eq!(sent.len(), 8, "restore must still run");
        assert!(sent[7].contains("\"offset_from_bottom\":0"));
    }

    // -- "send succeeded, but the
    // confirmation/response wait then timed out" must still restore, for
    // both protocol 22 (pane.scroll's own response wait) and 17/20
    // (AttachScroll's follow-up poll). --

    #[test]
    fn run_scrollback_links_protocol22_move_response_wait_timeout_still_restores() {
        // window1's `pane.scroll` request reaches the server (connect+write
        // succeed -- `attempted = true`), but the server never answers, so
        // the response wait itself times out (mirrors
        // `tests/api_client.rs`'s `no_response_before_deadline_is_timeout`).
        let api_path = json_socket_path("run22-move-timeout-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let resp0 = pane_info_response(0);
        let resp_procinfo = pane_info_response(0); // wrong `type` tag -> resolve_size_fail_open fallback
        let resp0b = pane_info_response(0);
        let api_thread = std::thread::spawn(move || {
            let entries = [
                Some(resp0.as_str()),         // 1. record_original_position: o0=0
                Some(resp_procinfo.as_str()), // 2. resolve_size_fail_open's pane.process_info
                None,                         // 3. window1 move: pane.scroll sent, never answered
                //    (last_move_confirmed=false)
                Some(resp0b.as_str()), // 4. restore: o0=0 && !last_move_confirmed -> sends the
                                       //    bottom restore unconditionally, WITHOUT reading o1
                                       //    first -> pane.scroll(0) -> 0
            ];
            serve_sequence_with_stall(api_listener, &entries)
        });

        let observe_socket = json_socket_path("run22-move-timeout-observe-unbound");
        let lock_dir = fresh_lock_dir("run22-move-timeout");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: observe_socket.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 22,
            cols: 80,
            windows: vec![10],
            timeout_ms: 200,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let err =
            run_scrollback_links(&params).expect_err("window1 move response wait must time out");
        assert!(
            matches!(err, RunError::Timeout),
            "expected Timeout, got {err:?}"
        );

        // All 4 entries were consumed -- including the fail-open
        // pane.process_info and the unconditional bottom-restore call --
        // proving restore ran to completion despite the timeout, not
        // skipped because `t` stayed stale at o0.
        let sent = api_thread.join().unwrap();
        assert_eq!(sent.len(), 4);
        assert!(sent[3].contains("\"method\":\"pane.scroll\""));
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&observe_socket);
    }

    #[test]
    fn run_scrollback_links_protocol17_move_confirm_poll_timeout_still_restores() {
        // window1's `AttachScroll` send succeeds (over the attach
        // connection, which never itself responds to `AttachScroll` by
        // design) but the follow-up confirmation `pane.get` poll (over the
        // separate api_socket) then times out. Restore must still run --
        // and, since the caller's `t` is now kept at the *attempted* target
        // (10) rather than staying stale at o0, the
        // approximate math would use `t=10` correctly if o0 were nonzero;
        // here o0=0 so it goes through the unconditional bottom-restore path.
        let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
        let api_path = json_socket_path("run17-move-timeout-api");
        let api_listener = UnixListener::bind(&api_path).unwrap();
        let resp0 = pane_info_response(0);
        let resp_procinfo = pane_process_info_response(real_shell.id());
        let resp0b = pane_info_response(0);
        let api_thread = std::thread::spawn(move || {
            let entries = [
                Some(resp0.as_str()),         // 1. record_original_position: o0=0
                Some(resp_procinfo.as_str()), // 2. resolve_size_fail_closed's pane.process_info
                None,                         // 3. window1 move: confirm poll, never answered
                //    (last_move_confirmed=false)
                Some(resp0b.as_str()), // 4. restore: o0=0 && !last_move_confirmed -> sends the
                                       //    bottom restore unconditionally, no o1 read first ->
                                       //    confirm poll -> 0
            ];
            serve_sequence_with_stall(api_listener, &entries)
        });

        let client_path = json_socket_path("run17-move-timeout-client");
        let client_listener = UnixListener::bind(&client_path).unwrap();
        let client_thread = std::thread::spawn(move || {
            let mut attach = accept_with_deadline(&client_listener);
            let _hello: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut attach,
                &ServerMessage17::Welcome {
                    version: 17,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let _attach_terminal: ClientMessage17 =
                read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            let _resize: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut attach,
                &ServerMessage17::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();

            // window1 move: 0 -> 10 -> Up, 10 lines. Sent successfully; its
            // poll (over api_socket) is what times out, not this send.
            let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match scroll_msg {
                ClientMessage17::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 0);
                    assert_eq!(lines, 10);
                }
                other => panic!("expected AttachScroll, got {:?}", other),
            }

            // restore: o0=0 -> bottom -> AttachScroll{Down, 65535}.
            let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            match scroll_msg {
                ClientMessage17::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 1, "1 = Down towards the bottom");
                    assert_eq!(lines, 65535);
                }
                other => panic!("expected AttachScroll, got {:?}", other),
            }
        });

        let lock_dir = fresh_lock_dir("run17-move-timeout");
        let params = ScrollbackParams {
            api_socket: api_path.to_str().unwrap().to_owned(),
            socket: client_path.to_str().unwrap().to_owned(),
            pane: "w1:p2".to_owned(),
            protocol: 17,
            cols: 80,
            windows: vec![10],
            timeout_ms: 200,
            restore_budget_ms: 5000,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
        };

        let err = run_scrollback_links(&params).expect_err("window1 confirm poll must time out");
        assert!(
            matches!(err, RunError::Timeout),
            "expected Timeout, got {err:?}"
        );

        let sent = api_thread.join().unwrap();
        assert_eq!(sent.len(), 4);
        client_thread.join().unwrap();
        let _ = real_shell.kill();
        let _ = real_shell.wait();
        let _ = std::fs::remove_file(&api_path);
        let _ = std::fs::remove_file(&client_path);
    }
}
