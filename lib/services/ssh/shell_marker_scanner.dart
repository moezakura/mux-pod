import 'dart:typed_data';

/// Incrementally scans a byte stream for a `start`/`end` marker pair and
/// extracts the bytes strictly between them.
///
/// A naive implementation that re-decodes and re-scans the whole accumulated
/// buffer on every chunk is O(n²) in the total output size — clearly visible
/// when a tmux `capture-pane` dumps hundreds of scrollback lines split across
/// many TCP segments. This scanner keeps search cursors so each incoming chunk
/// is inspected at most once (plus a marker-length overlap to catch a marker
/// that straddles a chunk boundary), giving O(n) amortised work.
///
/// Matching is done at the byte level. Both markers used by `PersistentShell`
/// consist of ASCII/control bytes (`\x01`, `#`, letters, digits); none of those
/// can appear as a UTF-8 continuation byte (`0x80`–`0xBF`) or lead byte, so
/// byte matching never splits a multi-byte character.
// inventory: SHELL-SCAN-001
class ShellMarkerScanner {
  // inventory: SHELL-SCAN-002
  ShellMarkerScanner({
    required List<int> startMarker,
    required List<int> endMarker,
  })  : assert(startMarker.isNotEmpty, 'start marker must not be empty'),
        assert(endMarker.isNotEmpty, 'end marker must not be empty'),
        _start = Uint8List.fromList(startMarker),
        _end = Uint8List.fromList(endMarker);

  final Uint8List _start;
  final Uint8List _end;

  /// Uint8List-backed accumulator. `_buf` is the capacity, `_len` the used
  /// prefix. Keeping a real Uint8List lets [feed] extract the matched slice
  /// with a SINGLE copy (`Uint8List.sublist`) instead of a `List<int>.sublist`
  /// followed by `Uint8List.fromList` (two copies).
  Uint8List _buf = Uint8List(0);
  int _len = 0;

  /// Appends [data] into [_buf], growing the backing store as needed.
  // inventory: SHELL-SCAN-005
  void _append(List<int> data) {
    final needed = _len + data.length;
    if (needed > _buf.length) {
      var newCap = _buf.isEmpty ? 64 : _buf.length * 2;
      while (newCap < needed) {
        newCap *= 2;
      }
      final grown = Uint8List(newCap);
      grown.setRange(0, _len, _buf);
      _buf = grown;
    }
    _buf.setRange(_len, needed, data);
    _len = needed;
  }

  /// Next index to inspect while the start marker has not been found yet.
  int _startSearchFrom = 0;

  /// Index just past the start marker once it has been located, else -1.
  int _contentStart = -1;

  /// Next index to inspect while searching for the end marker.
  int _endSearchFrom = 0;

  /// Discards buffered bytes and resets the search state.
  // inventory: SHELL-SCAN-003
  void reset() {
    _len = 0;
    _startSearchFrom = 0;
    _contentStart = -1;
    _endSearchFrom = 0;
  }

  /// Appends [data] and returns the bytes between the start and end markers
  /// once both are present (start before end), otherwise `null`.
  ///
  /// On a successful match the scanner resets itself, so it is ready for the
  /// next command without an explicit [reset] call. Bytes before the start
  /// marker and after the end marker are discarded.
  // inventory: SHELL-SCAN-004
  Uint8List? feed(List<int> data) {
    if (data.isNotEmpty) {
      _append(data);
    }

    if (_contentStart < 0) {
      final s = _indexOf(_buf, _len, _start, _startSearchFrom);
      if (s < 0) {
        // Rewind just far enough to catch a start marker that is split across
        // the boundary with the next chunk.
        _startSearchFrom = _len - _start.length + 1;
        if (_startSearchFrom < 0) _startSearchFrom = 0;
        return null;
      }
      _contentStart = s + _start.length;
      _endSearchFrom = _contentStart;
    }

    final e = _indexOf(_buf, _len, _end, _endSearchFrom);
    if (e < 0) {
      _endSearchFrom = _len - _end.length + 1;
      if (_endSearchFrom < _contentStart) _endSearchFrom = _contentStart;
      return null;
    }

    final result = _buf.sublist(_contentStart, e);
    reset();
    return result;
  }

  /// First index of [needle] within the first [hayLen] bytes of [haystack] at
  /// or after [from], or -1.
  // inventory: SHELL-SCAN-006
  static int _indexOf(Uint8List haystack, int hayLen, Uint8List needle, int from) {
    final n = needle.length;
    final limit = hayLen - n;
    outer:
    for (var i = from < 0 ? 0 : from; i <= limit; i++) {
      for (var j = 0; j < n; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
