//! Unit tests for the OSC 8 grammar tracker, driven by synthetic byte
//! sequences through the public `track_frame` API. Real captured frames are
//! covered by the integration tests under `tests/`.

use super::*;

// Synthetic byte-sequence builders. Real captured frames
// are exercised separately in the fixture regression tests.
fn cup(row1: u16, col1: u16) -> String {
    format!("\x1b[{};{}H", row1, col1)
}
fn bare_cup() -> &'static str {
    "\x1b[H"
}
fn osc8_open(url: &str) -> String {
    format!("\x1b]8;;{}\x1b\\", url)
}
fn osc8_close() -> &'static str {
    "\x1b]8;;\x1b\\"
}

#[test]
fn cup_then_ascii_print_builds_row_string() {
    let bytes = format!("{}hello", cup(1, 1));
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "hello");
    assert!(frame.links.is_empty());
}

#[test]
fn bare_cup_defaults_to_row1_col1() {
    // v0.7.5's full-redraw preamble form (`ESC[2J ESC[H`), confirmed
    // against the real v0.7.5 source (see module doc comment).
    let bytes = format!("{}X", bare_cup());
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "X");
}

#[test]
fn non_ascii_print_then_unpositioned_print_is_rejected() {
    // CUP -> non-ASCII (position becomes indeterminate) -> ASCII print
    // with no intervening CUP: must reject (PrintWithoutPosition).
    let bytes = format!("{}あX", cup(1, 1));
    let err = track_frame(bytes.as_bytes(), 80, 24).unwrap_err();
    assert_eq!(err, TrackError::PrintWithoutPosition);
}

#[test]
fn cup_after_non_ascii_restores_position() {
    let bytes = format!("{}あ{}X", cup(1, 1), cup(1, 3));
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "あX");
}

#[test]
fn osc8_open_close_produces_link_span() {
    let bytes = format!(
        "{}{}ab{}",
        cup(1, 1),
        osc8_open("https://example.com/"),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "ab");
    assert_eq!(
        frame.links,
        vec![RawLinkSpan {
            row: 0,
            start_col: 0,
            end_col: 1,
            url: "https://example.com/".to_owned(),
        }]
    );
}

#[test]
fn osc8_switch_between_two_urls_same_row() {
    let bytes = format!(
        "{}{}a{}b{}",
        cup(1, 1),
        osc8_open("https://a/"),
        osc8_open("https://b/"),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "ab");
    assert_eq!(
        frame.links,
        vec![
            RawLinkSpan {
                row: 0,
                start_col: 0,
                end_col: 0,
                url: "https://a/".to_owned()
            },
            RawLinkSpan {
                row: 0,
                start_col: 1,
                end_col: 1,
                url: "https://b/".to_owned()
            },
        ]
    );
}

#[test]
fn link_spanning_row_change_closes_at_line_end_and_continues() {
    // width=3: row 0 has 3 printable cols. Link opens at (0,1), a
    // character is written at col1, then CUP moves to row 1 while the
    // link is still open (no OSC8 close in between) — the row-0 span
    // must close at width-1 (col 2), and a new row-1 span for the same
    // URL must start at the CUP's column.
    let bytes = format!(
        "{}{}z{}y{}",
        cup(1, 2),
        osc8_open("https://wrap/"),
        cup(2, 1),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 3, 3).expect("must parse");
    assert_eq!(frame.rows[0], "z");
    assert_eq!(frame.rows[1], "y");
    assert_eq!(
        frame.links,
        vec![
            RawLinkSpan {
                row: 0,
                start_col: 1,
                end_col: 2,
                url: "https://wrap/".to_owned()
            },
            RawLinkSpan {
                row: 1,
                start_col: 0,
                end_col: 0,
                url: "https://wrap/".to_owned()
            },
        ]
    );
}

