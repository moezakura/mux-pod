# 004 Custom Key Buttons — Spec

Status: approved (design Q&A) / implementation pending
Date: 2026-08-21
Branch: feat/custom-key-buttons

## Problem

The special keys bar (`lib/widgets/special_keys_bar.dart`) is hard-coded: rows of
fixed buttons (ESC/TAB/CTRL/ALT/SHIFT/ENTER/S-RET, `/`, `-`, navigation keys, the
Cmd input button). Users cannot add their own buttons or multi-step actions
(e.g. type `/models` then press Enter).

## Goal

Let the user define custom buttons and lay out the special keys bar freely: any
button — custom or standard — can sit in any row at any position, or be parked
out of the bar entirely. Each custom button executes an ordered sequence of
steps: literal text, special key (tmux key name), or pause.

## Decisions (from design Q&A)

1. **Placement**: the bar is an ordered list of rows the user builds. The
   default layout is three rows — an empty custom row on top, then the modifier
   row and the navigation row at their historical contents. Rows can be added
   ("+ Add row", up to `CustomKeyRows.maxRows` = 6) and deleted. Any token
   (standard or custom) may be placed in any row at any index, and tokens the
   user does not want are parked on an "Unused" shelf that is derived from the
   rows, not stored.
2. **Action model**: a button is an ordered list of steps — `text` / `key` /
   `pause`. Example: `[text: "/models", key: "Enter"]`.
3. **Editing UX**: full editor reachable from the Settings screen (new section)
   AND from the terminal via a pencil button on the bar; layout is edited by
   long-press drag-and-drop of chips between the row strips and the shelf;
   tapping a custom chip opens the editor dialog for that button.
4. **Persistence**: global (shared_preferences), like other settings.
5. **Architecture**: token-list rows (approach A) — each row is an ordered list
   of tokens: stable standard-key ids + custom-button ids.
6. **Overflow**: a row that exactly equals its historical default renders on the
   legacy path (`Row` of `Expanded`, byte-identical to before); any other row
   renders through one generic token renderer inside a horizontal
   `SingleChildScrollView` with fixed-width buttons, so free insertion can never
   squeeze the row. An empty row renders nothing, which is how a user hides a
   whole row.

## Non-goals (YAGNI)

- No per-connection button sets (global only).
- No macros beyond the step types (no loops, no shell commands on device).
- No reordering of the button *library* list (position is defined by row
  tokens, not list order).
- No editing of standard buttons (labels/keys of standard buttons stay fixed).
- No direct-input row layout editing: `input` / `num1..num4` / `di_toggle` are
  ordinary tokens, but which of them render is still decided by direct-input
  mode.

## Architecture

```
Settings screen ──> CustomKeysScreen (full editor)
                        │ add/edit/delete + drag-and-drop layout
                        ▼
CustomKeysNotifier (Riverpod, shared_preferences)
                        │  buttons + row0/row1/row2 tokens
                        ▼
TerminalScreen ──> SpecialKeysBar ──> CustomKeyButtonWidget (render+execute)
                        │                 │ tap → steps via onKeyPressed /
                        │                 │       onSpecialKeyPressed
                        └── pencil ───────┘ long-press → editor dialog
```

### Components

| Component | File | Responsibility |
|---|---|---|
| Model | `lib/services/custom_keys/custom_key_button.dart` | step types, button model, JSON (de)serialization, standard-key id table, default row layouts, token validation |
| Provider | `lib/providers/custom_keys_provider.dart` | `CustomKeysState` (buttons + row0/row1/row2), CRUD, `placeToken` / `setRowTokens`, derived `unusedTokens()`, persistence in shared_preferences, two one-time layout migrations |
| Bar widget | `lib/widgets/special_keys_bar.dart` (modify) | new params (`customButtons`, `row0Tokens`, `row1Tokens`, `row2Tokens`, `onCustomButtonEdit`, `onManageButtons`); one generic token renderer for every row, legacy fast path only for an exactly-default row; empty rows vanish; pencil pinned to row 1 (or the first non-empty row) |
| Button widget | `lib/widgets/custom_key_button_widget.dart` | renders one custom button (amber accent), tap → sequential step execution, long-press → edit callback, re-entry guard |
| Editor dialog | `lib/widgets/dialogs/custom_key_button_editor_dialog.dart` | add/edit a button: label + ordered step list (type dropdown, value field, move up/down, delete, add step), optional Delete with confirmation |
| Editor screen | `lib/screens/custom_keys/custom_keys_screen.dart` | full editor: buttons library (add/edit/delete) + drag-and-drop strips for the custom row, row 1, row 2 and the Unused shelf |
| Settings entry | `lib/screens/settings/settings_screen.dart` (modify) | new section tile → CustomKeysScreen |
| Terminal wiring | `lib/screens/terminal/terminal_screen.dart` (modify) | watch the provider inside the bar's `Consumer`, pass data + edit callbacks to the bar |

