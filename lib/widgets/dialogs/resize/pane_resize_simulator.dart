import 'dart:math' as math;

import '../../../services/backend/domain/multiplexer_pane.dart';

/// tmux の resize-pane を簡易シミュレーションする（絶対 cols/rows・旧ロジック移植）。
///
/// サイズを先に決め、位置を全て再計算する。
/// 1. ウィンドウサイズとセパレータを算出
/// 2. 新しいサイズを決める（カラム幅、カラム内高さ配分）
/// 3. 位置を上から・左から再計算
/// 4. 結果組み立て（カラム内ペイン = copyWith / 左隣 = 幅のみ / その他 = 不変）
///
/// [MultiplexerPane] ベースに一般化した（[TmuxPane] は呼び出し側で
/// `toDomain()` 変換済み）。アルゴリズムは従来と同一のため、tmux 側
/// [ResizePaneDialog] のプレビュー結果は従来と同一である（互換維持・H-6）。
///
/// ガード/ identity 条件（panes 空 / 対象 ID 不在 / winW or winH == 0 のときは
/// 入力リストをそのまま返す）。resize ダイアログのプレビュー描画専用の純関数。
List<MultiplexerPane> simulatePaneResizeAbsolute({
  required List<MultiplexerPane> panes,
  required String targetId,
  required int newCols,
  required int newRows,
}) {
  if (panes.isEmpty) return panes;
  final target = panes.firstWhere(
    (p) => p.id == targetId,
    orElse: () => panes.first,
  );
  if (!panes.any((p) => p.id == targetId)) return panes;

  // === Step 1: ウィンドウサイズ・セパレータ算出 ===
  int winW = 0, winH = 0;
  for (final p in panes) {
    winW = math.max(winW, p.left + p.width);
    winH = math.max(winH, p.top + p.height);
  }
  if (winW == 0 || winH == 0) return panes;

  // 同一カラム（targetと同じleft）
  final colPanes = panes.where((p) => p.left == target.left).toList()
    ..sort((a, b) => a.top.compareTo(b.top));

  // 左隣ペイン（カラムの左に隣接し、垂直方向に重なるペイン）
  final leftNeighbors = panes
      .where(
        (p) =>
            p.left != target.left &&
            p.left + p.width < target.left &&
            colPanes.any(
              (cm) => p.top < cm.top + cm.height && p.top + p.height > cm.top,
            ),
      )
      .toList();

  // 水平セパレータ（カラムと左隣の隙間）
  int hSep = 1; // デフォルト
  if (leftNeighbors.isNotEmpty) {
    hSep = target.left - (leftNeighbors.first.left + leftNeighbors.first.width);
    if (hSep < 0) hSep = 1;
  }

  // 垂直セパレータ（カラム内ペイン間の隙間）
  int vSep = 1; // デフォルト
  if (colPanes.length >= 2) {
    vSep = colPanes[1].top - (colPanes[0].top + colPanes[0].height);
    if (vSep < 0) vSep = 1;
  }

  // === Step 2: 新しいサイズを決める ===

  // カラム幅（clamp: 最小1、最大winW - hSep - 左隣最小1）
  final maxColWidth = leftNeighbors.isNotEmpty ? winW - hSep - 1 : winW;
  final colWidth = newCols.clamp(1, maxColWidth);

  // 左隣幅
  final leftWidth = leftNeighbors.isNotEmpty
      ? math.max<int>(1, winW - hSep - colWidth)
      : 0;

  // カラム内高さ配分
  // カラムの総高さ（元のカラムが使っている高さ）
  final colTop = colPanes.first.top;
  final colBottom = colPanes.last.top + colPanes.last.height;
  final colTotalH = colBottom - colTop;
  final totalVSep = vSep * (colPanes.length - 1);
  final availableH = colTotalH - totalVSep;

  // ターゲットの新しい高さ（clamp: 最小1、最大=使用可能-他ペイン最小各1）
  final otherCount = colPanes.length - 1;
  final maxTargetH = availableH - otherCount; // 他ペインが各最小1
  final targetH = newRows.clamp(1, math.max<int>(1, maxTargetH));

  // 残りの高さを他ペインに元の比率で配分
  final int remainingH = math.max<int>(0, availableH - targetH);
  final otherOriginalSum = colPanes
      .where((p) => p.id != targetId)
      .fold<int>(0, (s, p) => s + p.height);

  final newHeights = <String, int>{};
  newHeights[targetId] = targetH;

  if (otherCount > 0 && otherOriginalSum > 0) {
    int distributed = 0;
    final others = colPanes.where((p) => p.id != targetId).toList();
    for (int i = 0; i < others.length; i++) {
      final p = others[i];
      if (i == others.length - 1) {
        // 最後のペインに残りを全て割り当て（端数調整）
        newHeights[p.id] = math.max<int>(1, remainingH - distributed);
      } else {
        final h = math.max(
          1,
          (remainingH * p.height / otherOriginalSum).round(),
        );
        newHeights[p.id] = h;
        distributed += h;
      }
    }
  }

  // === Step 3: 位置を再計算 ===

  // 左隣の新しいleft（元のまま）
  final newColLeft = leftNeighbors.isNotEmpty
      ? leftNeighbors.first.left + leftWidth + hSep
      : target.left; // 左隣がなければ元の位置

  // 左隣がなく、右隣がある場合
  // （カラムが左端にある場合は位置は0のまま）

  // カラム内のtopを上から再計算
  final newTops = <String, int>{};
  var currentTop = colTop;
  for (final p in colPanes) {
    newTops[p.id] = currentTop;
    currentTop += (newHeights[p.id] ?? p.height) + vSep;
  }

  // === Step 4: 結果組み立て ===
  return panes.map((p) {
    if (colPanes.any((cp) => cp.id == p.id)) {
      // カラム内ペイン
      return p.copyWith(
        left: newColLeft,
        top: newTops[p.id] ?? p.top,
        width: colWidth,
        height: newHeights[p.id] ?? p.height,
      );
    } else if (leftNeighbors.any((ln) => ln.id == p.id)) {
      // 左隣ペイン（幅変更、位置は元のまま）
      return p.copyWith(width: leftWidth);
    } else {
      // その他（変化なし）
      return p;
    }
  }).toList();
}
