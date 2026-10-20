//! Row fingerprinting for OSC 8 hyperlink row-mismatch suppression.
//!
//! Pure functions only — no I/O, no protocol dependency. This is the Rust
//! half of a function that is also ported to Dart; both implementations
//! must produce byte-identical output for byte-identical input. The exact
//! algorithm and a shared set of test vectors are captured in
//! `testdata/fingerprint_vectors.json`, which this module's
//! tests also load and cross-check against.

const FNV1A64_OFFSET_BASIS: u64 = 0xcbf29ce484222325;
const FNV1A64_PRIME: u64 = 0x100000001b3;

/// 64-bit FNV-1a hash of `bytes`.
fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash = FNV1A64_OFFSET_BASIS;
    for &byte in bytes {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(FNV1A64_PRIME);
    }
    hash
}

/// `fnv1a64` formatted as a zero-padded 16-digit lowercase hex string
/// (`rowHashes` / `rowFingerprints` are zero-padded 16-digit lowercase hex
/// strings).
pub fn fnv1a64_hex(bytes: &[u8]) -> String {
    format!("{:016x}", fnv1a64(bytes))
}

/// Row fingerprint for the row-mismatch suppression rule.
///
/// `display_text` must already be the row's display string (the written
/// cells' characters concatenated; no double-wide
/// continuation cells). This function performs only the
/// normalization — stripping trailing U+0020 (space) characters — and then
/// hashes the remaining string's UTF-8 bytes. Returns `None` when the
/// string is empty after stripping: an empty row has no fingerprint.
pub fn row_fingerprint(display_text: &str) -> Option<String> {
    let trimmed = display_text.trim_end_matches('\u{0020}');
    if trimmed.is_empty() {
        None
    } else {
        Some(fnv1a64_hex(trimmed.as_bytes()))
    }
}

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

#[cfg(test)]
mod grammar_tests {
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
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;
    use std::fs;
    use std::path::Path;

    // Well-known FNV-1a-64 reference vectors (http://www.isthe.com/chongo/tech/comp/fnv/),
    // used to verify this from-scratch implementation independently of any
    // Herdr-specific behavior.
    #[test]
    fn fnv1a64_hex_matches_well_known_reference_vectors() {
        assert_eq!(fnv1a64_hex(b""), "cbf29ce484222325");
        assert_eq!(fnv1a64_hex(b"a"), "af63dc4c8601ec8c");
        assert_eq!(fnv1a64_hex(b"foobar"), "85944171f73967e8");
    }

    #[test]
    fn row_fingerprint_ascii() {
        assert_eq!(
            row_fingerprint("hello world"),
            Some(fnv1a64_hex(b"hello world"))
        );
    }

    #[test]
    fn row_fingerprint_strips_trailing_space_only() {
        // Trailing U+0020 is stripped; a trailing tab or other whitespace is
        // not (only U+0020 is specified, not "whitespace" broadly).
        assert_eq!(row_fingerprint("hello   "), Some(fnv1a64_hex(b"hello")));
        assert_eq!(
            row_fingerprint("hello\t"),
            Some(fnv1a64_hex("hello\t".as_bytes()))
        );
    }

    #[test]
    fn row_fingerprint_whitespace_only_row_has_no_fingerprint() {
        assert_eq!(row_fingerprint("   "), None);
        assert_eq!(row_fingerprint(""), None);
    }

    #[test]
    fn row_fingerprint_cjk_fullwidth() {
        let text = "こんにちは";
        assert_eq!(row_fingerprint(text), Some(fnv1a64_hex(text.as_bytes())));
    }

    #[test]
    fn row_fingerprint_combining_character() {
        // "e" + COMBINING ACUTE ACCENT (U+0301), not the precomposed U+00E9.
        let text = "cafe\u{0301}";
        assert_eq!(row_fingerprint(text), Some(fnv1a64_hex(text.as_bytes())));
    }

    #[derive(Deserialize)]
    struct FingerprintVector {
        #[serde(rename = "displayText")]
        display_text: String,
        #[serde(rename = "fingerprint")]
        fingerprint: Option<String>,
    }

    /// Cross-checks `row_fingerprint` against the shared test vectors
    /// (`testdata/fingerprint_vectors.json`) that the Dart port
    /// also consumes, so both implementations are pinned to the
    /// same fixed values rather than only to each other's source code.
    #[test]
    fn row_fingerprint_matches_shared_fingerprint_vectors_json() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("testdata/fingerprint_vectors.json");
        let raw = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
        let vectors: Vec<FingerprintVector> =
            serde_json::from_str(&raw).expect("fingerprint_vectors.json must be a JSON array");
        assert!(
            !vectors.is_empty(),
            "fingerprint_vectors.json must not be empty"
        );
        for vector in &vectors {
            assert_eq!(
                row_fingerprint(&vector.display_text),
                vector.fingerprint,
                "mismatch for displayText {:?}",
                vector.display_text
            );
        }
    }
}