## Data model (summary — see data-model.md)

- `CustomKeyStep { type: text|key|pause, value: String }` — `value` is the
  literal text, the tmux key name (Enter, Escape, C-c, BSpace, S-Enter, …), or
  the pause duration in milliseconds (as string, e.g. "300").
- `CustomKeyButton { id, label, steps: List<CustomKeyStep> }` — `id` is a
  stable unique string generated at creation (`ck_<epochMs>_<rand>`).
- Row layout: `List<String>` of tokens. Standard tokens are stable ids:
  - Row 0 (custom row): empty by default.
  - Row 1: `esc tab ctrl alt shift enter senter slash dash`
  - Row 2: `pgup pgdn left up down right image di_toggle input`
    (`input` renders only in normal mode; `num1..num4` render only in
    direct-input mode — mode-dependent standard tokens that are not renderable
    in the current mode are skipped, in every row).
  - Custom tokens are prefixed `ck:` (e.g. `ck:1234_ab`), unambiguous against
    standard ids.
- Unplaced tokens are derived (`CustomKeysState.unusedTokens()`), never stored:
  every standard token plus every custom button that no row references, in
  canonical order.
- Persistence keys: `custom_key_buttons_v1` (JSON array of buttons),
  `custom_key_row0_v1`, `custom_key_row1_v1`, `custom_key_row2_v1` (JSON arrays
  of tokens) and the marker `custom_keys_shelf_v1`. Absent keys → defaults.
- Two one-time migrations on load: (a) no `custom_key_row0_v1` → custom tokens
  found in row 1/row 2 move into row 0; (b) a row 2 that differs from the
  default and lacks `num1..num4` gets them appended once. Note that `_persist()`
  writes every row key on every load, so "key present" must never be read as
  "the user customized this row".

## Behavior details

### Rendering

