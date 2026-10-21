//! OSC 8 grammar tracker for one `TerminalAnsi` full-redraw frame.
//!
//! Walks the frame's byte grammar (CUP, printable cells, OSC 8 open/close,
//! and the small set of tokens that are read and ignored) and returns the
//! displayed rows, the raw per-row link spans, and the trailing cursor
//! state. Fail-closed: any unknown or inconsistent sequence is rejected as a
//! `TrackError`. Re-exported from the parent `tracker` module.

// ---------------------------------------------------------------------
// Frame grammar tracker.
// ---------------------------------------------------------------------
//
// Byte-grammar tracker for a single `TerminalAnsi` full-redraw frame
// (`TerminalFrame.bytes` with `full == true`; the caller — `ansi_runner`'s
// `observe_terminal_ansi` — already rejects `full == false` before this is
// ever reached).
//
// Shared by protocols 17/20/22: the grammar itself (position-setting CUP,
// ASCII print, non-ASCII print making position indeterminate, OSC 8
// open/close, and a small set of "read and ignore" tokens) is identical
// across all three. Only the *frequency* of CUP emission differs (v0.7.5
// emits one before every written cell; v0.8.2/v0.9.1 omit it after an
// ASCII width-1 cell). This was verified directly against
// `render_ansi.rs` for all three tagged versions (file:line evidence is cited
// below); `tests/fixtures/v{17,20,22}_full_redraw.bin` holds real captured
// frames used by the regression tests.
//
// Grammar:
// - Position is `Fixed{row,col}` or `Indeterminate{start_col}` (the column
//   where the current ambiguous-width cell began; see below).
// - A CUP (`ESC[{row};{col}H`, 1-based; or bare `ESC[H` = row 1/col 1 —
//   only emitted by v0.7.5's full-redraw preamble, confirmed via
//   `git show v0.7.5:src/protocol/render_ansi.rs:445-447`) sets position
//   to `Fixed` and, if a link is open and the row changed, closes that
//   link's range at the previous row's last column (`width - 1`) and
//   starts a new range for the *same* URL at the new row (cross-row link
//   continuation; herdr's own `write_hyperlink_if_changed` never re-emits
//   OSC 8 for a link that is already active — confirmed byte-identical
//   across all 3 tagged versions: v0.7.5:658, v0.8.2:706, v0.9.1:928 — so
//   there is no separate "reopen" token to observe here).
// - A printable character starts a cell whose `symbol` may hold more than
//   one Unicode codepoint (halfwidth katakana + voiced mark, emoji +
//   skin-tone/ZWJ modifiers, a base letter + combining accent, a keycap's
//   base digit + variation selector + combining enclosing keycap, ...):
//   herdr's `write_cell` writes `cell.symbol.as_bytes()` as a single
//   `write_all` call with no separator between its codepoints — confirmed
//   identical in all 3 tagged versions (v0.7.5:706, v0.8.2:754,
//   v0.9.1:981). herdr does not decide a cell's grapheme boundary itself:
//   `pane/terminal.rs`'s `ghostty_buffer_symbol_into` reads each cell's
//   full grapheme text via `RowCellIter::grapheme_text_into`
//   (`src/ghostty/mod.rs:3564`), an FFI call into libghostty's own
//   per-cell grapheme storage (`GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_
//   GRAPHEMES_UTF8`) — the `vte`/`unicode-segmentation` crates are not
//   used for PTY grid emulation (`unicode-segmentation` appears only in
//   `client/shell/text_editor.rs`, an unrelated line editor). libghostty
//   attaches a trailing combining/variation-selector/enclosing codepoint
//   to its preceding base cell regardless of whether that base codepoint
//   is itself ASCII (a combining mark, variation selector, ZWJ, or
//   modifier codepoint is always non-ASCII and always *follows* its base
//   character, never the reverse — real Unicode grapheme cluster
//   structure), so the tracker consumes `ch0` plus every further
//   character up to (but not including) the next escape sequence, control
//   byte, or ASCII character as this one cell — regardless of whether
//   `ch0` itself was ASCII or not. Only when the *whole* consumed span is
//   a single ASCII character (`ch0.is_ascii()` and nothing else was
//   consumed) does position stay `Fixed`, one column forward, matching
//   herdr's own CUP-omission condition exactly (ASCII + width 1 — see
//   `next_inline_col` in `render_ansi.rs`'s `write_all_cells`;
//   cell width is never recomputed here). Every other case — a non-ASCII
//   base cell, or an ASCII base with a trailing non-ASCII continuation —
//   sets position to `Indeterminate{start_col}` (its true on-screen
//   width, and hence its exact end column, is herdr's to know, not ours),
//   since `next_inline_col` only clears to `None` after such a cell, so
//   the *next distinct cell* always gets its own explicit CUP.
// - A printable character while position is `Indeterminate` is rejected
//   (`PrintWithoutPosition`) — per the above, herdr's own grammar never
//   produces a genuinely new cell here without an intervening CUP, so this
//   is fail-closed evidence of drift/corruption, not a false positive.
// - OSC 8 open/close (`ESC]8;;<uri><ST>`, uri non-empty/empty
//   respectively) switches the active link, closing the previous one (if
//   any) at the current column - 1 (same row, `Fixed` position) or
//   `width - 1` (already closed by an intervening row-change CUP). A
//   *close* specifically may also legitimately fire while position is
//   `Indeterminate`: herdr's `write_all_cells` calls the frame-final
//   `close_hyperlink` unconditionally, with no CUP and no following print,
//   right after the very last cell of the very last row — if that cell was
//   non-ASCII, this is the one place a hyperlink token observes
//   `Indeterminate` position. Because this can only happen once every row
//   has been fully written, the still-open link's own row must be the
//   frame's last row (`height - 1`, else `IndeterminateCloseNotAtFrameEnd`)
//   and it closes at the frame's own last column (`width - 1`, not its own
//   `start_col` — a multi-column cell's own right half would otherwise be
//   under-counted), relying on the print branch already having resolved any pending
//   row change before this token is ever reached (see `track_frame`'s
//   comment on the row-continuation block). Nothing printable may
//   legitimately follow this close either way — a later print reaching
//   `track_frame`'s print branch after it fired rejects with
//   `PrintAfterFrameFinalClose`, even across an intervening CUP that resets
//   `position` back to `Fixed` (see that variant's doc comment). An *open*
//   never legitimately observes `Indeterminate`: every mid-frame OSC 8
//   token is written immediately before a real print (`write_cell`'s
//   order: CUP → SGR → hyperlink → symbol), so a still-`Indeterminate`
//   position at that point is a genuine grammar violation, correctly
//   rejected via the same `PrintWithoutPosition` path as any other
//   unpositioned print.
// - A fixed "read and ignore" token set (`?2026h`/`?2026l` sync markers,
//   `?25h`/`?25l` cursor visibility, DECSCUSR `ESC[{n} q` cursor shape,
//   `ESC[2J` screen clear, any `ESC[...m` SGR) does not change position or
//   link state. Visibility/shape/CUP values seen here *are* recorded
//   (`TrackedFrame::cursor*`) because whatever was last seen when the
//   frame ends is, by construction, the trailing cursor-state block
//   (consumed by the protocol-22 caret extraction, not by the hyperlink
//   aggregation).
// - Anything else (unrecognized escape, unrecognized control byte in
//   "print" position) is rejected (`UnknownSequence`) — herdr changing
//   its render grammar under the same protocol number must fail closed,
//   not silently misparse.
//
// **OSC 8 URI containing a C0 control byte**:
// the Dart `ansi_line_parser.dart` OSC 8 reader treats any C0 byte other
// than BEL/ESC as an ordinary URI character; this tracker is stricter and
// does not accept such a URI, but the damage is confined to that *one
// link*: `parse_osc8` keeps scanning to the terminator (ST `ESC \`, or a
// BEL) and returns `Token::LinkOpenInvalid`, so no span is produced for it
// while the row text, the positions, every other link and the cursor state
// stay intact (an OSC 8 sequence never advances the cell position). The
// exclusion is silent, like `hyperlinks.rs`'s `sanitize_links`. If the
// input ends before any terminator, the frame is `Truncated` (rejected as
// a whole). herdr's own encoder always terminates OSC 8 with ST, never BEL
// (`tests/fixtures/v17_full_redraw.bin` contains zero `0x07` bytes); a
// BEL-terminated sequence is therefore treated as an invalid link rather
// than as a valid one. An ESC inside the URI that does not begin ST is
// not a "control character in the URI" in this sense: the sequence is
// unterminated/desynced and what follows would be swallowed, so the whole
// frame is rejected (`UnknownSequence`).