#[test]
fn skip_tokens_do_not_affect_position_or_links_and_trailer_is_recorded() {
    let bytes = format!(
        "\x1b[?2026h\x1b[?25l{}\x1b[2J{}ab{}\x1b[0m{}\x1b[3 q\x1b[?25h\x1b[?2026l",
        cup(1, 1),
        osc8_open("https://x/"),
        osc8_close(),
        cup(1, 5),
    );
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "ab");
    assert_eq!(
        frame.links,
        vec![RawLinkSpan {
            row: 0,
            start_col: 0,
            end_col: 1,
            url: "https://x/".to_owned()
        }]
    );
    // Trailing cursor-state block: the last
    // CUP/shape/visibility seen anywhere in the frame.
    assert_eq!(frame.cursor_position, Some((0, 4)));
    assert_eq!(frame.cursor_shape, Some(3));
    assert_eq!(frame.cursor_visible, Some(true));
}

#[test]
fn unknown_escape_sequence_is_rejected() {
    let bytes = format!("{}\x1b[5x", cup(1, 1));
    let err = track_frame(bytes.as_bytes(), 80, 24).unwrap_err();
    assert_eq!(err, TrackError::UnknownSequence);
}

#[test]
fn raw_control_byte_outside_escape_sequence_is_rejected() {
    let bytes = format!("{}a\x01b", cup(1, 1));
    let err = track_frame(bytes.as_bytes(), 80, 24).unwrap_err();
    assert_eq!(err, TrackError::UnknownSequence);
}

#[test]
fn control_char_in_osc8_uri_drops_only_that_link() {
    // A raw NUL byte inside the URI body: that link alone is excluded
    // (no span); the neighbouring valid link, the row text and the
    // positions are untouched.
    let bytes = format!(
        "{}{}bad{}{}ok{}",
        cup(1, 1),
        "\x1b]8;;https://x/\x00y\x1b\\",
        osc8_open("https://good/"),
        "",
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "badok");
    assert_eq!(
        frame.links,
        vec![RawLinkSpan {
            row: 0,
            start_col: 3,
            end_col: 4,
            url: "https://good/".to_owned()
        }]
    );
}

#[test]
fn bel_terminated_osc8_uri_drops_only_that_link() {
    // BEL ends the URI body (a control byte, so the link is excluded)
    // and is consumed as the terminator.
    let bytes = format!(
        "{}\x1b]8;;https://x/\x07bad{}{}ok{}",
        cup(1, 1),
        osc8_close(),
        osc8_open("https://good/"),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "badok");
    assert_eq!(frame.links.len(), 1);
    assert_eq!(frame.links[0].url, "https://good/");
}

#[test]
fn invalid_link_switching_from_a_valid_link_closes_the_valid_one() {
    let bytes = format!(
        "{}{}ab\x1b]8;;u\x01v\x1b\\cd{}",
        cup(1, 1),
        osc8_open("https://good/"),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "abcd");
    assert_eq!(frame.links.len(), 1);
    assert_eq!((frame.links[0].start_col, frame.links[0].end_col), (0, 1));
}

#[test]
fn esc_that_is_not_a_st_inside_an_osc8_uri_rejects_the_frame() {
    // An unterminated OSC 8 followed by a CSI:
    // swallowing the CSI as "URI bytes" would drop a CUP and print
    // later links on the wrong row, so the frame is rejected.
    let bytes = format!(
        "{}AB\x1b]8;;https://a/\x1b[3;1HXY{}{}cc{}",
        cup(1, 1),
        osc8_close(),
        osc8_open("https://c/"),
        osc8_close()
    );
    let err = track_frame(bytes.as_bytes(), 80, 24).unwrap_err();
    assert_eq!(err, TrackError::UnknownSequence);
}

#[test]
fn esc_inside_an_osc8_uri_is_rejected_even_after_other_control_bytes() {
    let bytes = format!("{}\x1b]8;;https://x/\x00y\x1bz\x1b\\", cup(1, 1));
    let err = track_frame(bytes.as_bytes(), 80, 24).unwrap_err();
    assert_eq!(err, TrackError::UnknownSequence);
}

#[test]
fn control_char_uri_without_any_terminator_is_still_truncated() {
    let bytes = format!("{}\x1b]8;;https://x/\x00y", cup(1, 1));
    let err = track_frame(bytes.as_bytes(), 80, 24).unwrap_err();
    assert_eq!(err, TrackError::Truncated);
}

#[test]
fn cup_out_of_bounds_is_rejected() {
    let bytes = cup(1, 81); // col 81 (1-based) = col 80 (0-based) >= width 80
    let err = track_frame(bytes.as_bytes(), 80, 24).unwrap_err();
    assert_eq!(err, TrackError::CupOutOfBounds);
}

