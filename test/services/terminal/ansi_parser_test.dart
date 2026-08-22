import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/ansi_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnsiParser', () {
    late AnsiParser parser;

    setUp(() {
      parser = AnsiParser(
        defaultForeground: const Color(0xFFD4D4D4),
        defaultBackground: const Color(0xFF1E1E1E),
      );
    });

    test('parse handles reverse video (ESC[7m)', () {
      const input = '\x1b[7mReversed\x1b[27mNormal';
      final segments = parser.parse(input);

      expect(segments.length, 2);
      expect(segments[0].text, 'Reversed');
      expect(segments[0].style.inverse, isTrue);
      expect(segments[1].text, 'Normal');
      expect(segments[1].style.inverse, isFalse);
    });

    test('toTextSpan swaps colors when inverse is true', () {
      // Setup style with explicit colors
      const input = '\x1b[31;42;7mReversed\x1b[0m'; // Red fg, Green bg, Inverse
      final segments = parser.parse(input);

      final textSpan = parser.toTextSpan(
        segments,
        fontSize: 14,
        fontFamily: 'HackGen Console',
      );

      // Expected: FG should be Green (originally BG), BG should be Red (originally FG)
      // Original: 31 (Red) -> 0xFFCD3131, 42 (Green) -> 0xFF0DBC79

      final span = textSpan.children![0] as TextSpan;
      // In toTextSpan:
      // fg = Red, bg = Green
      // inverse -> fg = Green, bg = Red

      expect(span.style!.color, const Color(0xFF0DBC79)); // Green
      expect(span.style!.backgroundColor, const Color(0xFFCD3131)); // Red
    });

    test('toTextSpan handles default colors with inverse', () {
      const input = '\x1b[7mReversed\x1b[0m';
      final segments = parser.parse(input);

      final textSpan = parser.toTextSpan(
        segments,
        fontSize: 14,
        fontFamily: 'HackGen Console',
      );

      final span = textSpan.children![0] as TextSpan;

      // Default FG: 0xFFD4D4D4
      // Default BG: 0xFF1E1E1E
      // Inverse -> FG: 0xFF1E1E1E, BG: 0xFFD4D4D4

      expect(span.style!.color, const Color(0xFF1E1E1E));
      expect(span.style!.backgroundColor, const Color(0xFFD4D4D4));
    });

    test(
      'toTextSpan sets backgroundColor even if it matches defaultBackground when inverse is true',
      () {
        // 30 is Black (0xFF000000), 7 is Inverse
        // Default BG is 0xFF1E1E1E. If we set FG to 0xFF1E1E1E and invert,
        // the new BG will be 0xFF1E1E1E which matches defaultBackground.

        parser = AnsiParser(
          defaultForeground: const Color(0xFF000000),
          defaultBackground: const Color(0xFF1E1E1E),
        );

        const input = '\x1b[7mInverse\x1b[0m';
        final segments = parser.parse(input);
        final textSpan = parser.toTextSpan(
          segments,
          fontSize: 14,
          fontFamily: 'HackGen Console',
        );

        final span = textSpan.children![0] as TextSpan;

        // Swapped: FG -> 0xFF1E1E1E, BG -> 0xFF000000
        expect(span.style!.backgroundColor, const Color(0xFF000000));

        // Test case where BG matches defaultBackground after swap
        // Original FG = defaultBackground, then Inverse
        final styleWithDefaultBGAsFG = const AnsiStyle(
          inverse: true,
        ).copyWith(foreground: const Color(0xFF1E1E1E));
        final segment = AnsiSegment('text', styleWithDefaultBGAsFG);
        final spanWithDefaultBG = parser.toTextSpan(
          [segment],
          fontSize: 14,
          fontFamily: 'HackGen Console',
        );

        final span2 = spanWithDefaultBG.children![0] as TextSpan;
        // fg (swapped) = defaultBackground (0xFF1E1E1E)
        // bg (swapped) = foreground (0xFF1E1E1E)
        // Since inverse is true, it should NOT be null.
        expect(span2.style!.backgroundColor, const Color(0xFF1E1E1E));
      },
    );

    test('parseLines handles reverse video correctly across lines', () {
      const input = '\x1b[7mLine1\nLine2\x1b[27m';
      final parsedLines = parser.parseLines(input);

      expect(parsedLines.length, 2);

      // Line 1
      expect(parsedLines[0].segments[0].text, 'Line1');
      expect(parsedLines[0].segments[0].style.inverse, isTrue);
      expect(parsedLines[0].endStyle.inverse, isTrue); // Should carry over

      // Line 2
      expect(parsedLines[1].segments[0].text, 'Line2');
      expect(parsedLines[1].segments[0].style.inverse, isTrue);
      expect(parsedLines[1].endStyle.inverse, isFalse);
    });

    test('parseLines normalizes CRLF to LF (PTY 経由の改行)', () {
      // PTY の出力変換（ONLCR）で \r\n が混入しても、空行として扱われないこと
      const input = 'line1\r\nline2\r\nline3';
      final parsedLines = parser.parseLines(input);

      expect(parsedLines.length, 3);
      expect(parsedLines[0].segments[0].text, 'line1');
      expect(parsedLines[1].segments[0].text, 'line2');
      expect(parsedLines[2].segments[0].text, 'line3');
    });

    test('parseLines strips lone CR (行末の \\r)', () {
      const input = 'line1\rline2';
      final parsedLines = parser.parseLines(input);

      // \r は改行とみなさず除去され、1行としてパースされる
      expect(parsedLines.length, 1);
      expect(parsedLines[0].segments[0].text, 'line1line2');
    });

    test('handles inverse space (cursor representation)', () {
      const input = 'Prompt\x1b[7m \x1b[27m'; // ' ' is the cursor
      final segments = parser.parse(input);

      expect(segments.length, 2);
      expect(segments[1].text, ' ');
      expect(segments[1].style.inverse, isTrue);

      final textSpan = parser.toTextSpan(
        segments,
        fontSize: 14,
        fontFamily: 'HackGen Console',
      );

      final cursorSpan = textSpan.children![1] as TextSpan;
      // Should replace space with non-breaking space
      expect(cursorSpan.text, '\u00A0');

      expect(cursorSpan.style!.backgroundColor, isNotNull);
      // Default BG is 0xFF1E1E1E, Default FG is 0xFFD4D4D4
      // Swapped: BG should be 0xFFD4D4D4
      expect(cursorSpan.style!.backgroundColor, const Color(0xFFD4D4D4));
    });

    group('effectiveLineBackgroundColor', () {
      test('returns null for plain line (default background)', () {
        final lines = parser.parseLines('plain text');
        expect(parser.effectiveLineBackgroundColor(lines[0]), isNull);
      });

      test('returns segment background for colored line', () {
        // 青背景 44 = standardColors[4] = 0xFF2472C8
        final lines = parser.parseLines('\x1b[44mCOLORED-TEXT\x1b[49m');
        expect(
          parser.effectiveLineBackgroundColor(lines[0]),
          const Color(0xFF2472C8),
        );
      });

      test('returns endStyle background for empty line with SGR only', () {
        // 緑背景 42 のみでテキスト無しの空行
        final lines = parser.parseLines('\x1b[42m');
        expect(lines[0].segments, isEmpty);
        expect(
          parser.effectiveLineBackgroundColor(lines[0]),
          const Color(0xFF0DBC79),
        );
      });

      test('returns inverse-swapped foreground for inverse line', () {
        // 反転時は有効背景 = 元の前景（デフォルト前景）
        final lines = parser.parseLines('\x1b[7mreversed');
        expect(
          parser.effectiveLineBackgroundColor(lines[0]),
          const Color(0xFFD4D4D4), // defaultForeground
        );
      });

      test('uses last segment style for trailing style', () {
        // 前半は赤背景、後半はリセット済み → 有効背景は default → null
        final lines = parser.parseLines('\x1b[41mRED\x1b[49m tail');
        expect(parser.effectiveLineBackgroundColor(lines[0]), isNull);
      });
    });
  });
}
