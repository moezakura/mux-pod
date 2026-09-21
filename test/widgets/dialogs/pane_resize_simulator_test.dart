import 'package:flutter_muxpod/services/backend/domain/multiplexer_pane.dart';
import 'package:flutter_muxpod/widgets/dialogs/resize/pane_resize_simulator.dart';
import 'package:flutter_test/flutter_test.dart';

// simulatePaneResizeAbsolute（tmux resize-pane 簡易シミュレーション・純関数）の
// 単体テスト。アルゴリズムは resize_dialog.dart の旧 _simulatePaneResizeAbsolute
// から 1:1 移設（変更禁止）のため、期待値は仕様（Step1-4・identity 3 条件・
// clamp 境界）から直接計算したもの。

MultiplexerPane paneOf(List<MultiplexerPane> panes, String id) =>
    panes.firstWhere((p) => p.id == id);

void main() {
  // 横並び 2 pane fixture（0 起点・コンテナ 160x24）。
  const p1 = MultiplexerPane(
    index: 1,
    id: 'p1',
    left: 0,
    top: 0,
    width: 80,
    height: 24,
  );
  const p2 = MultiplexerPane(
    index: 2,
    id: 'p2',
    left: 80,
    top: 0,
    width: 80,
    height: 24,
  );

  group('simulatePaneResizeAbsolute', () {
    test('横並び 2 pane: target 幅変更・左隣幅が winW-hSep-colWidth に縮む', () {
      // 隙間 4 の横並び（hSep=4 になる前提・左隣判定は隙間 >= 1 が必要）。
      const gapP1 = MultiplexerPane(
        index: 1,
        id: 'gapP1',
        left: 0,
        top: 0,
        width: 80,
        height: 24,
      );
      const gapP2 = MultiplexerPane(
        index: 2,
        id: 'gapP2',
        left: 84,
        top: 0,
        width: 76,
        height: 24,
      );

      final result = simulatePaneResizeAbsolute(
        panes: const [gapP1, gapP2],
        targetId: 'gapP2',
        newCols: 100,
        newRows: 24,
      );

      expect(result.length, 2);
      // hSep = 84 - (0 + 80) = 4。winW = 160。
      // 左隣（gapP1）: 幅のみ変更（winW - hSep - colWidth = 160 - 4 - 100 = 56）。
      expect(paneOf(result, 'gapP1').left, 0);
      expect(paneOf(result, 'gapP1').top, 0);
      expect(paneOf(result, 'gapP1').width, 56);
      expect(paneOf(result, 'gapP1').height, 24);
      // target（gapP2）: left = leftNeighbors.first.left + leftWidth + hSep
      // = 0 + 56 + 4 = 60。
      expect(paneOf(result, 'gapP2').left, 60);
      expect(paneOf(result, 'gapP2').top, 0);
      expect(paneOf(result, 'gapP2').width, 100);
      expect(paneOf(result, 'gapP2').height, 24);
    });

    test('縦並び 2 pane: 高さ配分・残りは最後の他ペインが吸収', () {
      const v1 = MultiplexerPane(
        index: 1,
        id: 'v1',
        left: 0,
        top: 0,
        width: 80,
        height: 12,
      );
      const v2 = MultiplexerPane(
        index: 2,
        id: 'v2',
        left: 0,
        top: 12,
        width: 80,
        height: 12,
      );

      final result = simulatePaneResizeAbsolute(
        panes: const [v1, v2],
        targetId: 'v2',
        newCols: 80,
        newRows: 20,
      );

      // vSep = 12 - 12 = 0。availableH = 24、maxTargetH = 23 → targetH = 20。
      // remainingH = 4 → v1（最後の他ペイン）が全て吸収。
      expect(paneOf(result, 'v1').top, 0);
      expect(paneOf(result, 'v1').height, 4);
      expect(paneOf(result, 'v2').top, 4);
      expect(paneOf(result, 'v2').height, 20);
    });

    test('縦並び 3 pane: 比率配分 + 端数は最後の他ペインが吸収', () {
      const a = MultiplexerPane(
        index: 1,
        id: 'a',
        left: 0,
        top: 0,
        width: 80,
        height: 8,
      );
      const b = MultiplexerPane(
        index: 2,
        id: 'b',
        left: 0,
        top: 8,
        width: 80,
        height: 8,
      );
      const c = MultiplexerPane(
        index: 3,
        id: 'c',
        left: 0,
        top: 16,
        width: 80,
        height: 8,
      );

      final result = simulatePaneResizeAbsolute(
        panes: const [a, b, c],
        targetId: 'c',
        newCols: 80,
        newRows: 13,
      );

      // availableH = 24、otherCount = 2、maxTargetH = 22 → targetH = 13。
      // remainingH = 11、otherSum = 16:
      //   a = round(11 * 8 / 16) = round(5.5) = 6（比率配分）
      //   b = 11 - 6 = 5（最後が残りを吸収）
      // tops: a→0、b→6、c→11。
      expect(paneOf(result, 'a').top, 0);
      expect(paneOf(result, 'a').height, 6);
      expect(paneOf(result, 'b').top, 6);
      expect(paneOf(result, 'b').height, 5);
      expect(paneOf(result, 'c').top, 11);
      expect(paneOf(result, 'c').height, 13);
    });

    test('左隣なし（target が左端）: 位置は元のまま・右隣は不変', () {
      final result = simulatePaneResizeAbsolute(
        panes: const [p1, p2],
        targetId: 'p1',
        newCols: 100,
        newRows: 24,
      );

      // colWidth = 100.clamp(1, 160) = 100。左隣なし → newColLeft = 0。
      expect(paneOf(result, 'p1').left, 0);
      expect(paneOf(result, 'p1').top, 0);
      expect(paneOf(result, 'p1').width, 100);
      expect(paneOf(result, 'p1').height, 24);
      // カラム外（右隣）は変化なし。
      expect(paneOf(result, 'p2').left, 80);
      expect(paneOf(result, 'p2').width, 80);
      expect(paneOf(result, 'p2').height, 24);
    });

    test('identity: panes 空は入力リストをそのまま返す', () {
      const input = <MultiplexerPane>[];
      final result = simulatePaneResizeAbsolute(
        panes: input,
        targetId: 'p1',
        newCols: 100,
        newRows: 24,
      );

      expect(identical(result, input), isTrue);
      expect(result, isEmpty);
    });

    test('identity: 対象 ID 不在は入力リストをそのまま返す', () {
      const input = [p1, p2];
      final result = simulatePaneResizeAbsolute(
        panes: input,
        targetId: 'missing',
        newCols: 100,
        newRows: 24,
      );

      expect(identical(result, input), isTrue);
    });

    test('identity: winW == 0 は入力リストをそのまま返す', () {
      // target は存在するが全 pane の width が 0 → winW == 0。
      const z = MultiplexerPane(index: 1, id: 'z', left: 0, top: 0);
      const input = [z];
      final result = simulatePaneResizeAbsolute(
        panes: input,
        targetId: 'z',
        newCols: 100,
        newRows: 24,
      );

      expect(identical(result, input), isTrue);
    });

    test('clamp: newCols/newRows = 0 は最小 1 にクランプされる', () {
      // 隙間 4 の横並び（左隣あり・hSep = 4）。
      const gapP1 = MultiplexerPane(
        index: 1,
        id: 'gapP1',
        left: 0,
        top: 0,
        width: 80,
        height: 24,
      );
      const gapP2 = MultiplexerPane(
        index: 2,
        id: 'gapP2',
        left: 84,
        top: 0,
        width: 76,
        height: 24,
      );

      final result = simulatePaneResizeAbsolute(
        panes: const [gapP1, gapP2],
        targetId: 'gapP2',
        newCols: 0,
        newRows: 0,
      );

      // colWidth = 0.clamp(1, winW - hSep - 1 = 155) = 1。
      // leftWidth = max(1, 160 - 4 - 1) = 155。
      expect(paneOf(result, 'gapP1').width, 155);
      // newColLeft = 0 + 155 + 4 = 159。
      expect(paneOf(result, 'gapP2').left, 159);
      expect(paneOf(result, 'gapP2').width, 1);
      // targetH = 0.clamp(1, 24) = 1。
      expect(paneOf(result, 'gapP2').height, 1);
    });

    test('clamp: newCols/newRows が上限超過時は winW/availableH にクランプ', () {
      // 隙間 4 の横並び（左隣あり・hSep = 4）。
      const gapP1 = MultiplexerPane(
        index: 1,
        id: 'gapP1',
        left: 0,
        top: 0,
        width: 80,
        height: 24,
      );
      const gapP2 = MultiplexerPane(
        index: 2,
        id: 'gapP2',
        left: 84,
        top: 0,
        width: 76,
        height: 24,
      );

      final result = simulatePaneResizeAbsolute(
        panes: const [gapP1, gapP2],
        targetId: 'gapP2',
        newCols: 500,
        newRows: 100,
      );

      // colWidth = 500.clamp(1, 155) = 155。leftWidth = max(1, 160 - 4 - 155) = 1。
      expect(paneOf(result, 'gapP1').width, 1);
      // newColLeft = 0 + 1 + 4 = 5。
      expect(paneOf(result, 'gapP2').left, 5);
      expect(paneOf(result, 'gapP2').width, 155);
      // targetH = 100.clamp(1, 24) = 24。
      expect(paneOf(result, 'gapP2').height, 24);
    });
  });
}
