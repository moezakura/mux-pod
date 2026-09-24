import '../../../services/herdr/herdr_models.dart';
import '../../../services/tmux/pane_navigator.dart';

/// herdr: 現在表示中の pane の各方向に隣接 pane が存在するかを返す（純関数）。
///
/// snapshot の layout（pane の絶対座標 rect）から、[PaneNavigator] と同様の
/// 隣接判定を行う。snapshot 未取得時は null（スワイプヒント非表示）。
Map<SwipeDirection, bool>? herdrNavigableDirections({
  required String? paneId,
  required HerdrSnapshot? snapshot,
}) {
  if (paneId == null || snapshot == null) return null;

  // 現在の pane が属する layout（tab）を探す
  HerdrLayout? layout;
  for (final l in snapshot.layouts) {
    if (l.panes.any((p) => p.paneId == paneId)) {
      layout = l;
      break;
    }
  }
  if (layout == null) return null;

  final current = layout.panes.where((p) => p.paneId == paneId).firstOrNull;
  if (current == null) return null;

  return {
    for (final dir in SwipeDirection.values)
      dir: herdrHasAdjacentPane(layout.panes, current, dir),
  };
}

/// herdr layout 内で [current] の [direction] 方向に隣接 pane があるか判定。
bool herdrHasAdjacentPane(
  List<HerdrLayoutPane> panes,
  HerdrLayoutPane current,
  SwipeDirection direction,
) {
  if (panes.length <= 1) return false;
  for (final pane in panes) {
    if (pane.paneId == current.paneId) continue;
    final r = pane.rect;
    final c = current.rect;
    switch (direction) {
      case SwipeDirection.right:
        // 右: 左端が現在の右端以上 + 垂直方向の重なり
        if (r.x >= c.x + c.width && herdrVerticalOverlap(c, r)) {
          return true;
        }
      case SwipeDirection.left:
        // 左: 右端が現在の左端以下 + 垂直方向の重なり
        if (r.x + r.width <= c.x && herdrVerticalOverlap(c, r)) {
          return true;
        }
      case SwipeDirection.down:
        // 下: 上端が現在の下端以上 + 水平方向の重なり
        if (r.y >= c.y + c.height && herdrHorizontalOverlap(c, r)) {
          return true;
        }
      case SwipeDirection.up:
        // 上: 下端が現在の上端以下 + 水平方向の重なり
        if (r.y + r.height <= c.y && herdrHorizontalOverlap(c, r)) {
          return true;
        }
    }
  }
  return false;
}

bool herdrVerticalOverlap(HerdrRect a, HerdrRect b) =>
    a.y < b.y + b.height && b.y < a.y + a.height;

bool herdrHorizontalOverlap(HerdrRect a, HerdrRect b) =>
    a.x < b.x + b.width && b.x < a.x + a.width;

/// 方向の反転（`'right'` ↔ `'left'`・`'down'` ↔ `'up'`）。
String herdrOppositeDirection(String direction) {
  return switch (direction) {
    'right' => 'left',
    'left' => 'right',
    'down' => 'up',
    'up' => 'down',
    _ => 'right',
  };
}
