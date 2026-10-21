//! Scroll position handling for `scrollback-links`: recording the pane's
//! original position, resolving the real pty size, the attach round trip,
//! moving to a target window and confirming it, and restoring the original
//! position afterwards.

use super::ScrollbackParams;
use crate::error::RunError;

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
pub(super) fn resolve_size_fail_closed(
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
pub(super) fn resolve_size_fail_open(
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
    pub(super) fn as_json_str(self) -> &'static str {
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
pub(super) struct RestorePlan {
    pub(super) o0: u64,
    pub(super) t: u64,
    pub(super) moved: bool,
    pub(super) last_move_confirmed: bool,
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
pub(super) fn restore_position(
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::attach::ScrollDirection;

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
}