#[test]
fn unclosed_link_at_end_of_frame_is_rejected() {
    let bytes = format!("{}{}ab", cup(1, 1), osc8_open("https://x/"));
    let err = track_frame(bytes.as_bytes(), 80, 24).unwrap_err();
    assert_eq!(err, TrackError::UnclosedLinkAtEndOfFrame);
}

#[test]
fn invalid_utf8_is_rejected() {
    let bytes: &[u8] = &[0x1b, b'[', b'1', b';', b'1', b'H', 0xff, 0xfe];
    let err = track_frame(bytes, 80, 24).unwrap_err();
    assert_eq!(err, TrackError::InvalidUtf8);
}

#[test]
fn empty_link_span_is_rejected() {
    // Open then immediately switch/close with no character written in
    // between — herdr's own encoder never produces this (OSC 8 is only
    // ever written immediately before a cell's character).
    let bytes = format!("{}{}{}", cup(1, 1), osc8_open("https://x/"), osc8_close());
    let err = track_frame(bytes.as_bytes(), 80, 24).unwrap_err();
    assert_eq!(err, TrackError::EmptyLinkSpan);
}

// --- Colon SGR sub-parameters and grapheme clusters ---

#[test]
fn sgr_with_colon_separated_subparameters_is_ignored_not_rejected() {
    // herdr emits colon-separated SGR sub-parameters for the
    // underline style (e.g. `4:3` = "curly"), confirmed directly
    // against the real source: the encoding
    // (`render_ansi.rs:437-443`, `match underline_style_from_modifier
    // { 2 => "4:2", 3 => "4:3", ... }`) and its own test asserting the
    // exact literal this test uses (`render_ansi.rs:1195`:
    // `"\x1b[0;4:3;39;49m"`). SGR is read-and-ignored regardless of
    // its parameters, so a colon here must not reject
    // the frame.
    let bytes = format!("{}\x1b[0;4:3;39;49mab", cup(1, 1));
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "ab");
    assert!(frame.links.is_empty());
}

#[test]
fn halfwidth_katakana_with_voiced_sound_mark_is_one_cell_not_rejected() {
    // "ｶﾞ" = U+FF76 (halfwidth ｶ) + U+FF9E (halfwidth voiced
    // sound mark) -- both non-ASCII, herdr's own
    // `is_halfwidth_katakana_voiced_grapheme` special-cases exactly
    // this pair into one cell (confirmed present in all 3 tagged
    // versions' `render_ansi.rs`). herdr writes `cell.symbol.as_bytes()`
    // as one `write_all` call with no separator between the two
    // codepoints (v0.7.5:706, v0.8.2:754, v0.9.1:981), so the tracker
    // must not require a fresh position between them. The `X` that
    // follows is a genuinely new cell, so it still needs its own CUP
    // (`next_inline_col` is only set after an ASCII width-1 cell --
    // never after a non-ASCII one), exactly like real herdr output.
    let bytes = format!("{}ｶﾞ{}X", cup(1, 1), cup(1, 2));
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "ｶﾞX");
}

#[test]
fn emoji_with_skin_tone_modifier_is_one_cell_not_rejected() {
    // "👍🏽" = U+1F44D (thumbs up) + U+1F3FD (medium skin
    // tone modifier), both non-ASCII, one grapheme cluster / one
    // terminal cell. `X` still needs its own CUP -- see the katakana
    // test above.
    let bytes = format!("{}👍🏽{}X", cup(1, 1), cup(1, 2));
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "👍🏽X");
}

#[test]
fn base_letter_with_combining_accent_is_one_cell_not_rejected() {
    // "e" + COMBINING ACUTE ACCENT (U+0301) -- not the
    // precomposed U+00E9 -- matches `row_fingerprint_combining_character`
    // (tracker.rs's own `mod tests`)'s test string, exercised here at
    // the grammar level instead of just the fingerprint level. `X`
    // still needs its own CUP -- see the katakana test above.
    let bytes = format!("{}cafe\u{0301}{}X", cup(1, 1), cup(1, 5));
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "cafe\u{0301}X");
}

