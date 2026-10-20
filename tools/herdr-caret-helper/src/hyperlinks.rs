//! Aggregation layer between the low-level grammar tracker (`tracker.rs`)
//! and the `hyperlinks`/`scrollback-links` CLI output contract:
//! same-URL span aggregation into the contract's
//! per-URL `ranges` list, plus row fingerprints for every non-empty row
//! (`rowHashes`). Below `aggregate_links`: URL sanitization
//! (herdr's `sanitized_hyperlink_uri` equivalent + a 2048-byte cap),
//! output-size truncation (`--max-output-bytes` / `truncated`), the
//! `hyperlinks` subcommand's end-to-end runner (`run_hyperlinks`), and JSON
//! serialization matching the exact contract shape.

use crate::ansi_runner::observe_terminal_ansi;
use crate::is_hyperlink_protocol_supported;
use crate::runner::RunError;
use crate::tracker::{row_fingerprint, track_frame, RawLinkSpan, TrackError};
use crate::winsize::Winsize;
use serde::Serialize;
use std::collections::{HashMap, HashSet};
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

/// One URL's aggregated ranges, in the external JSON contract's shape
/// `{"url": ..., "ranges": [[row, startCol, endCol], ...]}`.
/// `ranges` preserves emission order (first span for this URL first);
/// row-crossing links from `tracker.rs` already arrive as separate
/// per-row `RawLinkSpan`s, so no further splitting is needed here — only
/// grouping by URL (one entry per URL).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AggregatedLink {
    pub url: String,
    /// `(row, start_col, end_col)`, `end_col` inclusive — same shape as
    /// `RawLinkSpan`, just grouped by URL instead of emission order.
    pub ranges: Vec<(u16, u16, u16)>,
}

/// One frame's fully aggregated link data: `links` for the JSON contract's
/// `links` field, `row_hashes` for its `rowHashes` field.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FrameLinks {
    pub links: Vec<AggregatedLink>,
    /// `(row, fingerprint)` for every non-empty row, in
    /// ascending row order. A row whose display text is empty — or becomes
    /// empty after stripping trailing U+0020 — is omitted entirely (see
    /// `tracker::row_fingerprint`).
    pub row_hashes: Vec<(u16, String)>,
}

/// Runs the grammar tracker on one full-redraw frame and aggregates its
/// output into the external JSON contract's shape. `Err` is always a
/// `TrackError` from `tracker::track_frame` — callers map it to
/// `RunError::RenderRejected` (see `ansi_runner.rs`'s existing `full`
/// check for the sibling failure mode this joins).
pub fn aggregate_frame(bytes: &[u8], width: u16, height: u16) -> Result<FrameLinks, TrackError> {
    let tracked = track_frame(bytes, width, height)?;
    let links = aggregate_links(tracked.links);
    let row_hashes = tracked
        .rows
        .iter()
        .enumerate()
        .filter_map(|(row, text)| row_fingerprint(text).map(|fp| (row as u16, fp)))
        .collect();
    Ok(FrameLinks { links, row_hashes })
}

/// Groups raw, per-span link data by URL, preserving first-appearance
/// order for both the outer `Vec<AggregatedLink>` and each URL's own
/// `ranges` (deterministic — the aggregation contract has no other
/// specified ordering, and stable output makes this testable and diffable
/// in the JSON contract).
fn aggregate_links(spans: Vec<RawLinkSpan>) -> Vec<AggregatedLink> {
    let mut order: Vec<String> = Vec::new();
    let mut by_url: HashMap<String, Vec<(u16, u16, u16)>> = HashMap::new();
    for span in spans {
        by_url
            .entry(span.url.clone())
            .or_insert_with(|| {
                order.push(span.url.clone());
                Vec::new()
            })
            .push((span.row, span.start_col, span.end_col));
    }
    order
        .into_iter()
        .map(|url| {
            let ranges = by_url.remove(&url).unwrap_or_default();
            AggregatedLink { url, ranges }
        })
        .collect()
}

// --- Sanitization, output-size truncation, and the `hyperlinks`
// subcommand's end-to-end runner. ---

/// `--max-output-bytes` default (the executor's own cap is 64000
/// `herdr_caret_helper_executor.dart:22`; this must stay smaller).
pub const DEFAULT_MAX_OUTPUT_BYTES: usize = 60_000;

