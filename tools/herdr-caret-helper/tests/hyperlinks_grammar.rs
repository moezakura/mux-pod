//! Regression tests for `tracker::track_frame` against the real
//! captured fixtures (`tests/fixtures/v{17,20,22}_full_redraw.bin` and,
//! for a link that genuinely spans multiple physical rows,
//! `tests/fixtures/v{17,20,22}_wrapped_link.bin` — captured later,
//! since `v22_full_redraw.bin`'s own `osc8-wrapped-long-url` turned out to
//! end exactly at the last column rather than actually wrap), confirming
//! zero rejections and that every known link's *exact*
//! `(row, start_col, end_col)` range (per each fixture's `.meta.md`, cross-
//! checked against the tracker's own output) is
//! produced, in emission order — not just that the right URLs are present
//! somewhere. Full same-URL aggregation into the external JSON contract's
//! `ranges` list is `hyperlinks.rs`'s job, not this module's.

use herdr_caret_helper::tracker::{track_frame, RawLinkSpan};
use std::fs;

fn span(row: u16, start_col: u16, end_col: u16, url: &str) -> RawLinkSpan {
    RawLinkSpan {
        row,
        start_col,
        end_col,
        url: url.to_owned(),
    }
}

#[test]
fn v17_full_redraw_fixture_parses_with_exact_known_link_ranges() {
    // v0.7.5, protocol 17. See tests/fixtures/v17_full_redraw.meta.md:
    // cols=80 rows=24, frame.full=true, 2 known links, CUP before every
    // written cell (v0.7.5's own grammar).
    let bytes = fs::read("tests/fixtures/v17_full_redraw.bin").expect("fixture must exist");
    let frame = track_frame(&bytes, 80, 24).expect("v17 fixture must not be rejected");
    assert_eq!(
        frame.links,
        vec![
            span(1, 2, 11, "https://example.com/osc8-https"),
            span(2, 2, 10, "http://example.com/osc8-http"),
        ]
    );
}

#[test]
fn v20_full_redraw_fixture_parses_with_exact_known_link_ranges() {
    // v0.8.2, protocol 20. See tests/fixtures/v20_full_redraw.meta.md:
    // cols=100 rows=29, frame.full=true, 2 known links, CUP omitted after
    // an ASCII width-1 cell.
    let bytes = fs::read("tests/fixtures/v20_full_redraw.bin").expect("fixture must exist");
    let frame = track_frame(&bytes, 100, 29).expect("v20 fixture must not be rejected");
    assert_eq!(
        frame.links,
        vec![
            span(1, 2, 11, "https://example.com/osc8-https"),
            span(2, 2, 10, "http://example.com/osc8-http"),
        ]
    );
}

#[test]
fn v17_and_v20_fixtures_produce_identical_link_ranges_despite_different_cup_frequency() {
    // v0.7.5 (protocol
    // 17) emits a CUP before every written cell; v0.8.2 (protocol 20)
    // omits it after an ASCII width-1 cell — the *only* grammar difference
    // across the 3 supported versions (confirmed directly against both
    // tagged sources; see the module doc comment in `src/tracker.rs`).
    // Both fixtures were captured from the same demo script
    // (`osc8-demo.sh`; both fixtures' own `.meta.md`), so the tracker must
    // resolve both CUP-frequency styles to the exact same link ranges, not
    // merely "the same URLs present somewhere".
    let v17 = fs::read("tests/fixtures/v17_full_redraw.bin").expect("fixture must exist");
    let v20 = fs::read("tests/fixtures/v20_full_redraw.bin").expect("fixture must exist");
    let frame17 = track_frame(&v17, 80, 24).expect("v17 fixture must not be rejected");
    let frame20 = track_frame(&v20, 100, 29).expect("v20 fixture must not be rejected");
    assert_eq!(
        frame17.links, frame20.links,
        "same demo script must yield identical ranges regardless of CUP frequency"
    );
}

#[test]
fn v22_full_redraw_fixture_parses_with_exact_known_link_ranges() {
    // v0.9.1, protocol 22. See tests/fixtures/v22_full_redraw.meta.md:
    // cols=80 rows=40, frame.full=true, 5 known links (including a CJK/
    // full-width-adjacent case and the `osc8-wrapped-long-url` link, whose
    // text happens to land exactly on the fixture's last column — see
    // `hyperlinks_aggregation.rs`'s matching test for the byte-level trace
    // establishing this is correct, not a bug).
    let bytes = fs::read("tests/fixtures/v22_full_redraw.bin").expect("fixture must exist");
    let frame = track_frame(&bytes, 80, 40).expect("v22 fixture must not be rejected");
    assert_eq!(
        frame.links,
        vec![
            span(1, 2, 11, "https://example.com/osc8-https"),
            span(2, 2, 10, "http://example.com/osc8-http"),
            span(3, 2, 10, "file:///etc/hostname"),
            span(4, 2, 9, "https://example.com/osc8-red"),
            span(5, 2, 79, "https://example.com/osc8-wrapped-long-url"),
        ]
    );
}