/// Cursor position while tracking a frame. `Indeterminate` means: a
/// non-ASCII cell was just printed and no CUP has re-fixed the position
/// since. `start_col` is that cell's own
/// starting column — still known, even though its end column (and hence
/// where the *next* cell would begin) is not — used only by the
/// frame-final OSC 8 close special case (see the module doc comment).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Position {
    Fixed { row: u16, col: u16 },
    Indeterminate { start_col: u16 },
}

/// One contiguous, single-row span of an OSC 8 hyperlink as emitted by the
/// tracker, in emission order. `url` is the raw URI text captured between
/// `ESC]8;;` and the ST terminator — **not yet sanitized** (`hyperlinks.rs`
/// applies herdr's `sanitized_hyperlink_uri`-equivalent
/// stripping and the 2048-byte cap; this type only guarantees the URI
/// contained no C0 control byte, since that would have rejected the whole
/// frame instead of producing a span). `hyperlinks.rs` aggregates
/// same-URL spans (including ones split across rows by this module) into
/// the external JSON contract's per-URL `ranges` list.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawLinkSpan {
    pub row: u16,
    pub start_col: u16,
    /// Inclusive.
    pub end_col: u16,
    pub url: String,
}

/// Result of successfully tracking one full-redraw frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrackedFrame {
    /// Per-row display text (index = row, `rows.len() == height`). Each
    /// row is exactly the characters herdr actually wrote for that row, in
    /// emission order — double-wide continuation cells never appear here
    /// because herdr's own `write_all_cells` never emits a symbol for them
    /// (verified in the design memo), so no extra trimming is needed to
    /// satisfy the "no continuation cells" rule.
    pub rows: Vec<String>,
    /// Raw, unaggregated link spans in emission order (see `RawLinkSpan`).
    pub links: Vec<RawLinkSpan>,
    /// The last CUP position seen anywhere in the frame (0-based). Once
    /// cell-writing finishes, the only remaining CUP is the trailing
    /// cursor-state block's, so after a full parse this is that block's
    /// position (consumed by the protocol-22 caret extraction).
    pub cursor_position: Option<(u16, u16)>,
    /// The last `?25h`/`?25l` seen (`true` = visible).
    pub cursor_visible: Option<bool>,
    /// The last DECSCUSR shape number seen.
    pub cursor_shape: Option<u8>,
}