#[test]
fn cjk_with_variation_selector_16_is_one_cell_not_rejected() {
    // A CJK character followed by VARIATION SELECTOR-16
    // (U+FE0F, forces emoji-style presentation) -- both non-ASCII, one
    // cell. `X` still needs its own CUP -- see the katakana test above.
    let bytes = format!("{}\u{6587}\u{fe0f}{}X", cup(1, 1), cup(1, 2));
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "\u{6587}\u{fe0f}X");
}

#[test]
fn non_ascii_print_then_sgr_then_unpositioned_print_is_still_rejected() {
    // Confirms the grapheme-cluster handling does not over-widen: a *token* (SGR)
    // between two prints is not "no separator" -- position stays
    // Indeterminate across it (skip tokens never restore position),
    // so "あ" SGR "X" must still reject, exactly like the pre-existing
    // `non_ascii_print_then_unpositioned_print_is_rejected` case with
    // no token at all.
    let bytes = format!("{}あ\x1b[1mX", cup(1, 1));
    let err = track_frame(bytes.as_bytes(), 80, 24).unwrap_err();
    assert_eq!(err, TrackError::PrintWithoutPosition);
}

#[test]
fn link_closing_immediately_after_a_non_ascii_cell_at_frame_end_is_not_rejected() {
    // Link ending in a full-width character: herdr's
    // `write_all_cells` calls the frame-final `close_hyperlink`
    // unconditionally, with no CUP and no following print (v0.9.1
    // `render_ansi.rs:893`, identical in all 3 versions) -- if the
    // last cell written under an open link is non-ASCII, this close
    // observes `Indeterminate` position. It must close at the frame's
    // own last column, not reject the whole frame. width=3/height=1 so
    // "あ" (starting at col 2) really is the frame's own bottom-right
    // cell -- the only shape this close token is ever legitimately
    // reached in (a non-final row/column here rejects via
    // `IndeterminateCloseNotAtFrameEnd`).
    let bytes = format!(
        "{}{}AB\u{3042}{}",
        cup(1, 1),
        osc8_open("https://x/"),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 3, 1).expect("must parse");
    assert_eq!(frame.rows[0], "AB\u{3042}");
    assert_eq!(
        frame.links,
        vec![RawLinkSpan {
            row: 0,
            start_col: 0,
            end_col: 2,
            url: "https://x/".to_owned()
        }]
    );
}

#[test]
fn ascii_digit_base_with_variation_selector_and_enclosing_keycap_is_one_cell() {
    // Keycap "1️⃣" = U+0031 '1' (ASCII) + U+FE0F
    // (variation selector-16) + U+20E3 (combining enclosing keycap).
    // Both trailing codepoints are non-ASCII but attach to the ASCII
    // base '1' as one cell -- `X` that follows still needs its own CUP
    // (the merged cell's `symbol` is not all-ASCII, so herdr's
    // `next_inline_col` is `None`), exactly like the non-ASCII-base
    // grapheme-cluster tests above.
    let bytes = format!("{}1\u{FE0F}\u{20E3}{}X", cup(1, 1), cup(1, 2));
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "1\u{FE0F}\u{20E3}X");
}

#[test]
fn ascii_letter_base_with_decomposed_combining_accent_is_one_cell() {
    // Decomposed "é" = ASCII 'e' + U+0301
    // (COMBINING ACUTE ACCENT), as opposed to the precomposed U+00E9.
    // Same reasoning as the keycap test above; `X` needs its own CUP.
    let bytes = format!("{}caf\u{0065}\u{0301}{}X", cup(1, 1), cup(1, 5));
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "cafe\u{0301}X");
}

#[test]
fn decomposed_accent_closing_a_link_at_frame_end_gets_the_correct_start_column() {
    // The scenario the `is_grapheme_continuation` distinction
    // actually matters for: without it, an ASCII base followed by a
    // real trailing combining mark would be mis-tracked as if the
    // combining mark started its *own* new cell one column later,
    // shifting a frame-final close's end column off by one. Here the
    // link's text is exactly "e\u{0301}" (one cell) and the *only*
    // cell in a width=1/height=1 frame, so its correct end_col is the
    // frame's own last column (0) -- which also happens to equal its
    // own start_col here, unlike the wider frame-final tests above
    // (the close now always uses `width - 1`, not `start_col`).
    let bytes = format!(
        "{}{}e\u{0301}{}",
        cup(1, 1),
        osc8_open("https://x/"),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 1, 1).expect("must parse");
    assert_eq!(frame.rows[0], "e\u{0301}");
    assert_eq!(
        frame.links,
        vec![RawLinkSpan {
            row: 0,
            start_col: 0,
            end_col: 0,
            url: "https://x/".to_owned()
        }]
    );
}