/// Second-layer URL guard beyond herdr's own sanitization:
/// herdr already sanitizes URIs before encoding them (`sanitized_hyperlink_uri`,
/// confirmed byte-identical across all 3 supported versions by reading the
/// tagged source directly: v0.7.5:634, v0.8.2:682, v0.9.1
/// `src/protocol/render_ansi.rs:904`), but the wire-level protocol is not
/// itself version-frozen for hyperlink semantics, so
/// this crate re-applies the same character filter and adds an explicit
/// byte-length cap that has no herdr-side equivalent.
const MAX_SANITIZED_URI_BYTES: usize = 2048;

/// Mirrors herdr's `sanitized_hyperlink_uri` character filter verbatim,
/// including the explicit `!= '\x1b' && != '\x07'` checks even though
/// `char::is_control()` already covers both (ESC/BEL are both in the C0
/// control range) — kept for exact correspondence with the upstream
/// predicate rather than relying on that overlap. Returns `None` when the
/// result is empty after stripping, or when it exceeds
/// `MAX_SANITIZED_URI_BYTES` (the additional cap) — either way, the
/// caller must treat the link as invalid, not the whole frame (the tracker
/// likewise excludes just the one link whose OSC 8 URI holds a C0 control
/// byte, `Token::LinkOpenInvalid` in `tracker.rs`).
fn sanitize_hyperlink_uri(uri: &str) -> Option<String> {
    let sanitized: String = uri
        .chars()
        .filter(|ch| *ch != '\x1b' && *ch != '\x07' && !ch.is_control())
        .collect();
    if sanitized.is_empty() || sanitized.len() > MAX_SANITIZED_URI_BYTES {
        None
    } else {
        Some(sanitized)
    }
}

/// Applies `sanitize_hyperlink_uri` to every aggregated link, dropping (not
/// merely blanking) any link whose URL sanitizes to `None` — its ranges are
/// not reassigned to any other entry, they simply disappear from the output,
/// matching the contract's rule to invalidate that link.
///
/// `pub` (not just `pub(crate)`) because `scrollback-links` reuses
/// this exact same second-layer URL guard on top of its own aggregation —
/// same rationale as `aggregate_frame`/`AggregatedLink` already being `pub`.
pub fn sanitize_links(links: Vec<AggregatedLink>) -> Vec<AggregatedLink> {
    links
        .into_iter()
        .filter_map(|link| {
            let url = sanitize_hyperlink_uri(&link.url)?;
            Some(AggregatedLink {
                url,
                ranges: link.ranges,
            })
        })
        .collect()
}

/// `hyperlinks` output contract: one JSON line, `ranges` and
/// `rowHashes` shapes match `AggregatedLink`/`FrameLinks` exactly (tuples
/// serialize as JSON arrays), so no separate wire-shape structs are needed
/// for `links`/`rowHashes` themselves.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct HyperlinksOutput {
    pane_id: String,
    protocol_version: u32,
    frame_width: u16,
    frame_height: u16,
    truncated: bool,
    links: Vec<AggregatedLink>,
    row_hashes: Vec<(u16, String)>,
}

impl Serialize for AggregatedLink {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct LinkOut<'a> {
            url: &'a str,
            ranges: &'a [(u16, u16, u16)],
        }
        LinkOut {
            url: &self.url,
            ranges: &self.ranges,
        }
        .serialize(serializer)
    }
}

/// Frame-level fields that stay constant across every truncation candidate
/// `render_output`/`filtered_output` build while searching for a row set
/// that fits `--max-output-bytes` — bundled into one struct instead of
/// passed individually so neither function trips clippy's
/// `too_many_arguments` (both would otherwise sit at 7-8 plain parameters).
struct FrameMeta<'a> {
    pane_id: &'a str,
    protocol_version: u32,
    width: u16,
    height: u16,
}