/// Why a frame was rejected. Every
/// variant is surfaced by callers as `RunError::RenderRejected` — see
/// `ansi_runner.rs` (which itself only checks `TerminalFrame.full`) and
/// `hyperlinks.rs` (which calls `track_frame` and maps any `Err`
/// here to that same classification, never a bare panic).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TrackError {
    /// A printable character arrived while position was `Indeterminate`
    /// (non-ASCII print with no following CUP before the next print).
    PrintWithoutPosition,
    /// A CUP's row/col was outside the frame's declared `width`/`height`.
    CupOutOfBounds,
    /// An OSC 8 open/close token, or a printable character, appeared in a
    /// position where an in-progress link span would end up empty (link
    /// opened and closed/switched with no character written under it) —
    /// something herdr's own encoder never produces (OSC 8 is only ever
    /// written immediately before a cell's character), so this is treated
    /// as fail-closed evidence of a malformed or desynced frame.
    EmptyLinkSpan,
    /// The frame ended with a link still open (herdr's own `write_all_cells`
    /// always calls `close_hyperlink` before returning, so this never
    /// happens for a well-formed frame).
    UnclosedLinkAtEndOfFrame,
    /// An OSC 8 close token fired while position was `Indeterminate` (the
    /// frame-final special case — see the module doc comment), but the
    /// active link's own row was not the frame's last row (`height - 1`).
    /// herdr's `write_all_cells` calls the unconditional frame-final
    /// `close_hyperlink` only once, strictly after every row has been
    /// written (v0.9.1 `render_ansi.rs:842-896`), so the only way this
    /// close can legitimately observe `Indeterminate` position is when the
    /// still-open link's last row is the frame's very last row — any other
    /// row is fail-closed evidence of a malformed or desynced frame (a
    /// non-final row's own trailing close would have gone through an
    /// intervening CUP first, taking the `Fixed`-position branch instead).
    IndeterminateCloseNotAtFrameEnd,
    /// A printable character was seen after an OSC 8 close already fired
    /// while position was `Indeterminate` (the frame-final special case).
    /// herdr only ever reaches that close once, strictly after the very
    /// last cell of the very last row has been written (v0.9.1
    /// `render_ansi.rs:842-896`) — nothing printable legitimately follows
    /// it, only the trailing SGR reset (`\x1b[0m`) and cursor-state block
    /// (CUP / DECSCUSR / `?25h`/`?25l`), none of which pass through the
    /// print branch. A printable character reaching this point despite an
    /// intervening CUP resetting `position` back to `Fixed` is still
    /// fail-closed evidence of a malformed or desynced frame, not a
    /// legitimate second batch of cells.
    PrintAfterFrameFinalClose,
    /// A byte sequence didn't match any recognized token (CUP / SGR / OSC 8
    /// / a known mode-toggle / ASCII print / UTF-8 print), or a printable
    /// control byte appeared outside of a recognized escape sequence.
    UnknownSequence,
    /// The frame ended in the middle of an escape sequence or OSC 8 URI.
    Truncated,
    /// The frame's bytes were not valid UTF-8 (herdr's own writer only
    /// ever emits valid UTF-8 — ASCII escape codes plus UTF-8 cell/URI
    /// text — so this itself is fail-closed evidence of corruption).
    InvalidUtf8,
}

