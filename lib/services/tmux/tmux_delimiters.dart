// inventory: TMUX-DELIM-000
/// tmux `-F` 出力の区切り文字ペア
library;

import 'dart:math';

// inventory: TMUX-DELIM-001
/// The field/record delimiter pair used for one `tmux -F` round trip.
///
/// Both delimiters are printable. tmux hands `-F` output to a client that is
/// not in UTF-8 mode through `utf8_sanitize()`, which rewrites every byte
/// outside `0x20..0x7e` to `_` — 0x1f, 0x1e and TAB all arrive as the same
/// character, indistinguishable from content. A tmux client is in UTF-8 mode
/// only when `$TMUX`, `LC_ALL`, `LC_CTYPE` or `LANG` says so, and an SSH
/// command channel carries none of those, so MuxPod always lands in the
/// sanitizing path.
///
/// The pair is minted per invocation ([TmuxDelimiters.random]) rather than
/// fixed: tmux accepts any printable string in a session, window or pane name,
/// so a constant delimiter — however unlikely — can be typed by a user and
/// shift the fields of a record. A delimiter that did not exist when the name
/// was set cannot be.
class TmuxDelimiters {
  /// Separates the fields inside one record.
  final String field;

  /// Terminates each record, so a newline inside a field cannot split it.
  final String record;

  const TmuxDelimiters({required this.field, required this.record});

  // inventory: TMUX-DELIM-002
  /// Mints a fresh pair, unguessable to whoever named the sessions.
  factory TmuxDelimiters.random() {
    final id = _randomId();
    return TmuxDelimiters(field: '@F$id@', record: '@R$id@');
  }

  // inventory: TMUX-DELIM-003
  /// Field delimiter (US, 0x1f) MuxPod used to ask tmux for.
  static const String legacyField = '\x1f';

  /// Record delimiter (RS, 0x1e) MuxPod used to ask tmux for.
  static const String legacyRecord = '\x1e';

  // inventory: TMUX-DELIM-004
  /// The pair MuxPod used to ask tmux for.
  ///
  /// Parse side only — never build a command with it. Output produced by an
  /// older MuxPod, and the fixtures modelled on it, still has to parse.
  static const TmuxDelimiters legacy = TmuxDelimiters(
    field: legacyField,
    record: legacyRecord,
  );

  /// 16 hex characters (64 bits) from a cryptographic source, like the
  /// pollPane section marker.
  static String _randomId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
