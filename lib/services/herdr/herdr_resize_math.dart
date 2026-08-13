import 'dart:math' as math;

import '../backend/domain/multiplexer_pane.dart';

/// herdr リサイズの backend 同式計算を提供する純関数群。
///
/// **herdr CLI 0.7.5 実測契約（resize_conversion_notes.md）ベース**。
/// このクラスは herdr 専用契約であり、tmux 等の他バックエンドの仕様を
/// 表すものではない（E8: 配置を lib/services/herdr/ に置く理由）。
///
/// 実測契約の要点（notes §A/C/D/E・C-2）:
/// - amount は現在 ratio への**加算**（対象 share は常に成長・縮小方向は存在しない。
///   負値は絶対値扱いのため、UI に負値を出さない契約と併せて本クラスは
///   amount <= 0 を変化なしとして扱う）。
/// - 1 回の delta 上限は 0.5、結果 ratio は [0.1, 0.9] にクランプ。
/// - セル換算は round(ratio × コンテナ)。
/// - 境界外（[0.1,0.9] を外れる操作）は changed:false となり実質 noop。
///
/// 全メソッドは純関数: **throw せず return・sync・副作用なし**。
/// サイズ不明・引数不正は例外にせず null / false で表現する。
class PaneResizeMath {
  PaneResizeMath._();

  /// 対象 pane の share を amount だけ成長させた結果を返す。
  ///
  /// - 対象は常に成長（縮小方向なし・C-2）: `ratio + delta`
  /// - delta = `min(amount, 0.5)`（1 回の上限 0.5・notes §D）
  /// - 結果は [0.1, 0.9] にクランプ（notes §C）
  /// - [amount] <= 0 は delta 0（変化なし）として扱う。herdr CLI は負値を
  ///   絶対値扱いする実測があるが、UI は正値のみを送出する契約のため、
  ///   ここで負値クォーク（符号誤りによる逆拡大・R1）を構造的に排除する。
  static double applyDelta(double ratio, double amount) {
    final delta = amount > 0 ? math.min(amount, 0.5) : 0.0;
    return (ratio + delta).clamp(0.1, 0.9).toDouble();
  }

  /// ratio をコンテナサイズのセル数へ換算する。
  ///
  /// 実測契約: `round(ratio × container)`（notes §A）。
  /// [container] <= 0 は 0 除算になるため null を返す（ガード）。
  static int? cellsFor(double ratio, int container) {
    if (container <= 0) return null;
    return (ratio * container).round();
  }

  /// 0 起点正規化した rect から対象 pane のシェア比率を概算推定する。
  ///
  /// `MultiplexerPane` は ratio を持たない（F6）ため、プレビューでは rect から
  /// 概算推定した比率を用いる（ユーザー決定8・「概算(estimated)」表示）。
  ///
  /// - 横分割（左右に並ぶ）: pane の幅がコンテナ幅より狭い → 幅比率
  /// - 縦分割（上下に並ぶ）: 上記以外 → 高さ比率
  /// - サイズ不明（[pane] または [panes] 内の width/height <= 0・コンテナ
  ///   サイズが 0 以下）は null（0 除算しない・E1）
  static double? estimateRatio(MultiplexerPane pane, List<MultiplexerPane> panes) {
    if (panes.isEmpty) return null;
    if (pane.width <= 0 || pane.height <= 0) return null;

    // 0 起点へ正規化（全 pane の min を引く・L6527-6547 と同方式）。
    var minLeft = panes.first.left;
    var minTop = panes.first.top;
    var maxRight = 0;
    var maxBottom = 0;
    for (final p in panes) {
      if (p.width <= 0 || p.height <= 0) return null;
      final right = p.left + p.width;
      final bottom = p.top + p.height;
      if (p.left < minLeft) minLeft = p.left;
      if (p.top < minTop) minTop = p.top;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }

    final containerWidth = maxRight - minLeft;
    final containerHeight = maxBottom - minTop;
    if (containerWidth <= 0 || containerHeight <= 0) return null;

    final paneWidth = pane.width.toDouble();
    if (paneWidth < containerWidth) {
      return (paneWidth / containerWidth).clamp(0.0, 1.0);
    }
    return (pane.height.toDouble() / containerHeight).clamp(0.0, 1.0);
  }