enum Token {
    Cup(u16, u16),
    SyncStart,
    SyncEnd,
    CursorVisible(bool),
    CursorShape(u8),
    ScreenClear,
    Sgr,
    LinkOpen(String),
    /// An OSC 8 open whose URI held a C0 control byte: that link alone is
    /// excluded (see the module doc comment).
    LinkOpenInvalid,
    LinkClose,
}

/// Parses one escape sequence starting at `s[0]` (`'\u{1b}'`). Returns the
/// number of bytes consumed (from `s[0]`, inclusive) and the token.
fn parse_escape(s: &str) -> Result<(usize, Token), TrackError> {
    let bytes = s.as_bytes();
    match bytes.get(1) {
        Some(b'[') => parse_csi(s, 2),
        Some(b']') => parse_osc8(s, 2),
        Some(_) => Err(TrackError::UnknownSequence),
        None => Err(TrackError::Truncated),
    }
}

/// Parses a CSI sequence's parameters/intermediate/final byte starting at
/// byte offset `start` (right after `ESC[`). `start` is always a char
/// boundary (ESC and `[` are both single-byte ASCII).
fn parse_csi(s: &str, start: usize) -> Result<(usize, Token), TrackError> {
    let bytes = s.as_bytes();
    let mut i = start;
    let private = bytes.get(i) == Some(&b'?');
    if private {
        i += 1;
    }
    let param_start = i;
    // ':' is accepted here (not just digits/';') because SGR (final byte
    // 'm') may carry colon-separated sub-parameters — herdr emits e.g.
    // `4:3` for the underline style (confirmed via the real fixture and
    // `render_ansi.rs`). SGR is
    // read-and-ignored regardless of its parameters (see the early return
    // below, before any numeric parsing), so accepting ':' here never
    // causes a *different* token to be misparsed — only SGR's own param
    // string can legitimately contain one.
    while matches!(bytes.get(i), Some(b) if b.is_ascii_digit() || *b == b';' || *b == b':') {
        i += 1;
    }
    let params = &s[param_start..i];
    let has_space = bytes.get(i) == Some(&b' ');
    if has_space {
        i += 1;
    }
    let final_byte = *bytes.get(i).ok_or(TrackError::Truncated)?;
    i += 1;

    // SGR: read-and-ignore token, so its parameters are never
    // interpreted — this also sidesteps colon sub-parameters entirely,
    // rather than trying to parse them as plain `;`-separated integers.
    if !private && !has_space && final_byte == b'm' {
        return Ok((i, Token::Sgr));
    }

    let mut nums: Vec<u32> = Vec::new();
    if !params.is_empty() {
        for part in params.split(';') {
            let n: u32 = part.parse().map_err(|_| TrackError::UnknownSequence)?;
            nums.push(n);
        }
    }

    let token = match (private, has_space, final_byte, nums.as_slice()) {
        (false, false, b'H', []) => Token::Cup(0, 0),
        (false, false, b'H', [row, col]) if *row >= 1 && *col >= 1 => {
            let row = u16::try_from(*row - 1).map_err(|_| TrackError::CupOutOfBounds)?;
            let col = u16::try_from(*col - 1).map_err(|_| TrackError::CupOutOfBounds)?;
            Token::Cup(row, col)
        }
        (true, false, b'h', [2026]) => Token::SyncStart,
        (true, false, b'l', [2026]) => Token::SyncEnd,
        (true, false, b'h', [25]) => Token::CursorVisible(true),
        (true, false, b'l', [25]) => Token::CursorVisible(false),
        (false, false, b'J', [2]) => Token::ScreenClear,
        (false, true, b'q', [n]) => {
            Token::CursorShape(u8::try_from(*n).map_err(|_| TrackError::UnknownSequence)?)
        }
        _ => return Err(TrackError::UnknownSequence),
    };
    Ok((i, token))
}