#[test]
fn ascii_cell_immediately_followed_by_a_distinct_non_ascii_cell_is_not_merged() {
    // The over-widening this fix must *not* introduce (regression
    // guard): "B" is a genuine standalone ASCII, width-1 cell, so
    // herdr's own `next_inline_col` *is* set after it -- a distinct,
    // unrelated non-ASCII cell (CJK "あ", not a combining mark) can
    // legitimately follow with no CUP in between. This must still
    // parse as two separate cells, not be folded into one "Bあ" cell
    // the way a real combining mark would be.
    let bytes = format!("{}AB\u{3042}", cup(1, 1));
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "AB\u{3042}");
}

#[test]
fn fullwidth_cjk_link_is_tracked_like_any_other_link() {
    // CJK full-width link: every character of the link text
    // itself is non-ASCII. Unlike the grapheme-cluster tests above,
    // "あ", "い", "う" are three distinct cells (not combining marks
    // continuing one cluster), so each gets its own CUP in real herdr
    // output -- `next_inline_col` is never set after a non-ASCII cell.
    // width=3/height=1 so "う" (the last cell) really is the frame's
    // own bottom-right cell, matching the frame-final close's
    // invariant.
    let bytes = format!(
        "{}{}\u{3042}{}\u{3044}{}\u{3046}{}",
        cup(1, 1),
        osc8_open("https://cjk/"),
        cup(1, 2),
        cup(1, 3),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 3, 1).expect("must parse");
    assert_eq!(frame.rows[0], "\u{3042}\u{3044}\u{3046}");
    assert_eq!(
        frame.links,
        vec![RawLinkSpan {
            row: 0,
            start_col: 0,
            end_col: 2,
            url: "https://cjk/".to_owned()
        }]
    );
}

// --- Frame-final Indeterminate close must end at `width - 1`, not
// `start_col`, and nothing printable may follow it. ---

#[test]
fn ascii_then_fullwidth_cjk_link_closes_at_the_frames_final_two_columns() {
    // "ab" (cols 0-1) + "あ" (starting col 2, one cell): in a
    // width=4/height=1 frame, "あ" is the frame's own bottom-right
    // cell, so the frame-final close must cover through the frame's
    // last column (3) -- both of "あ"'s own on-screen columns, not just
    // its start_col (2).
    let bytes = format!(
        "{}{}ab\u{3042}{}",
        cup(1, 1),
        osc8_open("https://x/"),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 4, 1).expect("must parse");
    assert_eq!(frame.rows[0], "ab\u{3042}");
    assert_eq!(
        frame.links,
        vec![RawLinkSpan {
            row: 0,
            start_col: 0,
            end_col: 3,
            url: "https://x/".to_owned()
        }]
    );
}

#[test]
fn keycap_link_closes_at_the_frames_final_two_columns() {
    // "X" (col 0, unrelated/unlinked) + keycap "1️⃣" (starting col 1,
    // one cell): in a width=3/height=1 frame, the keycap is the
    // frame's own bottom-right cell, so its link must close through
    // the frame's last column (2), covering both of the keycap's own
    // on-screen columns.
    let bytes = format!(
        "{}X{}1\u{FE0F}\u{20E3}{}",
        cup(1, 1),
        osc8_open("https://x/"),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 3, 1).expect("must parse");
    assert_eq!(frame.rows[0], "X1\u{FE0F}\u{20E3}");
    assert_eq!(
        frame.links,
        vec![RawLinkSpan {
            row: 0,
            start_col: 1,
            end_col: 2,
            url: "https://x/".to_owned()
        }]
    );
}

