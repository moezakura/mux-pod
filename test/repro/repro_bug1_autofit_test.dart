// Repro: バグ1 AutoFitモードが正しく動作しない
//
// 再現条件:
// - herdr バックエンド接続時、HerdrPaneContentReader は MultiplexerPaneSnapshot の
//   width/height を設定しない（= 0 のまま返す）
// - terminal_screen.dart の `w > 0 && h > 0` ガード（L1524-1530）がスキップされ、
//   paneWidth はデフォルト 80 のまま維持される
// - FontCalculator.calculate は paneCharWidth <= 0 を defaultPaneWidth (80) に
//   フォールバックする（L39-47）
// → AutoFit（画面幅に合わせてフォントサイズを調整）が常に paneWidth=80 で計算され、
//   実ペイン幅が 80 以外の場合は正しいフォントサイズにならない
//
// 期待される正しい動作: 実ペイン幅（文字セル単位）でフォントサイズを計算する
// 実際の動作（バグ）: paneWidth=80 固定で計算される
@Tags(['repro'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/font_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Repro BUG-1: AutoFit は herdr では paneWidth=80 固定で計算される', () {
    const screenWidth = 400.0; // テストスキャフォールドと同じ画面幅
    const minFontSize = 4.0; // クランプ回避のため低い最小値
    const fontFamily = 'JetBrains Mono';

    test('実ペイン幅 120 の場合は 80 の場合と異なるフォントサイズになる'
        '（herdr ではこの差分が発生しない）', () {
      final forWidePane = FontCalculator.calculate(
        screenWidth: screenWidth,
        paneCharWidth: 120, // 実ペイン幅（例: ワイド画面の herdr pane）
        fontFamily: fontFamily,
        minFontSize: minFontSize,
      );
      final forHerdr = FontCalculator.calculate(
        screenWidth: screenWidth,
        paneCharWidth: 0, // herdr が返す width（= 不明）
        fontFamily: fontFamily,
        minFontSize: minFontSize,
      );

      // herdr では width=0 → 80 フォールバックされるため、
      // 「実ペイン幅 120」の場合とは異なる結果になる。
      expect(
        forHerdr.fontSize,
        isNot(equals(forWidePane.fontSize)),
        reason:
            'バグ: herdr では paneWidth=0 が 80 にフォールバックされるため、'
            '実ペイン幅 120 に対する AutoFit 結果と一致しない',
      );
    });

    test('herdr の width=0 は defaultPaneWidth(80) と同一結果になる'
        '（= 実ペイン幅情報が AutoFit に一切使われない）', () {
      final forZero = FontCalculator.calculate(
        screenWidth: screenWidth,
        paneCharWidth: 0, // herdr の snapshot.width
        fontFamily: fontFamily,
        minFontSize: minFontSize,
      );
      final forDefault = FontCalculator.calculate(
        screenWidth: screenWidth,
        paneCharWidth: FontCalculator.defaultPaneWidth, // 80
        fontFamily: fontFamily,
        minFontSize: minFontSize,
      );

      expect(forZero.fontSize, equals(forDefault.fontSize));
      expect(forZero.needsScroll, equals(forDefault.needsScroll));
    });

    test('スクリーン幅が同じでも、paneCharWidth の違いで AutoFit 結果が変わるべき'
        '（herdr では paneCharWidth が常に 80 なので変化しない）', () {
      final narrow = FontCalculator.calculate(
        screenWidth: screenWidth,
        paneCharWidth: 40,
        fontFamily: fontFamily,
        minFontSize: minFontSize,
      );
      final herdr = FontCalculator.calculate(
        screenWidth: screenWidth,
        paneCharWidth: 0, // → 80 にフォールバック
        fontFamily: fontFamily,
        minFontSize: minFontSize,
      );

      // 実ペイン幅 40 なら 80 より大きなフォントになるはずだが、
      // herdr では width=0 → 80 なので「40 の結果」にならない。
      expect(
        herdr.fontSize,
        isNot(equals(narrow.fontSize)),
        reason: 'バグ: ペイン幅 40 の AutoFit 結果と herdr(width=0) の結果が一致しない',
      );
    });
  });
}