/// Parses an OSC 8 sequence's fixed `8;;` prefix and URI body starting at
/// byte offset `start` (right after `ESC]`). A C0 control byte in the URI
/// body (other than an ESC that does not begin ST, which rejects the
/// frame) does not reject the frame: scanning continues to the terminator
/// (ST, or BEL) and the result is `Token::LinkOpenInvalid` — see the
/// module doc comment. No terminator before the end of input is
/// `Truncated`.
fn parse_osc8(s: &str, start: usize) -> Result<(usize, Token), TrackError> {
    let bytes = s.as_bytes();
    if bytes.get(start..start + 3) != Some(b"8;;") {
        return Err(TrackError::UnknownSequence);
    }
    let uri_start = start + 3;
    let mut i = uri_start;
    let mut invalid = false;
    loop {
        match bytes.get(i) {
            None => return Err(TrackError::Truncated),
            Some(&b) if b < 0x20 => {
                if b == 0x1b && bytes.get(i + 1) == Some(&b'\\') {
                    let uri = &s[uri_start..i];
                    let total = i + 2;
                    return Ok((
                        total,
                        if invalid {
                            Token::LinkOpenInvalid
                        } else if uri.is_empty() {
                            Token::LinkClose
                        } else {
                            Token::LinkOpen(uri.to_owned())
                        },
                    ));
                }
                if b == 0x07 {
                    return Ok((i + 1, Token::LinkOpenInvalid));
                }
                if b == 0x1b {
                    // An ESC that is not the start of ST: the sequence is
                    // unterminated or the stream has desynced, so what
                    // follows (a CUP, text) must not be swallowed as URI
                    // bytes -- reject the frame.
                    return Err(TrackError::UnknownSequence);
                }
                invalid = true;
                i += 1;
            }
            Some(_) => i += 1,
        }
    }
}

fn require_position(position: Position) -> Result<(u16, u16), TrackError> {
    match position {
        Position::Fixed { row, col } => Ok((row, col)),
        Position::Indeterminate { .. } => Err(TrackError::PrintWithoutPosition),
    }
}

/// Finalizes one link span, closing at `end_col` (inclusive). Rejects
/// (`EmptyLinkSpan`) rather than emitting a span with `end_col < start_col`
/// — see `TrackError::EmptyLinkSpan`.
fn push_span(
    spans: &mut Vec<RawLinkSpan>,
    row: u16,
    start_col: u16,
    end_col: u16,
    url: String,
) -> Result<(), TrackError> {
    if end_col < start_col {
        return Err(TrackError::EmptyLinkSpan);
    }
    spans.push(RawLinkSpan {
        row,
        start_col,
        end_col,
        url,
    });
    Ok(())
}

/// Closes `active_link` (if any) against the current `(row, col)` — the
/// position of the OSC 8 open/close token doing the closing. Used by both
/// `LinkOpen` (switching links) and `LinkClose`.
///
/// If the link's row differs from `row`, the link silently continued
/// across one or more row-changing CUPs with **no character ever written
/// under it** before this close/switch fired (herdr's own
/// `write_hyperlink_if_changed` never re-emits OSC 8 for a link that is
/// already active, so a row-changing CUP alone is not proof that printing
/// actually resumed — see the real v22 fixture's `wrapped-long-url`
/// case, where the link's last row wraps to a new row via CUP and the very
/// next token is an unrelated close, with zero chars written on the new
/// row). In that case the span closes on its **own** last row at
/// `width - 1` and no
/// span is emitted for the new row — there is nothing to represent there.
/// When the link *does* continue with real text on the new row, that is
/// handled separately, in `track_frame`'s printable-character branch,
/// which reopens a fresh span at the first character actually written
/// there (see its comment).
fn close_active_link(
    active_link: &mut Option<(u16, u16, String)>,
    spans: &mut Vec<RawLinkSpan>,
    row: u16,
    col: u16,
    width: u16,
) -> Result<(), TrackError> {
    if let Some((lrow, lstart, lurl)) = active_link.take() {
        let end_col = if lrow == row {
            col.checked_sub(1).ok_or(TrackError::EmptyLinkSpan)?
        } else {
            width - 1
        };
        push_span(spans, lrow, lstart, end_col, lurl)?;
    }
    Ok(())
}

