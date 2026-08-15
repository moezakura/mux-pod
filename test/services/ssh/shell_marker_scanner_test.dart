import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/ssh/shell_marker_scanner.dart';

void main() {
  // Fixed test markers with the same shape as the ones PersistentShell builds
  // at runtime (which now use a per-session random nonce). They begin and end
  // with the SOH control byte 0x01; the exact id is irrelevant to the scanner.
  const startStr = '\x01###START_deadbeefcafe0001###\x01';
  const endStr = '\x01###END_deadbeefcafe0001###\x01';

  List<int> b(String s) => utf8.encode(s);

  ShellMarkerScanner newScanner() =>
      ShellMarkerScanner(startMarker: b(startStr), endMarker: b(endStr));

  String? decode(List<int>? bytes) =>
      bytes == null ? null : utf8.decode(bytes, allowMalformed: true);

  group('ShellMarkerScanner', () {
    test('extracts content when both markers arrive in one chunk', () {
      final s = newScanner();
      final result = s.feed(b('$startStr\nhello world\n$endStr'));
      expect(decode(result), '\nhello world\n');
    });

    test('returns null until the end marker is present', () {
      final s = newScanner();
      expect(s.feed(b('$startStr partial output')), isNull);
      expect(decode(s.feed(b(' more$endStr'))), ' partial output more');
    });

    test('ignores bytes before the start marker', () {
      final s = newScanner();
      final result = s.feed(b('leftover prompt junk$startStr payload$endStr'));
      expect(decode(result), ' payload');
    });

    test('ignores an end marker that appears before the start marker', () {
      final s = newScanner();
      // A stray end marker ahead of the real command output must not complete.
      expect(s.feed(b('$endStr noise')), isNull);
      expect(decode(s.feed(b('$startStr real$endStr'))), ' real');
    });

    test('detects a start marker split across chunk boundaries', () {
      final s = newScanner();
      final full = b(startStr);
      final head = full.sublist(0, 6);
      final tail = full.sublist(6);
      // Prepend enough leading junk that the rewind window is exercised.
      expect(s.feed([...b('x' * 40), ...head]), isNull);
      expect(decode(s.feed([...tail, ...b('data'), ...b(endStr)])), 'data');
    });

    test('detects an end marker split across chunk boundaries', () {
      final s = newScanner();
      final full = b(endStr);
      final head = full.sublist(0, 5);
      final tail = full.sublist(5);
      expect(s.feed([...b(startStr), ...b('abc'), ...head]), isNull);
      expect(decode(s.feed(tail)), 'abc');
    });

    test('preserves multi-byte UTF-8 content between markers', () {
      final s = newScanner();
      const payload = 'こんにちは 世界 🌐';
      final result = s.feed([...b(startStr), ...b(payload), ...b(endStr)]);
      expect(decode(result), payload);
    });

    test('returns an empty list when there is no content between markers', () {
      final s = newScanner();
      final result = s.feed(b('$startStr$endStr'));
      expect(result, isNotNull);
      expect(result, isEmpty);
    });

    test('resets after a match so it can be reused for the next command', () {
      final s = newScanner();
      expect(decode(s.feed(b('$startStr first$endStr'))), ' first');
      // Trailing bytes after the first end marker are discarded on reset.
      expect(decode(s.feed(b('$startStr second$endStr'))), ' second');
    });

    test('feeds byte-by-byte and completes exactly once', () {
      final s = newScanner();
      final all = [...b(startStr), ...b('drip'), ...b(endStr)];
      final matches = <String>[];
      for (final byte in all) {
        final r = s.feed([byte]);
        if (r != null) matches.add(decode(r)!);
      }
      expect(matches, ['drip']);
    });

    test('reset() discards a partially buffered command', () {
      final s = newScanner();
      expect(s.feed(b('$startStr half')), isNull);
      s.reset();
      // After reset the leftover "half" is gone; a fresh command still parses.
      expect(decode(s.feed(b('$startStr whole$endStr'))), ' whole');
    });
  });
}
