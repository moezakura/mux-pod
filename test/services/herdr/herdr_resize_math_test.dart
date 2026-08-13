import 'package:flutter_muxpod/services/backend/domain/multiplexer_pane.dart';
import 'package:flutter_muxpod/services/herdr/herdr_resize_math.dart';
import 'package:flutter_test/flutter_test.dart';

// 期待値は herdr CLI 0.7.5 の実測契約（resize_conversion_notes.md §A/C/D/E・C-2）に基づく。
// このテストは「対象 share は常に +min(amount, 0.5)・[0.1,0.9] クランプ」を契約として固定する。
void main() {
  group('PaneResizeMath.applyDelta', () {
    test('実測値: 上側クランプ [0.1,0.9] で 0.95 が 0.9 になる', () {
      expect(PaneResizeMath.applyDelta(0.75, 0.2), 0.9);
    });

    test('実測値: delta 上限 0.5 適用（0.1 + min(0.7, 0.5) = 0.6）', () {
      expect(PaneResizeMath.applyDelta(0.1, 0.7), 0.6);
    });

    test('実測値: +0.05 ずつ成長（0.5 → 0.55 → 0.6 → 0.65）', () {
      // IEEE754 累積誤差のため浮動小数点比較（closeTo）で固定する。
      // backend（herdr CLI）は誤差を丸めず JSON に出し、実測でも 0.65000004 等が
      // 観測される（notes §A）。PaneResizeMath は backend 同式の純関数のため
      // 丸めは行わず、期待値は概念値 0.55 / 0.6 / 0.65 と等価であることを検証する。
      expect(PaneResizeMath.applyDelta(0.5, 0.05), closeTo(0.55, 1e-9));
      expect(PaneResizeMath.applyDelta(0.55, 0.05), closeTo(0.6, 1e-9));
      expect(PaneResizeMath.applyDelta(0.6, 0.05), closeTo(0.65, 1e-9));
    });

    test('負値は受け付けない: amount <= 0 は変化なし（delta 0）として固定', () {
      // UI は正値のみ送出する契約。負値クォーク（符号誤りによる逆拡大）を
      // 構造的に排除するため、ここで挙動を固定する。
      expect(PaneResizeMath.applyDelta(0.5, 0.0), 0.5);
      expect(PaneResizeMath.applyDelta(0.5, -0.3), 0.5);
    });

    test('下側クランプ [0.1,0.9]: 0.05 は 0.1 に持ち上げられる', () {
      expect(PaneResizeMath.applyDelta(0.05, 0.05), 0.1);
    });

    test('境界値: 0.9 からの加算は 0.9 のまま', () {
      expect(PaneResizeMath.applyDelta(0.9, 0.1), 0.9);
    });
  });

  group('PaneResizeMath.cellsFor', () {
    test('実測値: round(ratio × container)', () {
      expect(PaneResizeMath.cellsFor(0.5, 78), 39);
      expect(PaneResizeMath.cellsFor(0.55, 78), 43); // 42.9 → 43
      expect(PaneResizeMath.cellsFor(0.75, 78), 59); // 58.5 → 59（half away from zero）
    });

    test('0 除算ガード: container <= 0 は null', () {
      expect(PaneResizeMath.cellsFor(0.5, 0), isNull);
      expect(PaneResizeMath.cellsFor(0.5, -10), isNull);
    });
  });

  group('PaneResizeMath.estimateRatio', () {
    test('横並び 2 pane: 幅比率で推定される', () {
      const p1 = MultiplexerPane(index: 1, id: 'w1:p1', left: 0, top: 0, width: 50, height: 20);
      const p2 = MultiplexerPane(index: 2, id: 'w1:p2', left: 50, top: 0, width: 50, height: 20);
      expect(PaneResizeMath.estimateRatio(p1, [p1, p2]), 0.5);
      expect(PaneResizeMath.estimateRatio(p2, [p1, p2]), 0.5);
    });

    test('非 0 起点 fixture でも正規化により同一の比率になる', () {
      const p1 = MultiplexerPane(index: 1, id: 'w1:p1', left: 26, top: 1, width: 50, height: 20);
      const p2 = MultiplexerPane(index: 2, id: 'w1:p2', left: 76, top: 1, width: 50, height: 20);
      expect(PaneResizeMath.estimateRatio(p1, [p1, p2]), 0.5);
    });

    test('縦並び 2 pane: 高さ比率で推定される', () {
      const top = MultiplexerPane(index: 1, id: 'w1:p1', left: 0, top: 0, width: 100, height: 20);
      const bottom = MultiplexerPane(index: 2, id: 'w1:p2', left: 0, top: 20, width: 100, height: 20);
      expect(PaneResizeMath.estimateRatio(top, [top, bottom]), 0.5);
      expect(PaneResizeMath.estimateRatio(bottom, [top, bottom]), 0.5);
    });

    test('1 pane のみ: paneWidth == containerWidth なので高さ比率パスになる', () {
      // 幅がコンテナ幅と等しい（横分割でない）ため高さ比率 20/20 = 1.0
      const single = MultiplexerPane(index: 1, id: 'w1:p1', left: 0, top: 0, width: 100, height: 20);
      expect(PaneResizeMath.estimateRatio(single, [single]), 1.0);
    });

    test('サイズ不明（width=0）は null（0 除算しない・E1）', () {
      const p1 = MultiplexerPane(index: 1, id: 'w1:p1', left: 0, top: 0, width: 0, height: 20);
      const p2 = MultiplexerPane(index: 2, id: 'w1:p2', left: 50, top: 0, width: 50, height: 20);
      expect(PaneResizeMath.estimateRatio(p1, [p1, p2]), isNull);
    });

    test('panes 内にサイズ不明 pane が含まれる場合も null', () {
      const p1 = MultiplexerPane(index: 1, id: 'w1:p1', left: 0, top: 0, width: 50, height: 20);
      const p2 = MultiplexerPane(index: 2, id: 'w1:p2', left: 50, top: 0, width: 0, height: 20);
      expect(PaneResizeMath.estimateRatio(p1, [p1, p2]), isNull);
    });

    test('空リストは null', () {
      const p1 = MultiplexerPane(index: 1, id: 'w1:p1', left: 0, top: 0, width: 50, height: 20);
      expect(PaneResizeMath.estimateRatio(p1, const []), isNull);
    });
  });

  group('PaneResizeMath.absoluteToDelta', () {
    test('実測値: コンテナ 78・39→43 セル（4 セル増 = ratio 0.05 相当・notes §A）', () {
      // 39 = round(0.5×78)・43 = round(0.55×78)。差は 4/78 ≈ 0.0513（ratio 0.05 相当）。
      final delta = PaneResizeMath.absoluteToDelta(
        currentCells: 39,
        targetCells: 43,
        containerCells: 78,
      );
      expect(delta, closeTo(4 / 78, 1e-9));
      expect(delta, greaterThan(0));
    });

    test('実測値: 縮小（43→39 セル）は負の delta を返す', () {
      final delta = PaneResizeMath.absoluteToDelta(
        currentCells: 43,
        targetCells: 39,
        containerCells: 78,
      );
      expect(delta, closeTo(-4 / 78, 1e-9));
      expect(delta, lessThan(0));
    });

    test('実測値: 39→59 セル（20 セル増 = ratio 0.25 相当）', () {
      final delta = PaneResizeMath.absoluteToDelta(
        currentCells: 39,
        targetCells: 59,
        containerCells: 78,
      );
      expect(delta, closeTo(20 / 78, 1e-9));
    });

    test('delta 上限 0.5（notes §D）: 0.5 を超える要求は 0.5 にキャップ', () {
      // (90-39)/78 = 0.6538 → clamp 0.5
      expect(
        PaneResizeMath.absoluteToDelta(
          currentCells: 39,
          targetCells: 90,
          containerCells: 78,
        ),
        0.5,
      );
      // (0-39)/78 = -0.5（ちょうど下限）
      expect(
        PaneResizeMath.absoluteToDelta(
          currentCells: 39,
          targetCells: 0,
          containerCells: 78,
        ),
        -0.5,
      );
    });

    test('0 除算ガード: containerCells <= 0 は null', () {
      expect(
        PaneResizeMath.absoluteToDelta(
          currentCells: 39,
          targetCells: 43,
          containerCells: 0,
        ),
        isNull,
      );
      expect(
        PaneResizeMath.absoluteToDelta(
          currentCells: 39,
          targetCells: 43,
          containerCells: -10,
        ),
        isNull,
      );
    });
  });

  group('PaneResizeMath.resolveDirection', () {
    // 横並び 2 pane（0 起点・コンテナ 100x20）。
    const p1 = MultiplexerPane(index: 1, id: 'w1:p1', left: 0, top: 0, width: 50, height: 20);
    const p2 = MultiplexerPane(index: 2, id: 'w1:p2', left: 50, top: 0, width: 50, height: 20);

    test('横並び 2 pane: 左端は右隣があるので right・右端は left', () {
      expect(
        PaneResizeMath.resolveDirection(
          target: p1,
          panes: [p1, p2],
          horizontal: true,
          grow: true,
        ),
        'right',
      );
      expect(
        PaneResizeMath.resolveDirection(
          target: p2,
          panes: [p1, p2],
          horizontal: true,
          grow: true,
        ),
        'left',
      );
    });

    test('縦並び 2 pane: 上は下隣があるので down・下は up', () {
      const top = MultiplexerPane(index: 1, id: 'w1:p1', left: 0, top: 0, width: 100, height: 20);
      const bottom = MultiplexerPane(index: 2, id: 'w1:p2', left: 0, top: 20, width: 100, height: 20);
      expect(
        PaneResizeMath.resolveDirection(
          target: top,
          panes: [top, bottom],
          horizontal: false,
          grow: true,
        ),
        'down',
      );
      expect(
        PaneResizeMath.resolveDirection(
          target: bottom,
          panes: [top, bottom],
          horizontal: false,
          grow: true,
        ),
        'up',
      );
    });

    test('3 pane 真ん中: 両隣ありは grow で優先方向が変わる', () {
      const p3 = MultiplexerPane(index: 3, id: 'w1:p3', left: 100, top: 0, width: 50, height: 20);
      // grow=true（対象を成長）: 右優先。
      expect(
        PaneResizeMath.resolveDirection(
          target: p2,
          panes: [p1, p2, p3],
          horizontal: true,
          grow: true,
        ),
        'right',
      );
      // grow=false（対象を縮小 = 隣接を成長）: 左優先。
      expect(
        PaneResizeMath.resolveDirection(
          target: p2,
          panes: [p1, p2, p3],
          horizontal: true,
          grow: false,
        ),
        'left',
      );
    });

    test('隣接なし（1 pane）は null', () {
      expect(
        PaneResizeMath.resolveDirection(
          target: p1,
          panes: [p1],
          horizontal: true,
          grow: true,
        ),
        isNull,
      );
    });

    test('サイズ不明（width=0）の pane は判定対象外（null）', () {
      const unknown = MultiplexerPane(index: 1, id: 'w1:p1', left: 0, top: 0, width: 0, height: 20);
      expect(
        PaneResizeMath.resolveDirection(
          target: unknown,
          panes: [unknown, p2],
          horizontal: true,
          grow: true,
        ),
        isNull,
      );
    });
  });
}