/// Builds the final `hyperlinks` JSON line, applying `--max-output-bytes`
/// truncation when needed. Never panics, never returns invalid/partial JSON
/// (a truncated JSON line is never emitted).
/// `links` must already be sanitized (`sanitize_links`) by the caller.
fn render_output(
    meta: &FrameMeta,
    links: &[AggregatedLink],
    row_hashes: &[(u16, String)],
    max_output_bytes: usize,
) -> String {
    let full = filtered_output(meta, links, row_hashes, None, false);
    if full.len() <= max_output_bytes {
        return full;
    }

    // Row-unit, bottom-first packing: rows are added from
    // the bottom of the frame upward, one at a time, stopping at the first
    // row that would push the output over budget — never a knapsack-style
    // best-fit search, and never a partial row. Cutting mid-row and prioritizing the top rows are both
    // rejected (prioritizing the top rows would
    // instead drop the newest/bottom output).
    let mut rows: Vec<u16> = row_hashes
        .iter()
        .map(|(row, _)| *row)
        .chain(
            links
                .iter()
                .flat_map(|l| l.ranges.iter().map(|(row, _, _)| *row)),
        )
        .collect();
    rows.sort_unstable();
    rows.dedup();
    rows.reverse();

    let mut kept: HashSet<u16> = HashSet::new();
    let mut best = filtered_output(meta, links, row_hashes, Some(&kept), true);
    for row in rows {
        let mut candidate_kept = kept.clone();
        candidate_kept.insert(row);
        let candidate = filtered_output(meta, links, row_hashes, Some(&candidate_kept), true);
        if candidate.len() <= max_output_bytes {
            kept = candidate_kept;
            best = candidate;
        } else {
            break;
        }
    }
    best
}

