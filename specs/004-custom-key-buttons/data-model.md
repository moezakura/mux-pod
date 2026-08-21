# 004 Custom Key Buttons — Data Model

## CustomKeyStepType

```dart
enum CustomKeyStepType { text, key, pause }
```

## CustomKeyStep

Immutable. One step of a button action.

```dart
class CustomKeyStep {
  final CustomKeyStepType type;
  final String value; // text: literal string; key: tmux key name; pause: ms as string
}
```

Serialized (JSON object):

```json
{ "type": "text" | "key" | "pause", "value": "…" }
```

Semantics per type:

| type | value | example | send path |
|---|---|---|---|
| `text` | literal string, sent as typed text | `"/models"` | `onKeyPressed(value)` |
| `key` | tmux key name (same vocabulary as the bar's special keys) | `"Enter"`, `"Escape"`, `"C-c"`, `"S-Enter"`, `"BSpace"` | `onSpecialKeyPressed(value)` |
| `pause` | positive integer, milliseconds | `"300"` | `await Future.delayed(Duration(milliseconds: int.parse(value)))` |

Validation: `text`/`key` → non-empty trimmed value; `pause` → positive integer.

## CustomKeyButton

```dart
class CustomKeyButton {
  final String id;          // 'ck_' + epochMilliseconds + '_' + 4-hex rand, generated at creation
  final String label;       // displayed on the button; non-empty after trim
  final List<CustomKeyStep> steps; // non-empty
}
```

Serialized (JSON object):

```json
{
  "id": "ck_1755820000000_a1b2",
  "label": "/models",
  "steps": [
    { "type": "text", "value": "/models" },
    { "type": "key",  "value": "Enter" }
  ]
}
```

## Row layout tokens

A row is `List<String>` of tokens. Standard tokens are the stable ids below;
custom tokens carry the `ck:` prefix (e.g. `"ck:1755820000000_a1b2"`), so the
two namespaces cannot collide.

### Standard key id table

Row 1 (modifier row), in canonical order:

```
esc  tab  ctrl  alt  shift  enter  senter  slash  dash
```

Row 2 (navigation row), in canonical order:

```
pgup  pgdn  left  up  down  right  image  di_toggle  input
```

Direct-input-mode extras (render only when `directInputEnabled`):

```
num1  num2  num3  num4
```

Mode-dependent standard tokens that cannot render in the current mode are
skipped at render time (`input` in direct mode; `num1..num4` in normal mode).

### Default rows

```dart
row0 = <String>[]  // dedicated custom row, top of the bar
row1 = ['esc','tab','ctrl','alt','shift','enter','senter','slash','dash']
row2 = ['pgup','pgdn','left','up','down','right','image','di_toggle','input']
```

`num1..num4` belong to no default row: they are unplaced (Unused) until the
user drags them in, and they only render while direct input is on.

### Token validation

- Token is valid iff it is a standard id (in the table above) or starts with
  `ck:` and its suffix matches an existing button id.
- Unknown tokens (deleted button, corrupt data) are skipped at render and
  removed on next save.
- Any token may sit in any row at any index. Nothing is pinned: a standard token
  can be reordered, moved to another row, or parked on the Unused shelf.

## Persistence (shared_preferences)

| key | content |
|---|---|
| `custom_key_buttons_v1` | JSON array of button objects |
| `custom_key_row0_v1` | JSON array of tokens (custom row) |
| `custom_key_row1_v1` | JSON array of tokens |
| `custom_key_row2_v1` | JSON array of tokens |
| `custom_keys_shelf_v1` | bool marker: the num-token migration already ran |

Absent key → default (empty buttons, default rows). Corrupt value: wholly
unparseable / non-array → default; partially invalid array → drop only the
invalid entries, keep the valid ones (a single corrupt button must not wipe
the rest).

The Unused shelf has no key of its own — it is derived from the rows, so the
stored layout can never disagree with what the shelf shows.

`_persist()` writes every row key on every load. Therefore the presence of a
row key says nothing about whether the user ever customized that row; the
num-token migration compares the row against its default (`listEquals`) instead.

### One-time migrations (on load)

1. No `custom_key_row0_v1`: custom tokens found in row 1 / row 2 are hoisted
   into row 0 (layouts written before the dedicated custom row existed).
2. `custom_keys_shelf_v1` unset, row 2 differs from its default, and row 2 has
   no `num1..num4`: append them once. Older builds injected the numbers at
   render time; making them real tokens keeps them draggable.

## State (provider)

```dart
class CustomKeysState {
  final List<CustomKeyButton> buttons;
  final List<String> row0;
  final List<String> row1;
  final List<String> row2;
  // helpers:
  CustomKeyButton? buttonById(String id);
  List<CustomKeyButton> unplacedButtons();  // library minus every row
  List<String> unusedTokens();              // standard + custom, canonical order
}
```

Provider API (`CustomKeysNotifier extends Notifier<CustomKeysState>`):

```dart
CustomKeyButton addButton(String label, List<CustomKeyStep> steps);
void updateButton(String id, {required String label, required List<CustomKeyStep> steps});
void deleteButton(String id);            // removes ck: tokens from every row
void setRowTokens(int row, List<String> tokens); // row: 0|1|2; validated before save
void placeToken(String token, {required int toRow, required int toIndex});
// toRow == CustomKeyRows.shelfRow parks the token outside the bar; the index is
// read against the target row *before* the move, so a same-row drag to a higher
// slot lands at toIndex - 1.
```