  /// 絶対セル数（Cols/Rows）の変更量を相対量（amount）へ換算する。
  ///
  /// [currentCells]（現在のセル数）から [targetCells]（目標セル数）への変化を、
  /// コンテナサイズ [containerCells] に対する ratio 差として返す。
  ///
  /// - 換算式: `delta = targetCells/containerCells - currentCells/containerCells`
  /// - 1 回の呼び出しあたりの delta 上限 0.5 を適用（notes §D）:
  ///   `clamp(-0.5, 0.5)`（**符号付き**: 正 = 成長・負 = 縮小）
  /// - [containerCells] <= 0 は 0 除算になるため null（ガード）
  /// - throw せず return・sync・副作用なし
  ///
  /// この delta を [PaneResizeMath.resolveDirection] で決めた方向に沿って
  /// `pane resize --amount <|delta|>` として送る（バックエンド契約不変・Q-04）。
  static double? absoluteToDelta({
    required int currentCells,
    required int targetCells,
    required int containerCells,
  }) {
    if (containerCells <= 0) return null;
    final currentRatio = currentCells / containerCells;
    final targetRatio = targetCells / containerCells;
    final delta = targetRatio - currentRatio;
    return delta.clamp(-0.5, 0.5).toDouble();
  }

  /// 対象 pane の share を増減させるために操作する隣接側の方向を返す。
  ///
  /// 戻り値の意味（呼び出し側の送信先・方向の決定に使う）:
  /// - [grow] = true: [target] を**成長させる方向**。右（下）隣があれば
  ///   `'right'`（`'down'`）、左（上）隣があれば `'left'`（`'up'`）。
  ///   呼び出し側は `writer.resizePane(target.id, 戻り値, |delta|)` を送る。
  /// - [grow] = false: [target] を**縮小させる側**。右（下）隣があれば
  ///   `'right'`（`'down'`）= その隣接 pane を成長させて target を縮める。
  ///   呼び出し側はその隣接 pane を特定し、隣接から見て target 側
  ///   （戻り値の反対方向）へ `|delta|` を送る。
  /// - 両方向に隣接がある場合は [grow] で優先方向を選ぶ（true → 右/下・
  ///   false → 左/上）。
  /// - 隣接が無い場合は null（送信しない・backend が noop を返す経路と同等）。
  ///
  /// 隣接判定は rect の重なり（絶対座標のまま）:
  /// - 横方向（[horizontal] = true）: 縦範囲が重なり、かつ target の右端より
  ///   左端が右にある pane = 右隣 / target の左端より右端が左にある pane = 左隣
  /// - 縦方向（[horizontal] = false）: 横範囲が重なり、かつ下/上に同様に判定
  /// - サイズ不明（width/height <= 0）の pane は判定対象外（E1）
  ///
  /// throw せず return・sync・副作用なし。
  static String? resolveDirection({
    required MultiplexerPane target,
    required List<MultiplexerPane> panes,
    required bool horizontal,
    required bool grow,
  }) {
    if (target.width <= 0 || target.height <= 0) return null;

    final right = target.left + target.width;
    final bottom = target.top + target.height;

    var hasRight = false;
    var hasLeft = false;
    var hasDown = false;
    var hasUp = false;
    for (final p in panes) {
      if (p.id == target.id) continue;
      if (p.width <= 0 || p.height <= 0) continue;
      final overlapsVertically =
          p.top < bottom && p.top + p.height > target.top;
      final overlapsHorizontally =
          p.left < right && p.left + p.width > target.left;
      if (horizontal) {
        if (p.left >= right && overlapsVertically) {
          hasRight = true;
        } else if (p.left + p.width <= target.left && overlapsVertically) {
          hasLeft = true;
        }
      } else {
        if (p.top >= bottom && overlapsHorizontally) {
          hasDown = true;
        } else if (p.top + p.height <= target.top && overlapsHorizontally) {
          hasUp = true;
        }
      }
    }

    if (horizontal) {
      if (hasRight && (grow || !hasLeft)) return 'right';
      if (hasLeft) return 'left';
      return null;
    }
    if (hasDown && (grow || !hasUp)) return 'down';
    if (hasUp) return 'up';
    return null;
  }
}
