import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/ansi_parser.dart';

/// Verifies the incremental line cache in [AnsiParser.parseLines] always
/// produces output identical to a fresh (cache-less) parse. A wrong cache reuse
/// would visually corrupt the terminal, so this is the correctness guard for
/// the render-jank optimization.
void main() {
  AnsiParser newParser() => AnsiParser(
    defaultForeground: const Color(0xFFD4D4D4),
    defaultBackground: const Color(0xFF1E1E1E),
  );

  void expectParsedEqual(List<ParsedLine> a, List<ParsedLine> b, String label) {
    expect(a.length, b.length, reason: '$label: line count');
    for (var i = 0; i < a.length; i++) {
      final sa = a[i].segments;
      final sb = b[i].segments;
      expect(sa.length, sb.length, reason: '$label: line $i segment count');
      for (var j = 0; j < sa.length; j++) {
        expect(sa[j].text, sb[j].text, reason: '$label: line $i seg $j text');
        expect(
          sa[j].style,
          sb[j].style,
          reason: '$label: line $i seg $j style',
        );
      }
      expect(a[i].endStyle, b[i].endStyle, reason: '$label: line $i endStyle');
    }
  }

  /// Parse [prev] then [next] on one parser (exercises the incremental path),
  /// and compare against a fresh parser that only parses [next].
  void checkIncremental(String prev, String next, String label) {
    final incremental = newParser();
    incremental.parseLines(prev);
    final incrementalResult = incremental.parseLines(next);
    final fresh = newParser().parseLines(next);
    expectParsedEqual(incrementalResult, fresh, label);
  }

  group('AnsiParser incremental parseLines', () {
    const red = '\x1b[31m';
    const green = '\x1b[32m';
    const reset = '\x1b[0m';

    test('identical text reuses everything and stays correct', () {
      checkIncremental(
        'line a\nline b\nline c',
        'line a\nline b\nline c',
        'identical',
      );
    });

    test('appended lines', () {
      checkIncremental('a\nb', 'a\nb\nc\nd', 'append');
    });

    test('modified last line', () {
      checkIncremental('a\nb\nc', 'a\nb\nCHANGED', 'last line');
    });

    test('modified middle line', () {
      checkIncremental('a\nb\nc\nd', 'a\nB2\nc\nd', 'middle line');
    });

    test('inserted middle line shifts indices', () {
      checkIncremental('a\nb\nc', 'a\nINSERTED\nb\nc', 'insert');
    });

    test('colored content unchanged', () {
      final t = '${red}error$reset\nnormal\n${green}ok$reset';
      checkIncremental(t, t, 'colored identical');
    });

    test('change that alters carried style for following lines', () {
      // prev: red is reset on line 0, so line 1 is default.
      // next: reset removed on line 0 -> red now bleeds into line 1.
      // The incremental parser MUST re-parse line 1 (entering style changed).
      checkIncremental(
        '${red}x$reset\nplain',
        '${red}x\nplain',
        'carried style',
      );
    });

    test('style reset restored makes following line default again', () {
      checkIncremental(
        '${red}x\nplain',
        '${red}x$reset\nplain',
        'reset restored',
      );
    });

    test('multi-step edits stay consistent', () {
      final p = newParser();
      p.parseLines('a\nb\nc');
      p.parseLines('a\nb\nc\nd');
      p.parseLines('a\nX\nc\nd');
      final incremental = p.parseLines('${green}a\nX\nc\nd');
      final fresh = newParser().parseLines('${green}a\nX\nc\nd');
      expectParsedEqual(incremental, fresh, 'multi-step');
    });

    test('shrinking content', () {
      checkIncremental('a\nb\nc\nd\ne', 'a\nb', 'shrink');
    });

    test('scrolling output: all lines shift up by one stays correct', () {
      // The active-tmux case: drop the top line, append a new bottom line.
      // Every index changes, so a position-based cache would miss; the
      // content-keyed cache must still yield output identical to a fresh parse.
      checkIncremental(
        'l0\nl1\nl2\nl3\nl4',
        'l1\nl2\nl3\nl4\nl5',
        'scroll shift',
      );
    });

    test('scrolling colored output shift stays correct', () {
      checkIncremental(
        '${red}a$reset\n${green}b$reset\nc\nd',
        '${green}b$reset\nc\nd\n${red}e$reset',
        'scroll colored shift',
      );
    });

    test('repeated blank lines share reuse and stay correct', () {
      checkIncremental('x\n\n\n\ny', '\n\n\n\ny', 'blank reuse');
    });
  });
}
