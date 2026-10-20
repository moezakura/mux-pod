//! Fixture-based regression test for `CaretOutput::from_tracked_frame`
//! (`src/runner.rs`), the pure function that backs the protocol-22 caret
//! path (`run_observe22`). This proves the function itself is correct
//! against the same real fixture `tests/hyperlinks_grammar.rs`'s
//! `v22_fixture_trailing_cursor_state_matches_meta_md` already uses.

use herdr_caret_helper::runner::CaretOutput;
use herdr_caret_helper::tracker::track_frame;
use std::fs;

#[test]
fn v22_full_redraw_fixture_yields_a_visible_cursor_caret_output() {
    // v22_full_redraw.meta.md: "このfixtureは `?25h`（表示）状態".
    let bytes = fs::read("tests/fixtures/v22_full_redraw.bin").expect("fixture must exist");
    let tracked = track_frame(&bytes, 80, 40).expect("fixture must not be rejected");

    let out = CaretOutput::from_tracked_frame(&tracked, 22, "w1:p1".to_owned(), 80, 40);

    let cursor = out
        .cursor
        .expect("fixture's trailing state is ?25h (visible)");
    assert!(cursor.visible);
    assert!(
        cursor.x < 80,
        "cursor.x={} must be within frame width",
        cursor.x
    );
    assert!(
        cursor.y < 40,
        "cursor.y={} must be within frame height",
        cursor.y
    );
    assert_eq!(out.protocol_version, 22);
    assert_eq!(out.pane_id, "w1:p1");
    assert_eq!(out.frame_width, 80);
    assert_eq!(out.frame_height, 40);
}