/// Whether `c` is a codepoint that attaches to whatever immediately
/// precedes it within the same grapheme cluster/cell, rather than starting
/// a new one — the specific ranges UAX #29's GB9 ("Extend"), GB9a
/// ("SpacingMark" for the relevant symbol-combining case), and GB11 (ZWJ
/// emoji sequences) rules cover for the cases this crate actually needs to
/// recognize: combining diacritical marks (and their extended/supplement
/// blocks, plus the combining half marks block used for multi-character
/// diacritics), combining marks for symbols (includes U+20E3 COMBINING
/// ENCLOSING KEYCAP), variation selectors (includes U+FE0F, forcing
/// emoji-style presentation), the variation selector supplement block, ZWJ
/// (emoji ZWJ sequences), emoji skin-tone modifiers, and the tag block
/// (used by tag-sequence emoji such as regional-indicator-less flag
/// sequences, e.g. England/Scotland/Wales). There is no Unicode-data crate
/// dependency available to consult the full Grapheme_Cluster_Break property
/// table (only `serde`/`bincode`/`serde_json` are dependencies of this
/// crate), so this is a targeted allow-list rather than a complete
/// implementation of UAX #29 — scoped to cover every case this module's own
/// tests and examples (keycap "1️⃣" = U+0031 + U+FE0F +
/// U+20E3, decomposed "é" = 'e' + U+0301) exercise, not a general-purpose
/// grapheme segmenter.
/// Used only for an ASCII base character's own trailing continuation (see
/// `track_frame`'s print branch) — a non-ASCII base's trailing consumption
/// does not need this distinction (see that branch's own comment for why).
fn is_grapheme_continuation(c: char) -> bool {
    matches!(c,
        '\u{0300}'..='\u{036F}'   // Combining Diacritical Marks
        | '\u{1AB0}'..='\u{1AFF}' // Combining Diacritical Marks Extended
        | '\u{1DC0}'..='\u{1DFF}' // Combining Diacritical Marks Supplement
        | '\u{20D0}'..='\u{20FF}' // Combining Diacritical Marks for Symbols (incl. U+20E3)
        | '\u{FE00}'..='\u{FE0F}' // Variation Selectors (incl. U+FE0F)
        | '\u{FE20}'..='\u{FE2F}' // Combining Half Marks
        | '\u{E0100}'..='\u{E01EF}' // Variation Selectors Supplement
        | '\u{E0020}'..='\u{E007F}' // Tags (tag-sequence emoji, e.g. regional flags)
        | '\u{200D}'              // ZERO WIDTH JOINER
        | '\u{1F3FB}'..='\u{1F3FF}' // Emoji skin-tone modifiers
    )
}

