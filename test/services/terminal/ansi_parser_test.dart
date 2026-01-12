import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/ansi_parser.dart';
import 'package:flutter_muxpod/services/terminal/terminal_font_styles.dart';

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
      expect(cursorSpan.style!.backgroundColor, isNotNull);
      // Default BG is 0xFF1E1E1E, Default FG is 0xFFD4D4D4
      // Swapped: BG should be 0xFFD4D4D4
      expect(cursorSpan.style!.backgroundColor, const Color(0xFFD4D4D4));
    });
  });
}
