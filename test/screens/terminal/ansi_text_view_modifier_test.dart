import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';

/// Issue #116 修正（Alt/Meta + 非 ASCII 合成文字時に logicalKey から
/// ASCII 文字を導出）のコアロジックに対するユニットテスト。
///
/// 対象: AnsiTextViewState.isAsciiPrintable / AnsiTextViewState.deriveBaseChar
/// （@visibleForTesting で公開。動作は本修正で追加したものであり、
/// 今後この近傍を変更しても契約が破壊されないことをここで固定する）。
void main() {
  group('isAsciiPrintable (0x20-0x7E 単一文字判定)', () {
    test('空文字列は false', () {
      expect(AnsiTextViewState.isAsciiPrintable(''), isFalse);
    });

    test('2 文字以上は false', () {
      expect(AnsiTextViewState.isAsciiPrintable('ab'), isFalse);
      expect(AnsiTextViewState.isAsciiPrintable('Intl Yen'), isFalse);
    });

    test('境界: 0x20 (SPC) と 0x7E (~) は true', () {
      expect(AnsiTextViewState.isAsciiPrintable(' '), isTrue);
      expect(AnsiTextViewState.isAsciiPrintable('~'), isTrue);
    });

    test('境界外: 0x1F, 0x7F は false', () {
      expect(AnsiTextViewState.isAsciiPrintable('\x1f'), isFalse);
      expect(AnsiTextViewState.isAsciiPrintable('\x7f'), isFalse);
    });

    test('非 ASCII 合成文字 (ø U+00F8) は false', () {
      expect(AnsiTextViewState.isAsciiPrintable('ø'), isFalse);
    });

    test('ASCII 印字可能文字は true (代表例)', () {
      for (final s in ['A', 'z', '0', '9', ',', '.', '/', ';', '[', '-']) {
        expect(AnsiTextViewState.isAsciiPrintable(s), isTrue, reason: s);
      }
    });

    test('サロゲートペア (絵文字, length==2) は false', () {
      expect(AnsiTextViewState.isAsciiPrintable('😀'), isFalse);
    });
  });

  group('deriveBaseChar (keyLabel から ASCII 文字導出)', () {
    group('英字 (非 Shift は小文字化 R1)', () {
      test("keyO ('O') → o (Shift なし)", () {
        expect(AnsiTextViewState().deriveBaseChar('O'), 'o');
      });

      test("keyO ('O') → O (Shift あり)", () {
        expect(
          AnsiTextViewState().deriveBaseChar('O', shiftPressed: true),
          'O',
        );
      });

      test("keyA〜keyZ ('A'〜'Z') の全26字を網羅 (Shift なし → 小文字)", () {
        for (final key in [
          LogicalKeyboardKey.keyA,
          LogicalKeyboardKey.keyB,
          LogicalKeyboardKey.keyC,
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.keyE,
          LogicalKeyboardKey.keyF,
          LogicalKeyboardKey.keyG,
          LogicalKeyboardKey.keyH,
          LogicalKeyboardKey.keyI,
          LogicalKeyboardKey.keyJ,
          LogicalKeyboardKey.keyK,
          LogicalKeyboardKey.keyL,
          LogicalKeyboardKey.keyM,
          LogicalKeyboardKey.keyN,
          LogicalKeyboardKey.keyO,
          LogicalKeyboardKey.keyP,
          LogicalKeyboardKey.keyQ,
          LogicalKeyboardKey.keyR,
          LogicalKeyboardKey.keyS,
          LogicalKeyboardKey.keyT,
          LogicalKeyboardKey.keyU,
          LogicalKeyboardKey.keyV,
          LogicalKeyboardKey.keyW,
          LogicalKeyboardKey.keyX,
          LogicalKeyboardKey.keyY,
          LogicalKeyboardKey.keyZ,
        ]) {
          final expected = key.keyLabel.toLowerCase();
          expect(
            AnsiTextViewState().deriveBaseChar(key.keyLabel),
            expected,
            reason: 'key=${key.keyLabel}',
          );
        }
      });

      test("keyA / keyZ (Shift あり → 大文字のまま)", () {
        expect(
          AnsiTextViewState().deriveBaseChar('A', shiftPressed: true),
          'A',
        );
        expect(
          AnsiTextViewState().deriveBaseChar('Z', shiftPressed: true),
          'Z',
        );
      });
    });

    group('数字 (0-9)', () {
      test("'0'〜'9' → 同一文字 (Shift 有無で不変)", () {
        for (final c in ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']) {
          expect(AnsiTextViewState().deriveBaseChar(c), c, reason: 'label=$c');
          expect(
            AnsiTextViewState().deriveBaseChar(c, shiftPressed: true),
            c,
            reason: 'label=$c (with shift)',
          );
        }
      });
    });

    group('記号', () {
      test('主要記号 → 同一 ASCII 記号', () {
        for (final c in [
          ',',
          '.',
          '/',
          ';',
          '-',
          '=',
          '`',
          '[',
          ']',
          '\\',
          "'",
        ]) {
          expect(AnsiTextViewState().deriveBaseChar(c), c, reason: 'label=$c');
        }
      });

      test("Space (' ') → SPC", () {
        expect(AnsiTextViewState().deriveBaseChar(' '), ' ');
      });
    });

    group('導出不能キーは null (従来動作へフォールバック R3)', () {
      test("keyLabel が複数文字 ('Intl Yen' = JIS ¥ キー相当) は null", () {
        expect(AnsiTextViewState().deriveBaseChar('Intl Yen'), isNull);
      });

      test('keyLabel が空文字列は null', () {
        expect(AnsiTextViewState().deriveBaseChar(''), isNull);
      });

      test("keyLabel が非 ASCII ('Ù') は null", () {
        expect(AnsiTextViewState().deriveBaseChar('Ù'), isNull);
      });

      test('keyLabel が制御文字 (0x00-0x1F) は null', () {
        expect(AnsiTextViewState().deriveBaseChar('\x01'), isNull);
        expect(AnsiTextViewState().deriveBaseChar('\x1f'), isNull);
      });

      test('keyLabel が 0x7F (DEL) は null', () {
        expect(AnsiTextViewState().deriveBaseChar('\x7f'), isNull);
      });
    });
  });
}