#[test]
fn cjk_link_at_the_frames_single_final_column_closes_with_a_one_column_span() {
    // The boundary case where the frame-final cell's own start_col
    // *is* the frame's last column already (width=1/height=1): the
    // close still correctly uses `width - 1` (0), which here happens
    // to equal start_col too -- there is no second column to include.
    let bytes = format!(
        "{}{}\u{3042}{}",
        cup(1, 1),
        osc8_open("https://x/"),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 1, 1).expect("must parse");
    assert_eq!(frame.rows[0], "\u{3042}");
    assert_eq!(
        frame.links,
        vec![RawLinkSpan {
            row: 0,
            start_col: 0,
            end_col: 0,
            url: "https://x/".to_owned()
        }]
    );
}

#[test]
fn print_after_the_frame_final_indeterminate_link_close_is_rejected() {
    // herdr only ever reaches the frame-final
    // Indeterminate-position close once, strictly after the very last
    // cell of the very last row -- nothing printable legitimately
    // follows it, even across an intervening CUP that resets
    // `position` back to `Fixed` (which would otherwise make a further
    // print look like an ordinary, valid one).
    let bytes = format!(
        "{}{}\u{3042}{}{}X",
        cup(1, 1),
        osc8_open("https://x/"),
        osc8_close(),
        cup(1, 1),
    );
    let err = track_frame(bytes.as_bytes(), 1, 1).unwrap_err();
    assert_eq!(err, TrackError::PrintAfterFrameFinalClose);
}

#[test]
fn indeterminate_close_not_on_the_frames_last_row_is_rejected() {
    // Defensive fail-closed check: herdr's `write_all_cells` only ever reaches the
    // frame-final Indeterminate-position close after every row has
    // been fully written, so the still-open link's own row must be the
    // frame's last row. A link closing here while `Indeterminate` on
    // an earlier row (no CUP ever having intervened) does not match
    // any real herdr output and must reject, not silently under-close.
    let bytes = format!(
        "{}{}\u{3042}{}",
        cup(1, 1),
        osc8_open("https://x/"),
        osc8_close()
    );
    let err = track_frame(bytes.as_bytes(), 1, 2).unwrap_err();
    assert_eq!(err, TrackError::IndeterminateCloseNotAtFrameEnd);
}

#[test]
fn adjacent_different_urls_with_an_explicit_close_then_open_between_them() {
    // Adjacent different URLs (a close followed by an open): unlike
    // `osc8_switch_between_two_urls_same_row` (which switches without
    // an intervening explicit close token), this exercises a genuine
    // close token immediately followed by a genuine open token for a
    // different URL, both still adjacent (no gap column between them).
    let bytes = format!(
        "{}{}a{}{}b{}",
        cup(1, 1),
        osc8_open("https://a/"),
        osc8_close(),
        osc8_open("https://b/"),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(frame.rows[0], "ab");
    assert_eq!(
        frame.links,
        vec![
            RawLinkSpan {
                row: 0,
                start_col: 0,
                end_col: 0,
                url: "https://a/".to_owned()
            },
            RawLinkSpan {
                row: 0,
                start_col: 1,
                end_col: 1,
                url: "https://b/".to_owned()
            },
        ]
    );
}

#[test]
fn same_url_reopened_later_produces_two_separate_raw_spans() {
    // Several ranges for the same URL: at this (unaggregated) layer,
    // two separate open/close cycles for the same URL simply produce
    // two separate `RawLinkSpan`s in emission order -- merging same-URL
    // spans into one contract entry is `hyperlinks.rs`'s job
    // (`aggregate_links`), not this module (see the module doc
    // comment on `RawLinkSpan`).
    let bytes = format!(
        "{}{}a{}{}{}b{}",
        cup(1, 1),
        osc8_open("https://same/"),
        osc8_close(),
        cup(1, 5),
        osc8_open("https://same/"),
        osc8_close()
    );
    let frame = track_frame(bytes.as_bytes(), 80, 24).expect("must parse");
    assert_eq!(
        frame.links,
        vec![
            RawLinkSpan {
                row: 0,
                start_col: 0,
                end_col: 0,
                url: "https://same/".to_owned()
            },
            RawLinkSpan {
                row: 0,
                start_col: 4,
                end_col: 4,
                url: "https://same/".to_owned()
            },
        ]
    );
}
