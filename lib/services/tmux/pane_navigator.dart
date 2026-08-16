import 'dart:ui' show Offset;

import 'tmux_models.dart';

/// スワイプ方向
// inventory: TMUX-NAV-005
enum SwipeDirection { up, down, left, right }

/// SwipeDirectionの方向反転
extension SwipeDirectionExtension on SwipeDirection {
  /// 反転した方向を返す（up↔down, left↔right）
  SwipeDirection get inverted => switch (this) {
    SwipeDirection.up => SwipeDirection.down,
    SwipeDirection.down => SwipeDirection.up,
    SwipeDirection.left => SwipeDirection.right,
    SwipeDirection.right => SwipeDirection.left,
  };
}

/// ペイン間の空間ナビゲーション
///
/// TmuxPaneのleft/top/width/heightフィールド（文字単位）を使用して
/// 隣接ペインを特定する。
///
/// tmuxのペイン間には1カラム/1行のセパレータがあるため、
/// 隣接ペインの座標は `current.left + current.width + 1` となる。
/// 隣接判定に `>=` を使用することで、セパレータ幅に依存しない。
// inventory: TMUX-NAV-001
class PaneNavigator {
  /// 指定方向の隣接ペインを検索
  ///
  /// [panes] 現在のウィンドウの全ペイン
  /// [current] アクティブペイン
  /// [direction] スワイプ方向
  /// 見つからなければnullを返す
  // inventory: TMUX-NAV-002
  static TmuxPane? findAdjacentPane({
    required List<TmuxPane> panes,
    required TmuxPane current,
    required SwipeDirection direction,
  }) {
    if (panes.length <= 1) return null;

    final candidates = <TmuxPane>[];

    for (final pane in panes) {
      if (pane.id == current.id) continue;

      switch (direction) {
        case SwipeDirection.right:
          // 右方向: ペインの左端が現在ペインの右端以上 + 垂直方向の重なりあり
          if (pane.left >= current.left + current.width &&
              _hasVerticalOverlap(current, pane)) {
            candidates.add(pane);
          }
        case SwipeDirection.left:
          // 左方向: ペインの右端が現在ペインの左端以下 + 垂直方向の重なりあり
          if (pane.left + pane.width <= current.left &&
              _hasVerticalOverlap(current, pane)) {
            candidates.add(pane);
          }
        case SwipeDirection.down:
          // 下方向: ペインの上端が現在ペインの下端以上 + 水平方向の重なりあり
          if (pane.top >= current.top + current.height &&
              _hasHorizontalOverlap(current, pane)) {
            candidates.add(pane);
          }
        case SwipeDirection.up:
          // 上方向: ペインの下端が現在ペインの上端以下 + 水平方向の重なりあり
          if (pane.top + pane.height <= current.top &&
              _hasHorizontalOverlap(current, pane)) {
            candidates.add(pane);
          }
      }
    }

    if (candidates.isEmpty) return null;

    // 最も近い候補を返す（重心間のマンハッタン距離）
    candidates.sort((a, b) {
      final distA = _manhattanDistance(current, a);
      final distB = _manhattanDistance(current, b);
      return distA.compareTo(distB);
    });

    return candidates.first;
  }

  /// 各方向に隣接ペインが存在するかのマップを返す
  // inventory: TMUX-NAV-003
  static Map<SwipeDirection, bool> getNavigableDirections({
    required List<TmuxPane> panes,
    required TmuxPane current,
  }) {
    return {
      for (final dir in SwipeDirection.values)
        dir:
            findAdjacentPane(panes: panes, current: current, direction: dir) !=
            null,
    };
  }

  /// 2本指スワイプのdelta(dx, dy)からスワイプ方向を判定
  ///
  /// 移動量が[threshold]未満の場合はnullを返す
  // inventory: TMUX-NAV-004
  static SwipeDirection? detectSwipeDirection(
    Offset delta, {
    double threshold = 50.0,
  }) {
    final dx = delta.dx;
    final dy = delta.dy;
    if (dx.abs() > dy.abs()) {
      if (dx > threshold) return SwipeDirection.right;
      if (dx < -threshold) return SwipeDirection.left;
    } else {
      if (dy > threshold) return SwipeDirection.down;
      if (dy < -threshold) return SwipeDirection.up;
    }
    return null;
  }

  /// 垂直方向の重なりがあるか（水平移動時に使用）
  static bool _hasVerticalOverlap(TmuxPane a, TmuxPane b) {
    return b.top < a.top + a.height && b.top + b.height > a.top;
  }

  /// 水平方向の重なりがあるか（垂直移動時に使用）
  static bool _hasHorizontalOverlap(TmuxPane a, TmuxPane b) {
    return b.left < a.left + a.width && b.left + b.width > a.left;
  }

  /// 重心間のマンハッタン距離
  static double _manhattanDistance(TmuxPane a, TmuxPane b) {
    final aCenterX = a.left + a.width / 2.0;
    final aCenterY = a.top + a.height / 2.0;
    final bCenterX = b.left + b.width / 2.0;
    final bCenterY = b.top + b.height / 2.0;
    return (aCenterX - bCenterX).abs() + (aCenterY - bCenterY).abs();
  }
}