/// Tracks one full-redraw `TerminalAnsi` frame's bytes,
/// producing per-row display text and raw (unaggregated) link spans, or
/// rejecting per `TrackError` (always surfaced as `render_rejected` by
/// callers). `width`/`height` are the frame's declared dimensions
/// (`TerminalFrame.width`/`.height`) — `bytes` is `TerminalFrame.bytes`
/// (only ever called when `TerminalFrame.full == true`; see the module doc
/// comment).
pub fn track_frame(bytes: &[u8], width: u16, height: u16) -> Result<TrackedFrame, TrackError> {
    let text = std::str::from_utf8(bytes).map_err(|_| TrackError::InvalidUtf8)?;
    let mut pos = 0usize;
    let mut position = Position::Indeterminate { start_col: 0 };
    let mut rows: Vec<String> = vec![String::new(); height as usize];
    let mut active_link: Option<(u16, u16, String)> = None;
    let mut spans: Vec<RawLinkSpan> = Vec::new();
    let mut cursor_position: Option<(u16, u16)> = None;
    let mut cursor_visible: Option<bool> = None;
    let mut cursor_shape: Option<u8> = None;
    // Set once an OSC 8 close has fired while `position` was `Indeterminate`
    // (the frame-final special case below) — herdr only ever reaches that
    // close once, strictly after the frame's very last cell, so nothing
    // printable may legitimately follow it afterward, even if a later CUP
    // resets `position` back to `Fixed` (see `TrackError::
    // PrintAfterFrameFinalClose`'s doc comment).
    let mut frame_tail_link_closed = false;

    while pos < text.len() {
        let rest = &text[pos..];
        let ch0 = rest.chars().next().expect("pos < text.len()");
        if ch0 == '\u{1b}' {
            let (consumed, token) = parse_escape(rest)?;
            pos += consumed;
            match token {
                Token::Cup(row, col) => {
                    if row >= height || col >= width {
                        return Err(TrackError::CupOutOfBounds);
                    }
                    // No link-state action here: a row-changing CUP alone
                    // does not prove a still-open link continues onto the
                    // new row (see `close_active_link`'s doc comment). The
                    // decision is made lazily, either when the link is
                    // actually closed/switched (`close_active_link`'s
                    // row-comparison) or when a print resumes on the new
                    // row (below).
                    position = Position::Fixed { row, col };
                    cursor_position = Some((row, col));
                }
                Token::SyncStart | Token::SyncEnd | Token::ScreenClear | Token::Sgr => {}
                Token::CursorVisible(v) => cursor_visible = Some(v),
                Token::CursorShape(n) => cursor_shape = Some(n),
                Token::LinkOpen(url) => {
                    let (row, col) = require_position(position)?;
                    close_active_link(&mut active_link, &mut spans, row, col, width)?;
                    active_link = Some((row, col, url));
                }
                Token::LinkOpenInvalid => {
                    let (row, col) = require_position(position)?;
                    close_active_link(&mut active_link, &mut spans, row, col, width)?;
                }
                Token::LinkClose => {
                    match position {
                        Position::Fixed { row, col } => {
                            close_active_link(&mut active_link, &mut spans, row, col, width)?;
                        }
                        Position::Indeterminate { start_col: _ } => {
                            // The frame-final `close_hyperlink` call
                            // (unconditional, no CUP, no following print —
                            // see the module doc comment) can legitimately
                            // fire right here, but *only* once every row has
                            // been fully written: `write_all_cells` (v0.9.1
                            // `render_ansi.rs:842-896`) writes every column
                            // of every row before calling it exactly once,
                            // strictly after the outer row loop. So the
                            // still-open link's own last row must be the
                            // frame's very last row (`height - 1`) — any
                            // other row is fail-closed evidence of a
                            // malformed/desynced frame. And
                            // because that same write always covers through
                            // the frame's last column (a cell reaching the
                            // frame's right edge, possibly via its own
                            // double-wide `skip` continuation), the correct
                            // end column is always `width - 1`, not this
                            // cell's own `start_col` — using `start_col`
                            // under-counted a multi-column cell's own right
                            // half.
                            // herdr also writes this same empty-URI OSC 8
                            // close unconditionally at the very *start* of
                            // every frame, before any cell/CUP, purely to
                            // reset stale OSC 8 state ("Start each frame
                            // from a known OSC 8 state" —
                            // `blit_frame_to_with_cursor_memory_and_clear_
                            // policy`, v0.9.1 `render_ansi.rs:685-687`;
                            // confirmed present in the real v22 fixture's
                            // first 21 bytes). With no link ever opened yet,
                            // `active_link` is `None` there — that harmless
                            // no-op is not the frame-final special case at
                            // all, so it must not set the tail-closed flag
                            // or be checked against `height - 1`.
                            if let Some((lrow, lstart, lurl)) = active_link.take() {
                                if lrow != height - 1 {
                                    return Err(TrackError::IndeterminateCloseNotAtFrameEnd);
                                }
                                push_span(&mut spans, lrow, lstart, width - 1, lurl)?;
                                frame_tail_link_closed = true;
                            }
                        }
                    }
                }
            }
        } else {
            // Nothing printable may legitimately follow the frame-final
            // Indeterminate-position link close (see `TrackError::
            // PrintAfterFrameFinalClose`'s doc comment) — checked before
            // even the control-byte check below, since neither a control
            // byte nor an ordinary printable character can legitimately
            // appear here once that close has fired.
            if frame_tail_link_closed {
                return Err(TrackError::PrintAfterFrameFinalClose);
            }
            if ch0.is_control() {
                return Err(TrackError::UnknownSequence);
            }
            let (row, col) = require_position(position)?;
            if row >= height || col >= width {
                return Err(TrackError::CupOutOfBounds);
            }
            // A link that was active on an earlier row and silently
            // continued across a row-changing CUP (no OSC 8 token in
            // between — see `close_active_link`'s doc comment) is only
            // confirmed to continue once we see it: the first character
            // actually written on the new row. Close its old-row span at
            // `width - 1` and reopen a fresh span for the same URL
            // starting exactly here.
            if let Some((lrow, lstart, lurl)) = active_link.take() {
                if lrow == row {
                    active_link = Some((lrow, lstart, lurl));
                } else {
                    push_span(&mut spans, lrow, lstart, width - 1, lurl.clone())?;
                    active_link = Some((row, col, lurl));
                }
            }
            // Consume this cell's grapheme cluster: `ch0` itself, plus
            // whatever trails it in the same `write_all(cell.symbol.
            // as_bytes())` call (see the module doc comment). The rule for
            // *what* trails it differs by `ch0`'s own ASCII-ness, because
            // herdr's CUP-omission condition itself is asymmetric
            // (`next_inline_col = (cell.symbol.is_ascii() && width==1)
            // .then_some(col+1)`, `render_ansi.rs`'s `write_all_cells`):
            //
            // - `ch0` non-ASCII: `cell.symbol` can never be all-ASCII
            //   again, so herdr always CUPs before whatever comes next --
            //   meaning *any* further non-ASCII character seen here with no
            //   intervening CUP cannot be a genuinely new, separate cell
            //   (that would have needed its own CUP); it can only be this
            //   same cell's own trailing codepoint. Consuming every
            //   following non-ASCII character (stopping at ASCII/ESC/
            //   control) is therefore safe and lossless.
            // - `ch0` ASCII: `cell.symbol` (so far just `ch0`) *is*
            //   all-ASCII, so herdr's CUP-omission condition already holds
            //   for `ch0` alone -- a genuinely new, separate cell (ASCII or
            //   not; e.g. "B" immediately followed by unrelated CJK "あ",
            //   both real, distinct cells) can legitimately follow with no
            //   CUP too. So "any following non-ASCII char" is *not* a safe
            //   trailing-continuation test here; only an actual grapheme
            //   *continuation* codepoint (`is_grapheme_continuation`, e.g.
            //   a combining accent, variation selector, ZWJ, or enclosing/
            //   modifier mark) may be folded into `ch0`'s own cell.
            //
            // This ASCII-base case was verified
            // against herdr's source, not assumed: keycap "1️⃣" (U+0031 '1'
            // + U+FE0F + U+20E3) and decomposed "é" ('e' + U+0301) both
            // attach their trailing combining codepoints to the *same*
            // cell regardless of the base codepoint's ASCII-ness. herdr
            // does not build cells itself — `pane/terminal.rs`'s
            // `ghostty_buffer_symbol_into` reads each cell's full grapheme
            // text via `RowCellIter::grapheme_text_into`
            // (`src/ghostty/mod.rs:3564`), an FFI call into libghostty's own
            // per-cell grapheme storage (`GHOSTTY_RENDER_STATE_ROW_CELLS_
            // DATA_GRAPHEMES_UTF8`); the `vte`/`unicode-segmentation` crates
            // are not used for PTY grid emulation (`unicode-segmentation`
            // appears only in `client/shell/text_editor.rs`, an unrelated
            // line editor). So a cell's grapheme boundary is decided by
            // libghostty before herdr ever sees it, following the same
            // continuation codepoints UAX #29 does (GB9/GB9a/GB11): a
            // combining mark, variation selector, ZWJ, or modifier always
            // attaches to whatever came immediately before it, ASCII or
            // not -- `is_grapheme_continuation` below is scoped to exactly
            // those codepoints.
            rows[row as usize].push(ch0);
            pos += ch0.len_utf8();
            let mut trailing_continuation = false;
            while pos < text.len() {
                let c = text[pos..].chars().next().expect("pos < text.len()");
                let continues = if ch0.is_ascii() {
                    is_grapheme_continuation(c)
                } else {
                    c != '\u{1b}' && !c.is_control() && !c.is_ascii()
                };
                if !continues {
                    break;
                }
                rows[row as usize].push(c);
                pos += c.len_utf8();
                trailing_continuation = true;
            }
            position = if ch0.is_ascii() && !trailing_continuation {
                // A pure single ASCII, width-1 cell, with no trailing
                // combining continuation (herdr's own CUP-omission
                // condition — see the module doc comment): position stays
                // `Fixed`, one column forward, so the *next* print can
                // continue without a fresh CUP.
                Position::Fixed { row, col: col + 1 }
            } else {
                // Either a non-ASCII base cell, or an ASCII base with a
                // trailing grapheme continuation -- either way the real
                // `cell.symbol` is not all-ASCII, so herdr's own
                // `next_inline_col` is `None` and the *next* cell always
                // gets an explicit CUP; the exact end column is herdr's to
                // know, not ours.
                Position::Indeterminate { start_col: col }
            };
        }
    }

    if active_link.is_some() {
        return Err(TrackError::UnclosedLinkAtEndOfFrame);
    }

    Ok(TrackedFrame {
        rows,
        links: spans,
        cursor_position,
        cursor_visible,
        cursor_shape,
    })
}
