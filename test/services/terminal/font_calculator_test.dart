import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/font_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Warm the FontCalculator char-width cache once before all tests run.
  //
  // Calling measureCharWidthRatio triggers google_fonts to enqueue a background
  // HTTP fetch (loadFontIfNecessary). Under TestWidgetsFlutterBinding all HTTP
  // requests return 400, so that task always fails. By warming the cache here
  // inside a guarded zone we swallow the expected font-load error before it
  // bleeds across test boundaries. All subsequent calls in individual tests hit
  // the cache and never enqueue another request.
  setUpAll(() {
    runZonedGuarded(
      () {
        FontCalculator.measureCharWidthRatio('JetBrains Mono');
      },
      (error, _) {
        // Suppress the expected "Failed to load font" error from google_fonts.
      },
    );
  });

  group('FontCalculator', () {
    group('calculate', () {
      test('falls back to default pane width (80) for zero pane width', () {
        // T031: paneWidth = 0 → fallback to 80
        final resultZero = FontCalculator.calculate(
          screenWidth: 400.0,
          paneCharWidth: 0,
          fontFamily: 'JetBrains Mono',
          minFontSize: 4.0, // Low min to avoid clamping
        );

        final resultDefault = FontCalculator.calculate(
          screenWidth: 400.0,
          paneCharWidth: FontCalculator.defaultPaneWidth, // 80
          fontFamily: 'JetBrains Mono',
          minFontSize: 4.0,
        );

        // Should produce same result as using default pane width
        expect(resultZero.fontSize, equals(resultDefault.fontSize));
        expect(resultZero.needsScroll, equals(resultDefault.needsScroll));
      });

      test('falls back to default pane width (80) for negative pane width', () {
        // T031: paneWidth < 0 → fallback to 80
        final resultNegative = FontCalculator.calculate(
          screenWidth: 400.0,
          paneCharWidth: -10,
          fontFamily: 'JetBrains Mono',
          minFontSize: 4.0,
        );

        final resultDefault = FontCalculator.calculate(
          screenWidth: 400.0,
          paneCharWidth: FontCalculator.defaultPaneWidth, // 80
          fontFamily: 'JetBrains Mono',
          minFontSize: 4.0,
        );

        expect(resultNegative.fontSize, equals(resultDefault.fontSize));
        expect(resultNegative.needsScroll, equals(resultDefault.needsScroll));
      });

      test('clamps extremely narrow panes to minimum width (10)', () {
        // T032: paneWidth < 10 → clamp to 10
        final resultNarrow = FontCalculator.calculate(
          screenWidth: 400.0,
          paneCharWidth: 5,
          fontFamily: 'JetBrains Mono',
          minFontSize: 4.0,
        );

        final resultMinWidth = FontCalculator.calculate(
          screenWidth: 400.0,
          paneCharWidth: FontCalculator.minPaneWidth, // 10
          fontFamily: 'JetBrains Mono',
          minFontSize: 4.0,
        );

        expect(resultNarrow.fontSize, equals(resultMinWidth.fontSize));
        expect(resultNarrow.needsScroll, equals(resultMinWidth.needsScroll));
      });

      test('returns default values for zero screen width', () {
        final result = FontCalculator.calculate(
          screenWidth: 0.0,
          paneCharWidth: 80,
          fontFamily: 'JetBrains Mono',
          minFontSize: 8.0,
        );

        expect(result.fontSize, equals(FontCalculator.defaultFontSize));
        expect(result.needsScroll, isFalse);
      });

      test('returns default values for negative screen width', () {
        final result = FontCalculator.calculate(
          screenWidth: -100.0,
          paneCharWidth: 80,
          fontFamily: 'JetBrains Mono',
          minFontSize: 8.0,
        );

        expect(result.fontSize, equals(FontCalculator.defaultFontSize));
        expect(result.needsScroll, isFalse);
      });

      test('calculates font size for standard 80 char pane', () {
        final result = FontCalculator.calculate(
          screenWidth: 800.0, // Wider screen to ensure font fits
          paneCharWidth: 80,
          fontFamily: 'JetBrains Mono',
          minFontSize: 8.0,
        );

        // fontSize = screenWidth / (paneWidth * charWidthRatio)
        // Should calculate a valid font size
        expect(result.fontSize, greaterThanOrEqualTo(8.0));
        expect(result.needsScroll, isFalse);
      });

      test('enables horizontal scroll when font would be too small', () {
        final result = FontCalculator.calculate(
          screenWidth: 100.0, // Very narrow screen
          paneCharWidth: 200,
          fontFamily: 'JetBrains Mono',
          minFontSize: 8.0,
        );

        expect(result.fontSize, equals(8.0));
        expect(result.needsScroll, isTrue);
      });

      test('respects custom minimum font size', () {
        final result = FontCalculator.calculate(
          screenWidth: 100.0, // Very narrow screen
          paneCharWidth: 200,
          fontFamily: 'JetBrains Mono',
          minFontSize: 10.0,
        );

        expect(result.fontSize, equals(10.0));
        expect(result.needsScroll, isTrue);
      });

      test('does not need scroll when font fits', () {
        final result = FontCalculator.calculate(
          screenWidth: 2000.0, // Very wide screen
          paneCharWidth: 80,
          fontFamily: 'JetBrains Mono',
          minFontSize: 8.0,
        );

        expect(result.needsScroll, isFalse);
        expect(result.fontSize, greaterThan(8.0));
      });

      test('narrower pane results in larger font', () {
        final result40 = FontCalculator.calculate(
          screenWidth: 400.0,
          paneCharWidth: 40,
          fontFamily: 'JetBrains Mono',
          minFontSize: 4.0, // Very low min to avoid clamping
        );

        final result80 = FontCalculator.calculate(
          screenWidth: 400.0,
          paneCharWidth: 80,
          fontFamily: 'JetBrains Mono',
          minFontSize: 4.0,
        );

        expect(result40.fontSize, greaterThan(result80.fontSize));
      });

      test('wider screen results in larger font', () {
        final result400 = FontCalculator.calculate(
          screenWidth: 400.0,
          paneCharWidth: 80,
          fontFamily: 'JetBrains Mono',
          minFontSize: 4.0, // Very low min to avoid clamping
        );

        final result800 = FontCalculator.calculate(
          screenWidth: 800.0,
          paneCharWidth: 80,
          fontFamily: 'JetBrains Mono',
          minFontSize: 4.0,
        );

        expect(result800.fontSize, greaterThan(result400.fontSize));
      });
    });

    group('measureCharWidthRatio', () {
      test('returns positive ratio', () {
        final ratio = FontCalculator.measureCharWidthRatio('JetBrains Mono');
        expect(ratio, greaterThan(0.0));
        // Ratio can be >= 1 for some fonts, especially fallback fonts
        expect(ratio, lessThan(2.0));
      });

      test('returns consistent ratio for same font family', () {
        final ratio1 = FontCalculator.measureCharWidthRatio('JetBrains Mono');
        final ratio2 = FontCalculator.measureCharWidthRatio('JetBrains Mono');
        expect(ratio1, equals(ratio2));
      });
    });

    group('calculateTerminalWidth', () {
      test('calculates terminal width in pixels', () {
        final width = FontCalculator.calculateTerminalWidth(
          paneCharWidth: 80,
          fontSize: 14.0,
          fontFamily: 'JetBrains Mono',
        );

        // width = paneCharWidth * charWidthRatio * fontSize
        expect(width, greaterThan(0.0));
      });

      test('wider pane results in larger terminal width', () {
        final width80 = FontCalculator.calculateTerminalWidth(
          paneCharWidth: 80,
          fontSize: 14.0,
          fontFamily: 'JetBrains Mono',
        );

        final width120 = FontCalculator.calculateTerminalWidth(
          paneCharWidth: 120,
          fontSize: 14.0,
          fontFamily: 'JetBrains Mono',
        );

        expect(width120, greaterThan(width80));
      });

      test('larger font results in larger terminal width', () {
        final width14 = FontCalculator.calculateTerminalWidth(
          paneCharWidth: 80,
          fontSize: 14.0,
          fontFamily: 'JetBrains Mono',
        );

        final width20 = FontCalculator.calculateTerminalWidth(
          paneCharWidth: 80,
          fontSize: 20.0,
          fontFamily: 'JetBrains Mono',
        );

        expect(width20, greaterThan(width14));
      });
    });

    group('getCharDisplayWidth', () {
      test('returns 1 for ASCII characters', () {
        expect(FontCalculator.getCharDisplayWidth('a'.codeUnitAt(0)), equals(1));
        expect(FontCalculator.getCharDisplayWidth('Z'.codeUnitAt(0)), equals(1));
        expect(FontCalculator.getCharDisplayWidth('0'.codeUnitAt(0)), equals(1));
        expect(FontCalculator.getCharDisplayWidth('!'.codeUnitAt(0)), equals(1));
        expect(FontCalculator.getCharDisplayWidth(' '.codeUnitAt(0)), equals(1));
      });

      test('returns 2 for Japanese hiragana', () {
        expect(FontCalculator.getCharDisplayWidth('あ'.codeUnitAt(0)), equals(2));
        expect(FontCalculator.getCharDisplayWidth('い'.codeUnitAt(0)), equals(2));
        expect(FontCalculator.getCharDisplayWidth('う'.codeUnitAt(0)), equals(2));
      });

      test('returns 2 for Japanese katakana', () {
        expect(FontCalculator.getCharDisplayWidth('ア'.codeUnitAt(0)), equals(2));
        expect(FontCalculator.getCharDisplayWidth('イ'.codeUnitAt(0)), equals(2));
      });

      test('returns 2 for CJK ideographs (kanji)', () {
        expect(FontCalculator.getCharDisplayWidth('漢'.codeUnitAt(0)), equals(2));
        expect(FontCalculator.getCharDisplayWidth('字'.codeUnitAt(0)), equals(2));
      });

      test('returns 2 for fullwidth characters', () {
        // Fullwidth asterisk U+FF0A
        expect(FontCalculator.getCharDisplayWidth(0xFF0A), equals(2));
        // Fullwidth A U+FF21
        expect(FontCalculator.getCharDisplayWidth(0xFF21), equals(2));
      });

      test('returns 2 for emoji', () {
        // 💩 U+1F4A9
        expect(FontCalculator.getCharDisplayWidth(0x1F4A9), equals(2));
        // 😀 U+1F600
        expect(FontCalculator.getCharDisplayWidth(0x1F600), equals(2));
      });

      test('returns 0 for control characters', () {
        expect(FontCalculator.getCharDisplayWidth(0x00), equals(0)); // NUL
        expect(FontCalculator.getCharDisplayWidth(0x1F), equals(0)); // Unit Separator
        expect(FontCalculator.getCharDisplayWidth(0x7F), equals(0)); // DEL
      });

      test('returns 0 for variation selectors', () {
        // VS16 U+FE0F (emoji style)
        expect(FontCalculator.getCharDisplayWidth(0xFE0F), equals(0));
        // VS15 U+FE0E (text style)
        expect(FontCalculator.getCharDisplayWidth(0xFE0E), equals(0));
      });

      test('returns 0 for zero-width joiners', () {
        // ZWJ U+200D
        expect(FontCalculator.getCharDisplayWidth(0x200D), equals(0));
        // ZWNJ U+200C
        expect(FontCalculator.getCharDisplayWidth(0x200C), equals(0));
      });

      test('returns 0 for combining marks', () {
        // Combining Acute Accent U+0301
        expect(FontCalculator.getCharDisplayWidth(0x0301), equals(0));
      });
    });

    group('getTextDisplayWidth', () {
      test('calculates width for ASCII text', () {
        expect(FontCalculator.getTextDisplayWidth('hello'), equals(5));
        expect(FontCalculator.getTextDisplayWidth('abc123'), equals(6));
      });

      test('calculates width for Japanese text', () {
        expect(FontCalculator.getTextDisplayWidth('あいうえお'), equals(10));
      });

      test('calculates width for mixed text', () {
        // 'aあb' = 1 + 2 + 1 = 4
        expect(FontCalculator.getTextDisplayWidth('aあb'), equals(4));
      });

      test('calculates width for emoji with VS16', () {
        // ✡️ = U+2721 (width 2 because followed by VS16) + U+FE0F (width 0) = 2
        expect(FontCalculator.getTextDisplayWidth('✡️'), equals(2));
      });

      test('calculates width for complex emoji text', () {
        // ＊✡️💩aaあいうえお
        // ＊ (U+FF0A) = 2
        // ✡️ (U+2721 + U+FE0F) = 2 + 0 = 2
        // 💩 (U+1F4A9) = 2
        // aa = 2
        // あいうえお = 10
        // Total = 2 + 2 + 2 + 2 + 10 = 18
        expect(FontCalculator.getTextDisplayWidth('＊✡️💩aaあいうえお'), equals(18));
      });

      test('returns 0 for empty string', () {
        expect(FontCalculator.getTextDisplayWidth(''), equals(0));
      });
    });

    group('columnToCharOffset', () {
      test('converts column position for ASCII text', () {
        const text = 'hello';
        expect(FontCalculator.columnToCharOffset(text, 0), equals(0));
        expect(FontCalculator.columnToCharOffset(text, 1), equals(1));
        expect(FontCalculator.columnToCharOffset(text, 3), equals(3));
        expect(FontCalculator.columnToCharOffset(text, 5), equals(5));
      });

      test('converts column position for Japanese text', () {
        const text = 'あいう'; // Each character is 2 columns, 1 code unit each
        // Column 0 -> code unit 0
        expect(FontCalculator.columnToCharOffset(text, 0), equals(0));
        // Column 2 -> code unit 1 (after 'あ')
        expect(FontCalculator.columnToCharOffset(text, 2), equals(1));
        // Column 4 -> code unit 2 (after 'い')
        expect(FontCalculator.columnToCharOffset(text, 4), equals(2));
        // Column 6 -> code unit 3 (after 'う')
        expect(FontCalculator.columnToCharOffset(text, 6), equals(3));
      });

      test('converts column position for mixed text', () {
        const text = 'aあb'; // 1 + 2 + 1 = 4 columns
        // Column 0 -> code unit 0
        expect(FontCalculator.columnToCharOffset(text, 0), equals(0));
        // Column 1 -> code unit 1 (after 'a')
        expect(FontCalculator.columnToCharOffset(text, 1), equals(1));
        // Column 3 -> code unit 2 (after 'あ')
        expect(FontCalculator.columnToCharOffset(text, 3), equals(2));
        // Column 4 -> code unit 3 (after 'b')
        expect(FontCalculator.columnToCharOffset(text, 4), equals(3));
      });

      test('converts column position with emoji and VS16', () {
        const text = '✡️a'; // ✡️ (2 columns) + a (1 column) = 3 columns
        // ✡ (U+2721) = 1 code unit, VS16 (U+FE0F) = 1 code unit, a = 1 code unit
        // Column 0 -> code unit 0
        expect(FontCalculator.columnToCharOffset(text, 0), equals(0));
        // Column 2 -> code unit 2 (after ✡️)
        expect(FontCalculator.columnToCharOffset(text, 2), equals(2));
        // Column 3 -> code unit 3 (after 'a')
        expect(FontCalculator.columnToCharOffset(text, 3), equals(3));
      });

      test('handles surrogate pair emoji correctly', () {
        // 💩 (U+1F4A9) is a surrogate pair = 2 code units
        const text = 'a💩b';
        // a = 1 code unit, 💩 = 2 code units, b = 1 code unit
        // Columns: a(1) + 💩(2) + b(1) = 4 columns
        // Column 0 -> code unit 0
        expect(FontCalculator.columnToCharOffset(text, 0), equals(0));
        // Column 1 -> code unit 1 (after 'a')
        expect(FontCalculator.columnToCharOffset(text, 1), equals(1));
        // Column 3 -> code unit 3 (after 💩, which is 2 code units)
        expect(FontCalculator.columnToCharOffset(text, 3), equals(3));
        // Column 4 -> code unit 4 (after 'b')
        expect(FontCalculator.columnToCharOffset(text, 4), equals(4));
      });

      test('handles complex emoji text correctly', () {
        const text = '＊✡️💩aaあいうえお';
        // Code units:
        // ＊ (U+FF0A): 1 code unit, 2 columns -> cu 0-0
        // ✡ (U+2721): 1 code unit, 2 columns -> cu 1
        // VS16 (U+FE0F): 1 code unit, 0 columns -> cu 2
        // 💩 (U+1F4A9): 2 code units, 2 columns -> cu 3-4
        // a: 1 code unit, 1 column -> cu 5
        // a: 1 code unit, 1 column -> cu 6
        // あ: 1 code unit, 2 columns -> cu 7
        // い: 1 code unit, 2 columns -> cu 8
        // う: 1 code unit, 2 columns -> cu 9
        // え: 1 code unit, 2 columns -> cu 10
        // お: 1 code unit, 2 columns -> cu 11

        expect(FontCalculator.columnToCharOffset(text, 0), equals(0));  // Start
        expect(FontCalculator.columnToCharOffset(text, 2), equals(1));  // After ＊, start of ✡
        expect(FontCalculator.columnToCharOffset(text, 4), equals(3));  // After ✡️, start of 💩
        expect(FontCalculator.columnToCharOffset(text, 6), equals(5));  // After 💩, start of first 'a'
        expect(FontCalculator.columnToCharOffset(text, 8), equals(7));  // After 'aa', start of 'あ'
        expect(FontCalculator.columnToCharOffset(text, 18), equals(12)); // End of text
      });

      test('handles text with multiple surrogate pairs', () {
        const text = '💩💩a'; // 2 + 2 + 1 = 5 columns, 2 + 2 + 1 = 5 code units
        expect(FontCalculator.columnToCharOffset(text, 0), equals(0));
        expect(FontCalculator.columnToCharOffset(text, 2), equals(2)); // After first 💩
        expect(FontCalculator.columnToCharOffset(text, 4), equals(4)); // After second 💩
        expect(FontCalculator.columnToCharOffset(text, 5), equals(5)); // After 'a'
      });

      test('returns 0 for empty string', () {
        expect(FontCalculator.columnToCharOffset('', 0), equals(0));
        expect(FontCalculator.columnToCharOffset('', 5), equals(0));
      });
    });

    group('calculateMaxCols', () {
      test('画面幅からカラム数を計算する', () {
        final result = FontCalculator.calculateMaxCols(
          screenWidth: 800,
          fontSize: 14,
          fontFamily: 'JetBrains Mono',
        );
        expect(result, greaterThan(0));
        expect(result, lessThanOrEqualTo(999));
      });

      test('最小値10にクランプされる', () {
        final result = FontCalculator.calculateMaxCols(
          screenWidth: 10,
          fontSize: 100,
          fontFamily: 'JetBrains Mono',
        );
        expect(result, greaterThanOrEqualTo(10));
      });
    });

    group('calculateMaxRows', () {
      test('画面高さから行数を計算する', () {
        final result = FontCalculator.calculateMaxRows(
          screenHeight: 600,
          fontSize: 14,
          fontFamily: 'JetBrains Mono',
        );
        expect(result, greaterThan(0));
        expect(result, lessThanOrEqualTo(999));
      });

      test('最小値5にクランプされる', () {
        final result = FontCalculator.calculateMaxRows(
          screenHeight: 10,
          fontSize: 100,
          fontFamily: 'JetBrains Mono',
        );
        expect(result, greaterThanOrEqualTo(5));
      });
    });

    group('getCharDisplayWidthWithContext', () {
      test('returns 2 for emoji-eligible character followed by VS16', () {
        // ✡ (U+2721) followed by VS16 should be width 2
        expect(
          FontCalculator.getCharDisplayWidthWithContext(0x2721, 0xFE0F),
          equals(2),
        );
      });

      test('returns base width when not followed by VS16', () {
        // ✡ (U+2721) alone should be width 1
        expect(
          FontCalculator.getCharDisplayWidthWithContext(0x2721, null),
          equals(1),
        );
        expect(
          FontCalculator.getCharDisplayWidthWithContext(0x2721, 'a'.codeUnitAt(0)),
          equals(1),
        );
      });

      test('returns 0 for VS16 itself', () {
        expect(
          FontCalculator.getCharDisplayWidthWithContext(0xFE0F, null),
          equals(0),
        );
      });

      test('returns 2 for already wide character regardless of VS16', () {
        // 💩 (U+1F4A9) is already width 2
        expect(
          FontCalculator.getCharDisplayWidthWithContext(0x1F4A9, null),
          equals(2),
        );
        expect(
          FontCalculator.getCharDisplayWidthWithContext(0x1F4A9, 0xFE0F),
          equals(2),
        );
      });
    });
  });
}