/// Exact known ranges, from real row-crossing fixtures (captured because
/// `v22_full_redraw.bin`'s own `osc8-wrapped-long-url` turned out to end
/// exactly at the last column, not actually wrap), for a link that *genuinely*
/// spans multiple physical rows, for all 3 supported protocol versions,
/// each checked against its own `.meta.md`'s hand-verified
/// `(row, startCol, endCol)` triples (1-origin/inclusive there, converted
/// to this crate's 0-origin/inclusive here).
///
/// v20 and v22 share the same demo script and the same 73-column width, so
/// their ranges are expected to be byte-identical (asserted directly
/// below) — v17 is captured at a different width (53 cols, its pane's own
/// default size) so its wrap points differ, and is asserted separately
/// against its own `.meta.md`.
#[test]
fn v22_wrapped_link_fixture_parses_with_exact_known_link_ranges_spanning_two_rows() {
    let bytes = fs::read("tests/fixtures/v22_wrapped_link.bin").expect("fixture must exist");
    let frame = track_frame(&bytes, 73, 29).expect("v22 wrapped-link fixture must not be rejected");
    assert_eq!(
        frame.links,
        vec![
            span(1, 2, 72, "https://example.com/osc8-wrap-ascii"),
            span(2, 0, 39, "https://example.com/osc8-wrap-ascii"),
            span(3, 2, 72, "https://example.com/osc8-wrap-cjk"),
            span(4, 0, 49, "https://example.com/osc8-wrap-cjk"),
        ]
    );
}

#[test]
fn v20_wrapped_link_fixture_parses_with_exact_known_link_ranges_spanning_two_rows() {
    let bytes = fs::read("tests/fixtures/v20_wrapped_link.bin").expect("fixture must exist");
    let frame = track_frame(&bytes, 73, 28).expect("v20 wrapped-link fixture must not be rejected");
    assert_eq!(
        frame.links,
        vec![
            span(1, 2, 72, "https://example.com/osc8-wrap-ascii"),
            span(2, 0, 39, "https://example.com/osc8-wrap-ascii"),
            span(3, 2, 72, "https://example.com/osc8-wrap-cjk"),
            span(4, 0, 49, "https://example.com/osc8-wrap-cjk"),
        ]
    );
}

#[test]
fn v20_and_v22_wrapped_link_fixtures_produce_identical_link_ranges() {
    // Same demo script, same 73-column width -- must resolve to byte-
    // identical ranges regardless of protocol version, exactly like the
    // existing v17/v20 `full_redraw` parity test above.
    let v20 = fs::read("tests/fixtures/v20_wrapped_link.bin").expect("fixture must exist");
    let v22 = fs::read("tests/fixtures/v22_wrapped_link.bin").expect("fixture must exist");
    let frame20 = track_frame(&v20, 73, 28).expect("v20 wrapped-link fixture must not be rejected");
    let frame22 = track_frame(&v22, 73, 29).expect("v22 wrapped-link fixture must not be rejected");
    assert_eq!(frame20.links, frame22.links);
}

/// v0.7.5 (protocol 17) is structurally different here (confirmed via the
/// fixture capture and the module doc comment's cited source evidence): it
/// re-opens the *same* URL with a fresh OSC 8 token every time the
/// physical row changes, closing at each row's own last written column,
/// instead of opening once and silently continuing across a row-changing
/// CUP the way v20/v22 do. `track_frame` requires no special handling for
/// this -- each open/close pair is an entirely ordinary, independent span;
/// grouping same-URL spans together is `hyperlinks::aggregate_links`'s job
/// not this module's. This test only confirms `track_frame` itself
/// still parses every one of the 6 raw per-row spans (3 rows x 2 links)
/// exactly as this fixture's `.meta.md` records them, in emission order.
#[test]
fn v17_wrapped_link_fixture_parses_with_exact_known_link_ranges_as_separate_per_row_spans() {
    let bytes = fs::read("tests/fixtures/v17_wrapped_link.bin").expect("fixture must exist");
    let frame = track_frame(&bytes, 53, 23).expect("v17 wrapped-link fixture must not be rejected");
    assert_eq!(
        frame.links,
        vec![
            span(1, 2, 52, "https://example.com/osc8-wrap-ascii"),
            span(2, 0, 52, "https://example.com/osc8-wrap-ascii"),
            span(3, 0, 6, "https://example.com/osc8-wrap-ascii"),
            span(4, 2, 52, "https://example.com/osc8-wrap-cjk"),
            span(5, 0, 52, "https://example.com/osc8-wrap-cjk"),
            span(6, 0, 17, "https://example.com/osc8-wrap-cjk"),
        ]
    );
}

#[test]
fn v22_fixture_trailing_cursor_state_matches_meta_md() {
    // v22_full_redraw.meta.md: this fixture's cursor state is `?25h`
    // (visible), captured at the trailing CUP/DECSCUSR block (the exact
    // position/shape are ground truth read directly
    // from this fixture, not asserted in the .meta.md itself).
    let bytes = fs::read("tests/fixtures/v22_full_redraw.bin").expect("fixture must exist");
    let frame = track_frame(&bytes, 80, 40).expect("v22 fixture must not be rejected");
    assert_eq!(frame.cursor_position, Some((7, 22)));
    assert_eq!(frame.cursor_visible, Some(true));
    assert_eq!(frame.cursor_shape, Some(3));
}