- **Default row** (exactly equal to that row's default token list): unchanged
  `Row` of `Expanded` buttons — byte-identical to the pre-feature layout.
- **Any other row**: `SingleChildScrollView(horizontal)` containing a `Row` of
  fixed-width buttons produced by one generic token renderer, so a standard
  token renders the same in every row. Standard widths: ESC/TAB ≈ 40,
  CTRL/ALT ≈ 44, SHIFT ≈ 48, ENTER/S-RET ≈ 56, `/`/`-` ≈ 32, nav 36×36;
  custom buttons get label-based width (min 44, max 96, ellipsis).
- **Empty row**: renders nothing — this is how the user hides a row.
- **Custom button styling**: same base as `_buildSpecialKeyButton` but with
  `DesignColors.secondary` (amber) border/text — distinct from the cyan
  `primary` used by ENTER. Labels render on one line with `TextOverflow.ellipsis`.
- **Pencil button**: fixed icon button (`Icons.edit_outlined`) pinned outside
  the scroller at the end of the FIRST row that renders anything — the top row
  is the custom row, so it sits next to the user's own buttons. When no row
  renders (every row empty, or no rows at all) the bar draws a pencil-only
  strip, so the entry point never disappears and is never rendered twice.
  Tap → `onManageButtons()` (opens the full editor).
- **Auto-scroll**: when a row grows, it scrolls to reveal the new token — to the
  start when the token was prepended, to the end when appended.

### Execution

- Tap on a custom button → haptic (if enabled) → reset software modifier
  toggles (CTRL/ALT/SHIFT) → execute steps in order:
  - `text`: `onKeyPressed(value)`
  - `key`: `onSpecialKeyPressed(value)`
  - `pause`: `await Future.delayed(Duration(milliseconds: int.parse(value)))`
- Step sends are enqueued in order through the existing callbacks; the backend
  (PaneWriter/SSH queue) is FIFO, so ordering is preserved. Pauses delay the
  enqueue of the following step.
- Re-entry guard: an in-flight execution is tracked; taps during execution are
  ignored (a long pause sequence cannot be double-triggered).
- No key overlay per step (bulk actions would be noisy).
- Modifier toggles are NOT applied to custom steps and are reset on tap.

### Editor

- **Full editor (CustomKeysScreen)**:
  - Section "Buttons": list of custom buttons (label + step summary, e.g.
    `"/models" + Enter`), tap → edit dialog, delete via trailing button,
    header "+ Add button" → add dialog, and the new button is placed at the head
    of the custom row so it is visible immediately.
  - Sections "Layout — Row N" (1-based from the top, one per row) and "Unused":
    each is a strip of chips. Each row header carries a delete button, and a
    "+ Add row" tile after the last strip appends an empty row (disabled at
    `CustomKeyRows.maxRows`). Deleting a row does not delete its buttons: its
    tokens simply return to the shelf. Every chip (standard or custom) is
    long-press draggable; per-index drop slots between chips place the token at
    that exact index, and dropping on a strip's free area appends. Dragging a
    chip onto "Unused" removes it from the bar. Strips wrap onto multiple lines
    (never a horizontal scroller) because scrolling is impossible mid-drag and
    an off-screen slot would be unreachable. Tapping a custom chip opens its
    editor dialog.
  - Validation: label non-empty; at least one step; text/key step values
    non-empty (trimmed); pause value is a positive integer. Invalid → inline
    error, no save. Empty text/key steps are rejected because a persisted
    empty step would make the button unparseable on next load (defense in
    depth: the loader below also drops such entries).
  - Delete of a button also removes its tokens from every row.
- **Quick edit (long-press)**: the same `CustomKeyButtonEditorDialog`,
  pre-filled, launched from the terminal screen with the button's data.

### Settings entry

New section header `Buttons` with a single `ListTile` ("Custom Buttons",
subtitle "Add buttons and action sequences to the key bar") → pushes
`CustomKeysScreen`. Placed after the existing Key Overlay section.

## Error handling

- Corrupt persisted JSON: a wholly unparseable buttons value (or a non-array)
  falls back to an empty list; a partially invalid array drops only the
  invalid entries and keeps the valid ones (drop-bad-keep-good — one corrupt
  button must not wipe the rest). Corrupt row values fall back to the default
  row. Never crashes startup.
- Unknown tokens in a row (button deleted, or id collision): skipped at render.
- Pause parse failure at execution: step skipped, sequence continues (defensive
  against hand-edited data; validation trims the value, execution trims too).
- Read-only terminal (`_ReadOnlyBanner` shown): bar hidden entirely; pencil and
  custom buttons not reachable (existing behavior).

## Testing

- **Unit — model** (`test/services/custom_keys/custom_key_button_test.dart`):
  JSON round-trip for all step types; corrupt JSON → default; token prefix
  validation; standard-id table completeness.
- **Unit — provider** (`test/providers/custom_keys_provider_test.dart`):
  defaults when keys absent; add/update/delete persist; delete removes row
  tokens from every row; `setRowTokens` drops unknown/duplicate tokens;
  `placeToken` index arithmetic (head, same-row shift, shelf, unknown token);
  `unusedTokens()` canonical order; both migrations, including that a persisted
  default row 2 is left alone; SharedPreferences mock.
- **Widget — bar** (`test/widgets/special_keys_bar_test.dart`, extend): default
  layout unchanged (existing tests keep passing); a standard token renders in
  the custom row and a custom token renders in row 2; a reordered row honours
  its order; an empty row vanishes and the pencil moves to the first non-empty
  row; numbers are not auto-appended; a row scrolls to a newly prepended or
  appended token; long-press fires the edit callback; tap executes steps in
  order exactly once; modifier reset on custom tap.
- **Widget — editor dialog**: label/step validation; step add/reorder/delete;
  Delete with confirmation (confirm and cancel); layout survives a 2× text
  scale and a 308dp-wide dialog (actions on one row, labels not clipped).
- **Widget — editor screen**: buttons CRUD; drag between rows, within a row, to
  and from the Unused shelf; delete removes the token; persistence through the
  provider.
- **Gate**: `flutter analyze` clean; full `flutter test` green apart from the
  suite's known pre-existing failures.

## Verification

- `flutter analyze` — no issues.
- Full `flutter test` suite (existing + new).
- Manual smoke on a device: add a button `/models` + `Enter`, drag it and a
  standard key between rows and onto the Unused shelf, verify the bar matches
  the editor, that both send on tap, and that the layout survives a restart.
