//! `scrollback-links` subcommand: orchestration and output assembly.
//!
//! The submodules own the individual concerns: `args` (CLI parsing), `lock`
//! (the per-pane lock), and `position` (original position, round trip, move,
//! and restore). This file keeps the per-window observation, the JSON output
//! assembly with its byte budget, and `run_scrollback_links`, whose window
//! loop stays in one function so that every early return still passes
//! through the position restore.

use crate::ansi_runner::observe_terminal_ansi;
use crate::error::RunError;
use crate::hyperlinks::{aggregate_frame, sanitize_links, AggregatedLink};
use serde::Serialize;
use std::collections::HashSet;
use std::os::unix::net::UnixStream;

mod args;
mod lock;
mod position;

pub use args::{parse_args, ScrollbackParams};
pub use lock::{acquire_lock, ScrollbackLock};
pub use position::{
    close_round_trip, move_to_offset, open_round_trip, record_original_position, OriginalPosition,
    RestoreOutcome, RoundTripHandle,
};
use position::{resolve_size_fail_closed, resolve_size_fail_open, restore_position, RestorePlan};

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
mod render_tests {
    use super::*;

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
}

#[cfg(test)]
mod tests;
