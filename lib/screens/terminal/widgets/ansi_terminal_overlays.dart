import 'package:flutter/material.dart';

import '../../../services/tmux/pane_navigator.dart';
import '../../../theme/design_colors.dart';

/// ホールド+スワイプの視覚フィードバックオーバーレイ（P3-2・状態なし）。
class AnsiSwipeOverlay extends StatelessWidget {
  const AnsiSwipeOverlay({
    super.key,
    required this.isLongPressing,
    required this.lastSwipeDirection,
  });

  /// 長押し中か（透過率切替）。
  final bool isLongPressing;

  /// 最後に確定したスワイプ方向（'Up'/'Down'/'Left'/'Right'）。null は非確定。
  final String? lastSwipeDirection;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedOpacity(
        opacity: isLongPressing ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              // 上矢印
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Icon(
                  Icons.arrow_drop_up,
                  size: 40,
                  color: lastSwipeDirection == 'Up'
                      ? Colors.amber
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
              // 下矢印
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Icon(
                  Icons.arrow_drop_down,
                  size: 40,
                  color: lastSwipeDirection == 'Down'
                      ? Colors.amber
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
              // 左矢印
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Icon(
                  Icons.arrow_left,
                  size: 40,
                  color: lastSwipeDirection == 'Left'
                      ? Colors.amber
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
              // 右矢印
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Icon(
                  Icons.arrow_right,
                  size: 40,
                  color: lastSwipeDirection == 'Right'
                      ? Colors.amber
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
              // 中央の点
              Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 端到達時の赤系フラッシュ（P3-2・状態なし）。
class AnsiEdgeFlashOverlay extends StatelessWidget {
  const AnsiEdgeFlashOverlay({super.key, required this.direction});

  /// 端に到達した方向。
  final SwipeDirection direction;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (direction) {
      SwipeDirection.left => Alignment.centerLeft,
      SwipeDirection.right => Alignment.centerRight,
      SwipeDirection.up => Alignment.topCenter,
      SwipeDirection.down => Alignment.bottomCenter,
    };

    final isHorizontal =
        direction == SwipeDirection.left || direction == SwipeDirection.right;

    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: alignment,
          child: Container(
            width: isHorizontal ? 40 : double.infinity,
            height: isHorizontal ? double.infinity : 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: isHorizontal
                    ? (direction == SwipeDirection.left
                          ? Alignment.centerRight
                          : Alignment.centerLeft)
                    : (direction == SwipeDirection.up
                          ? Alignment.bottomCenter
                          : Alignment.topCenter),
                end: isHorizontal
                    ? (direction == SwipeDirection.left
                          ? Alignment.centerLeft
                          : Alignment.centerRight)
                    : (direction == SwipeDirection.up
                          ? Alignment.topCenter
                          : Alignment.bottomCenter),
                colors: [Colors.transparent, Colors.red.withValues(alpha: 0.4)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// パン中の方向グロー（P3-2・状態なし）。
class AnsiPanGlowOverlay extends StatelessWidget {
  const AnsiPanGlowOverlay({
    super.key,
    required this.panDelta,
    required this.navigableDirections,
  });

  /// 2 本指パンの累積移動量。
  final Offset panDelta;

  /// 各方向にペインが存在するかのマップ（ライブ参照のため build 毎に更新）。
  final Map<SwipeDirection, bool>? navigableDirections;

  @override
  Widget build(BuildContext context) {
    final dx = panDelta.dx;
    final dy = panDelta.dy;

    // 移動量が小さすぎる場合は表示しない
    if (dx.abs() < 20.0 && dy.abs() < 20.0) {
      return const SizedBox.shrink();
    }

    SwipeDirection? direction;
    if (dx.abs() > dy.abs()) {
      direction = dx > 0 ? SwipeDirection.right : SwipeDirection.left;
    } else {
      direction = dy > 0 ? SwipeDirection.down : SwipeDirection.up;
    }

    final canNavigate = navigableDirections?[direction] ?? true;
    final color = canNavigate
        ? DesignColors.primary.withValues(alpha: 0.2)
        : Colors.red.withValues(alpha: 0.15);

    final alignment = switch (direction) {
      SwipeDirection.left => Alignment.centerLeft,
      SwipeDirection.right => Alignment.centerRight,
      SwipeDirection.up => Alignment.topCenter,
      SwipeDirection.down => Alignment.bottomCenter,
    };

    final isHorizontal =
        direction == SwipeDirection.left || direction == SwipeDirection.right;

    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: alignment,
          child: Container(
            width: isHorizontal ? 30 : double.infinity,
            height: isHorizontal ? double.infinity : 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: isHorizontal
                    ? (direction == SwipeDirection.left
                          ? Alignment.centerRight
                          : Alignment.centerLeft)
                    : (direction == SwipeDirection.up
                          ? Alignment.bottomCenter
                          : Alignment.topCenter),
                end: isHorizontal
                    ? (direction == SwipeDirection.left
                          ? Alignment.centerLeft
                          : Alignment.centerRight)
                    : (direction == SwipeDirection.up
                          ? Alignment.topCenter
                          : Alignment.bottomCenter),
                colors: [Colors.transparent, color],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 2 本指スワイプの視覚フィードバックディスパッチャ（P3-2・状態なし）。
///
/// 端到達フラッシュ優先、次にパン中グロー、それ以外は非表示（SizedBox.shrink）。
class AnsiTwoFingerOverlay extends StatelessWidget {
  const AnsiTwoFingerOverlay({
    super.key,
    required this.twoFingerSwipeResult,
    required this.isTwoFingerPanning,
    required this.panDelta,
    required this.navigableDirections,
  });

  /// 端到達時のフラッシュ方向（null ならフラッシュなし）。
  final SwipeDirection? twoFingerSwipeResult;

  /// 2 本指パン中か。
  final bool isTwoFingerPanning;

  /// パン中の累積移動量。
  final Offset panDelta;

  /// 各方向にペインが存在するかのマップ。
  final Map<SwipeDirection, bool>? navigableDirections;

  @override
  Widget build(BuildContext context) {
    // 端到達時のフラッシュ表示
    if (twoFingerSwipeResult != null) {
      return AnsiEdgeFlashOverlay(direction: twoFingerSwipeResult!);
    }

    // パン中のエッジグロー表示
    if (isTwoFingerPanning) {
      return AnsiPanGlowOverlay(
        panDelta: panDelta,
        navigableDirections: navigableDirections,
      );
    }

    return const SizedBox.shrink();
  }
}
