import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/font_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });
}