/// Renders one candidate output, restricted to `kept` rows when given (`None`
/// means "every row", used only for the initial no-truncation-needed check).
/// A link entry whose every range falls outside `kept` is dropped entirely
/// rather than emitted with an empty `ranges` array.
fn filtered_output(
    meta: &FrameMeta,
    links: &[AggregatedLink],
    row_hashes: &[(u16, String)],
    kept: Option<&HashSet<u16>>,
    truncated: bool,
) -> String {
    let filtered_row_hashes: Vec<(u16, String)> = match kept {
        None => row_hashes.to_vec(),
        Some(k) => row_hashes
            .iter()
            .filter(|(row, _)| k.contains(row))
            .cloned()
            .collect(),
    };
    let filtered_links: Vec<AggregatedLink> = links
        .iter()
        .filter_map(|link| {
            let ranges: Vec<(u16, u16, u16)> = match kept {
                None => link.ranges.clone(),
                Some(k) => link
                    .ranges
                    .iter()
                    .filter(|(row, _, _)| k.contains(row))
                    .cloned()
                    .collect(),
            };
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
    let out = HyperlinksOutput {
        pane_id: meta.pane_id.to_owned(),
        protocol_version: meta.protocol_version,
        frame_width: meta.width,
        frame_height: meta.height,
        truncated,
        links: filtered_links,
        row_hashes: filtered_row_hashes,
    };
    serde_json::to_string(&out).unwrap_or_else(|_| r#"{"error":"internal"}"#.to_owned())
}

/// CLI parameters for the `hyperlinks` subcommand.
#[derive(Debug, Clone)]
pub struct HyperlinksParams {
    pub socket: String,
    /// Optional, `hyperlinks`-only.
    /// `None` when `--api-socket` is omitted — `resolve_dimensions` then
    /// falls back to `cols`/`rows` unchanged, so this field's absence
    /// reproduces today's behaviour byte-for-byte.
    pub api_socket: Option<String>,
    pub pane: String,
    pub protocol: u8,
    pub cols: u16,
    pub rows: u16,
    pub timeout_ms: u64,
    pub max_output_bytes: usize,
}

/// Resolves the real pty dimensions to prefer for this observation
/// fail-open: every failure reason collapses into
/// the same `(fallback_cols, fallback_rows, 0, 0)` result, with no
/// distinction surfaced to the caller or to stderr (no new
/// stderr classification for this path, since a successful run never
/// writes to stderr today and this is not a failure of the overall
/// command).
///
/// Failure reasons, in the order checked: `api_socket` is `None` (flag
/// omitted); `pane.process_info` itself failed; `shell_pid` is absent
/// (process spawn never reported a pid, per `api_client`'s doc comment);
/// or `winsize::real_size` failed (process gone, no pty, zero dimension,
/// ...). Uses the same `deadline` the wire connection's own timeout is
/// bounded by, consistent with `scrollback.rs`'s existing pattern of
/// sharing one overall deadline across both the API socket and the wire
/// socket.
///
/// Returns `Winsize` (not a bare tuple) so the result threads directly
/// into `ansi_runner::observe_terminal_ansi`'s single bundled `size`
/// parameter (avoiding clippy's `too_many_arguments`).
fn resolve_dimensions(
    api_socket: Option<&str>,
    pane: &str,
    fallback_cols: u16,
    fallback_rows: u16,
    deadline: Instant,
) -> Winsize {
    let fallback = Winsize {
        cols: fallback_cols,
        rows: fallback_rows,
        cell_width_px: 0,
        cell_height_px: 0,
    };
    let Some(api_socket) = api_socket else {
        return fallback;
    };
    let Ok(info) = crate::api_client::pane_process_info(api_socket, pane, deadline) else {
        return fallback;
    };
    let Some(shell_pid) = info.shell_pid else {
        return fallback;
    };
    crate::winsize::real_size(shell_pid).unwrap_or(fallback)
}

/// Connects, observes one `TerminalAnsi` full-redraw frame, tracks it,
/// aggregates + sanitizes its links, and renders the final JSON line — the
/// `hyperlinks` subcommand's whole pipeline. Mirrors
/// `runner::run`'s connect/deadline arrangement exactly, but delegates the
/// protocol-version dispatch and the `TerminalFrame.full` check to
/// `ansi_runner::observe_terminal_ansi` (shared with caret-22 and
/// `scrollback-links`) instead of duplicating them here.
pub fn run_hyperlinks(params: &HyperlinksParams) -> Result<String, RunError> {
    if !is_hyperlink_protocol_supported(params.protocol) {
        return Err(RunError::Usage("unsupported protocol".to_owned()));
    }
    let stream = UnixStream::connect(&params.socket).map_err(|_| RunError::Connect)?;
    let base = Duration::from_millis(params.timeout_ms);
    stream
        .set_read_timeout(Some(base))
        .map_err(|_| RunError::Io)?;
    let deadline = Instant::now() + base;

    let size = resolve_dimensions(
        params.api_socket.as_deref(),
        &params.pane,
        params.cols,
        params.rows,
        deadline,
    );

    let frame = observe_terminal_ansi(stream, &params.pane, params.protocol, size, deadline)?;
    let aggregated = aggregate_frame(&frame.bytes, frame.width, frame.height)
        .map_err(|e| RunError::RenderRejected(format!("{e:?}")))?;
    let sanitized = sanitize_links(aggregated.links);
    let meta = FrameMeta {
        pane_id: &params.pane,
        protocol_version: params.protocol as u32,
        width: frame.width,
        height: frame.height,
    };
    Ok(render_output(
        &meta,
        &sanitized,
        &aggregated.row_hashes,
        params.max_output_bytes,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cup(row1: u16, col1: u16) -> String {
        format!("\x1b[{};{}H", row1, col1)
    }
    fn osc8_open(url: &str) -> String {
        format!("\x1b]8;;{}\x1b\\", url)
    }
    fn osc8_close() -> &'static str {
        "\x1b]8;;\x1b\\"
    }

    // -- resolve_dimensions: each fail-open fallback branch ----------------------

    fn far_deadline() -> Instant {
        Instant::now() + Duration::from_secs(10)
    }

    #[test]
    fn resolve_dimensions_falls_back_when_api_socket_is_none() {
        // The first branch: no `--api-socket` at all. No `pane.process_info`
        // call is attempted (nothing to connect to), so this is the one
        // branch exercisable without a live api_client peer.
        let got = resolve_dimensions(None, "w1:p1", 80, 24, far_deadline());
        assert_eq!(
            got,
            Winsize {
                cols: 80,
                rows: 24,
                cell_width_px: 0,
                cell_height_px: 0
            }
        );
    }

    #[test]
    fn resolve_dimensions_falls_back_when_pane_process_info_fails() {
        // Second branch: `--api-socket` given, but nothing is listening
        // there -- `pane_process_info` must return `Err`, and
        // `resolve_dimensions` must fall back exactly as it did with no
        // socket at all, not propagate the error.
        let got = resolve_dimensions(
            Some("/dev/null/herdr-winsize-resolve-dimensions-test.sock"),
            "w1:p1",
            80,
            24,
            far_deadline(),
        );
        assert_eq!(
            got,
            Winsize {
                cols: 80,
                rows: 24,
                cell_width_px: 0,
                cell_height_px: 0
            }
        );
    }

    // The remaining two branches (`pane.process_info` succeeds but
    // `shell_pid` is `None`; `shell_pid` is `Some` but `winsize::real_size`
    // fails) drive a real `pane.process_info` JSON-API peer via a one-shot
    // `UnixListener`, the same mock-socket style `tests/api_client.rs`
    // uses for `pane_get`/`pane_scroll`.

    /// A fresh socket path under the OS temp dir, unique per test run --
    /// mirrors `tests/api_client.rs::socket_path`.
    fn resolve_dimensions_socket_path(name: &str) -> std::path::PathBuf {
        let mut path = std::env::temp_dir();
        path.push(format!(
            "herdr-caret-helper-resolve-dimensions-test-{}-{}.sock",
            name,
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        path
    }

    /// Accepts exactly one connection, reads one request line, writes back
    /// `response` -- mirrors `tests/api_client.rs::serve_one`.
    fn serve_one_process_info(listener: std::os::unix::net::UnixListener, response: &str) {
        use std::io::{BufRead, BufReader, Write};
        let (stream, _) = listener.accept().expect("accept");
        let mut reader = BufReader::new(&stream);
        let mut line = String::new();
        reader.read_line(&mut line).expect("read request line");
        let mut writer = &stream;
        writer.write_all(response.as_bytes()).unwrap();
        writer.write_all(b"\n").unwrap();
        writer.flush().unwrap();
    }

    #[test]
    fn resolve_dimensions_falls_back_when_shell_pid_is_none() {
        // Third branch: `pane.process_info` succeeds, but herdr reports no
        // shell PID for this pane (e.g. the shell has already exited) --
        // `resolve_dimensions` must fall back without ever calling
        // `winsize::real_size`.
        let path = resolve_dimensions_socket_path("shell-pid-none");
        let listener = std::os::unix::net::UnixListener::bind(&path).unwrap();
        let response =
            r#"{"id":"1","result":{"type":"pane_process_info","process_info":{"shell_pid":null}}}"#;
        let t = std::thread::spawn(move || serve_one_process_info(listener, response));

        let got = resolve_dimensions(path.to_str(), "w1:p1", 80, 24, far_deadline());
        t.join().unwrap();
        assert_eq!(
            got,
            Winsize {
                cols: 80,
                rows: 24,
                cell_width_px: 0,
                cell_height_px: 0
            }
        );
    }

    #[test]
    fn resolve_dimensions_falls_back_when_winsize_real_size_fails() {
        // Fourth branch: `pane.process_info` succeeds and reports a
        // `shell_pid`, but `winsize::real_size` itself fails (here: the pid
        // does not correspond to any running process) -- fails exactly like
        // every other branch, collapsing into the same fallback.
        let path = resolve_dimensions_socket_path("winsize-fails");
        let listener = std::os::unix::net::UnixListener::bind(&path).unwrap();
        // PID 1 always exists but is never this test's own controlling tty's
        // shell, and a very large, almost-certainly-unused pid is used
        // instead to land reliably in `WinsizeError::ProcessNotRunning`
        // rather than depending on PID 1's own tty state.
        let response = r#"{"id":"1","result":{"type":"pane_process_info","process_info":{"shell_pid":2147483000}}}"#;
        let t = std::thread::spawn(move || serve_one_process_info(listener, response));

        let got = resolve_dimensions(path.to_str(), "w1:p1", 80, 24, far_deadline());
        t.join().unwrap();
        assert_eq!(
            got,
            Winsize {
                cols: 80,
                rows: 24,
                cell_width_px: 0,
                cell_height_px: 0
            }
        );
    }

    #[test]
    fn single_link_becomes_one_entry_with_one_range() {
        let bytes = format!(
            "{}{}ab{}",
            cup(1, 1),
            osc8_open("https://example.com/"),
            osc8_close()
        );
        let out = aggregate_frame(bytes.as_bytes(), 80, 24).expect("must parse");
        assert_eq!(
            out.links,
            vec![AggregatedLink {
                url: "https://example.com/".to_owned(),
                ranges: vec![(0, 0, 1)],
            }]
        );
    }

    #[test]
    fn same_url_reopened_on_a_later_row_merges_into_one_entry_two_ranges() {
        // Same URL, closed on row 0 then reopened (not merely continued —
        // an explicit new OSC8 open) on row 1: must still merge into one
        // `AggregatedLink` with two ranges (one entry per URL
        // -- this applies across non-contiguous
        // reappearances too, not only the single-continuous-span case
        // `tracker.rs` itself already handles).
        let bytes = format!(
            "{}{}a{}{}{}b{}",
            cup(1, 1),
            osc8_open("https://example.com/"),
            osc8_close(),
            cup(2, 1),
            osc8_open("https://example.com/"),
            osc8_close()
        );
        let out = aggregate_frame(bytes.as_bytes(), 80, 24).expect("must parse");
        assert_eq!(
            out.links,
            vec![AggregatedLink {
                url: "https://example.com/".to_owned(),
                ranges: vec![(0, 0, 0), (1, 0, 0)],
            }]
        );
    }

    #[test]
    fn two_different_urls_stay_as_separate_entries_in_first_seen_order() {
        let bytes = format!(
            "{}{}a{}b{}",
            cup(1, 1),
            osc8_open("https://b/"),
            osc8_open("https://a/"),
            osc8_close()
        );
        let out = aggregate_frame(bytes.as_bytes(), 80, 24).expect("must parse");
        assert_eq!(
            out.links,
            vec![
                AggregatedLink {
                    url: "https://b/".to_owned(),
                    ranges: vec![(0, 0, 0)]
                },
                AggregatedLink {
                    url: "https://a/".to_owned(),
                    ranges: vec![(0, 1, 1)]
                },
            ]
        );
    }

    #[test]
    fn row_hashes_cover_every_non_empty_row_only() {
        let bytes = format!("{}ab{}cd", cup(1, 1), cup(3, 1));
        // Row 1 (0-based) is never written -> empty -> no fingerprint.
        let out = aggregate_frame(bytes.as_bytes(), 80, 3).expect("must parse");
        let rows: Vec<u16> = out.row_hashes.iter().map(|(row, _)| *row).collect();
        assert_eq!(rows, vec![0, 2]);
        assert_eq!(out.row_hashes[0].1, row_fingerprint("ab").unwrap());
        assert_eq!(out.row_hashes[1].1, row_fingerprint("cd").unwrap());
    }

    #[test]
    fn frame_with_no_links_has_empty_links_but_still_reports_row_hashes() {
        let bytes = format!("{}hello", cup(1, 1));
        let out = aggregate_frame(bytes.as_bytes(), 80, 24).expect("must parse");
        assert!(out.links.is_empty());
        assert_eq!(out.row_hashes, vec![(0, row_fingerprint("hello").unwrap())]);
    }

    #[test]
    fn rejected_frame_propagates_track_error() {
        let bytes = format!("{}\x1b[5x", cup(1, 1));
        let err = aggregate_frame(bytes.as_bytes(), 80, 24).unwrap_err();
        assert_eq!(err, TrackError::UnknownSequence);
    }
}

#[cfg(test)]
mod sanitize_tests {
    use super::*;

    // Cases: ESC, BEL, `\n`,
    // NUL, empty-after-strip, and >2048 bytes.

    #[test]
    fn esc_is_stripped_but_link_survives_if_nonempty_afterward() {
        assert_eq!(
            sanitize_hyperlink_uri("https://a/\x1bx"),
            Some("https://a/x".to_owned())
        );
    }

    #[test]
    fn bel_is_stripped_but_link_survives_if_nonempty_afterward() {
        assert_eq!(
            sanitize_hyperlink_uri("https://a/\x07x"),
            Some("https://a/x".to_owned())
        );
    }

    #[test]
    fn newline_is_stripped_but_link_survives_if_nonempty_afterward() {
        assert_eq!(
            sanitize_hyperlink_uri("https://a/\nx"),
            Some("https://a/x".to_owned())
        );
    }

    #[test]
    fn nul_is_stripped_but_link_survives_if_nonempty_afterward() {
        assert_eq!(
            sanitize_hyperlink_uri("https://a/\0x"),
            Some("https://a/x".to_owned())
        );
    }

    #[test]
    fn empty_after_strip_is_rejected() {
        assert_eq!(sanitize_hyperlink_uri("\x1b\x07\n\0"), None);
        assert_eq!(sanitize_hyperlink_uri(""), None);
    }

    #[test]
    fn exactly_2048_bytes_is_accepted_2049_is_rejected() {
        let at_cap = "a".repeat(2048);
        assert_eq!(sanitize_hyperlink_uri(&at_cap), Some(at_cap));

        let over_cap = "a".repeat(2049);
        assert_eq!(sanitize_hyperlink_uri(&over_cap), None);
    }

    #[test]
    fn sanitize_links_drops_the_whole_entry_when_its_url_is_invalid_not_just_blanks_it() {
        let links = vec![
            AggregatedLink {
                url: "\x1b\x07".to_owned(),
                ranges: vec![(0, 0, 0)],
            },
            AggregatedLink {
                url: "https://ok/".to_owned(),
                ranges: vec![(1, 0, 0)],
            },
        ];
        let out = sanitize_links(links);
        assert_eq!(
            out,
            vec![AggregatedLink {
                url: "https://ok/".to_owned(),
                ranges: vec![(1, 0, 0)]
            }]
        );
    }
}

#[cfg(test)]
mod truncation_tests {
    use super::*;

    fn sample_links() -> Vec<AggregatedLink> {
        vec![AggregatedLink {
            url: "https://example.com/".to_owned(),
            ranges: vec![(0, 0, 5), (1, 0, 5), (2, 0, 5)],
        }]
    }

    fn sample_row_hashes() -> Vec<(u16, String)> {
        vec![
            (0, row_fingerprint("aaaaaa").unwrap()),
            (1, row_fingerprint("bbbbbb").unwrap()),
            (2, row_fingerprint("cccccc").unwrap()),
        ]
    }

    fn sample_meta() -> FrameMeta<'static> {
        FrameMeta {
            pane_id: "w1:p1",
            protocol_version: 22,
            width: 80,
            height: 24,
        }
    }

    #[test]
    fn fits_within_budget_is_not_truncated_and_keeps_every_row() {
        let json = render_output(
            &sample_meta(),
            &sample_links(),
            &sample_row_hashes(),
            60_000,
        );
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        assert_eq!(parsed["truncated"], false);
        assert_eq!(parsed["rowHashes"].as_array().unwrap().len(), 3);
        assert_eq!(parsed["links"][0]["ranges"].as_array().unwrap().len(), 3);
    }

    #[test]
    fn output_is_always_complete_valid_json_never_a_partial_line() {
        // A budget far too small for even the empty skeleton: still parses
        // as complete JSON (never a truncated JSON line), just
        // with every row dropped.
        let json = render_output(&sample_meta(), &sample_links(), &sample_row_hashes(), 1);
        let parsed: serde_json::Value =
            serde_json::from_str(&json).expect("must still be valid json");
        assert_eq!(parsed["truncated"], true);
        assert_eq!(parsed["rowHashes"].as_array().unwrap().len(), 0);
        assert_eq!(parsed["links"].as_array().unwrap().len(), 0);
    }

    #[test]
    fn tight_budget_keeps_bottom_rows_first_and_drops_top_rows() {
        let full = render_output(
            &sample_meta(),
            &sample_links(),
            &sample_row_hashes(),
            60_000,
        );
        // A few bytes below the full size: exactly one row (the topmost,
        // row 0) must be the one dropped, since packing goes bottom-first
        // `- 1` alone is not tight enough here: toggling
        // `truncated` from `false` to `true` alone already shrinks the JSON
        // by 1 byte ("false" -> "true"), so a `- 1` budget would still fit
        // every row without actually dropping any.
        let budget = full.len() - 5;
        let json = render_output(
            &sample_meta(),
            &sample_links(),
            &sample_row_hashes(),
            budget,
        );
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
        assert_eq!(parsed["truncated"], true);
        let kept_rows: Vec<u64> = parsed["rowHashes"]
            .as_array()
            .unwrap()
            .iter()
            .map(|pair| pair[0].as_u64().unwrap())
            .collect();
        assert_eq!(
            kept_rows,
            vec![1, 2],
            "row 0 (topmost) must be the one dropped"
        );
        let kept_ranges: Vec<u64> = parsed["links"][0]["ranges"]
            .as_array()
            .unwrap()
            .iter()
            .map(|range| range[0].as_u64().unwrap())
            .collect();
        assert_eq!(
            kept_ranges,
            vec![1, 2],
            "row 0's range must be dropped from the link too"
        );
    }
}
