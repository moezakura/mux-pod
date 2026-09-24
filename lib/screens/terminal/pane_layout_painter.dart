import 'package:flutter/material.dart';

import '../../services/backend/domain/multiplexer_pane.dart';

/// ペインレイアウトを描画するCustomPainter
///
/// 共通 domain 型（[MultiplexerPane]）の pane リストから、pane_left/pane_top を
/// 使用して実際のレイアウトを正確に再現する（tmux / herdr 共通・クラス名維持: テスト
/// helper `paneIndicatorPainter()` が runtimeType で判別するため）。
class _PaneLayoutPainter extends CustomPainter {
  final List<MultiplexerPane> panes;
  final String? activePaneId;
  // inventory: LEGACY-0080
  final Color activeColor;
  final bool isDark;

  _PaneLayoutPainter({
    required this.panes,
    this.activePaneId,
    required this.activeColor,
    required this.isDark,
  });

  @override
  // inventory: LEGACY-0082
  void paint(Canvas canvas, Size size) {
    if (panes.isEmpty) return;

    // 全 pane の min を 0 起点へ正規化する（PaneLayoutVisualizer と同一の
    // 幾何学）。herdr の layout rect は 0 起点でないため（実測 x:26 / y:1）、
    // min を引いて 0 起点へ揃える。tmux は 0 起点パースのため正規化は恒等。
    var minLeft = panes.first.left;
    var minTop = panes.first.top;
    int maxRight = 0;
    int maxBottom = 0;
    for (final pane in panes) {
      final right = pane.left + pane.width;
      final bottom = pane.top + pane.height;
      if (pane.left < minLeft) minLeft = pane.left;
      if (pane.top < minTop) minTop = pane.top;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }

    if (maxRight == 0 || maxBottom == 0) return;

    // 0 起点へ正規化した全体サイズ
    maxRight -= minLeft;
    maxBottom -= minTop;
    if (maxRight == 0 || maxBottom == 0) return;

    // スケール係数を計算
    final scaleX = size.width / maxRight;
    final scaleY = size.height / maxBottom;
    final gap = 1.0;

    // ペインごとに描画
    for (final pane in panes) {
      final isActive = pane.id == activePaneId;

      // 実際の位置とサイズからRectを計算（0 起点へ正規化済み）
      final left = (pane.left - minLeft) * scaleX;
      final top = (pane.top - minTop) * scaleY;
      final width = pane.width * scaleX - gap;
      final height = pane.height * scaleY - gap;

      final rect = Rect.fromLTWH(left, top, width, height);

      // 背景
      final bgPaint = Paint()
        ..color = isActive
            ? activeColor.withValues(alpha: 0.3)
            : (isDark ? Colors.black45 : Colors.grey.shade300);
      canvas.drawRect(rect, bgPaint);

      // 枠線
      final borderPaint = Paint()
        ..color = isActive
            ? activeColor
            : (isDark ? Colors.white30 : Colors.grey.shade500)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? 1.5 : 1.0;
      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  // inventory: LEGACY-0083
  bool shouldRepaint(covariant _PaneLayoutPainter oldDelegate) {
    // 既存 4 項目（panes/activePaneId/activeColor/isDark）を維持しつつ、
    // panes 比較を「長さ + 各 pane の id/left/top/width/height の明示比較」
    // へ強化する（B-2）。[MultiplexerPane.==] は id のみ比較のため、同一 id で
    // rect だけが変化した resize でも描画更新できるようにする。
    if (activePaneId != oldDelegate.activePaneId ||
        activeColor != oldDelegate.activeColor ||
        isDark != oldDelegate.isDark) {
      return true;
    }
    if (panes.length != oldDelegate.panes.length) return true;
    for (var i = 0; i < panes.length; i++) {
      final a = panes[i];
      final b = oldDelegate.panes[i];
      if (a.id != b.id ||
          a.left != b.left ||
          a.top != b.top ||
          a.width != b.width ||
          a.height != b.height) {
        return true;
      }
    }
    return false;
  }
}

/// ペインレイアウトのミニマップシェル（[MultiplexerPane] ベース・tmux / herdr 共通）。
///
/// 全 pane の layout rect が 0（layout なし）の場合や pane 数が 1 以下の場合は
/// 空ボックスを描かない（HIGH-2）。タップでセレクタ表示へ遷移する。
class PaneIndicatorShell extends StatelessWidget {
  final List<MultiplexerPane> panes;
  final String? activePaneId;
  final VoidCallback onTap;

  const PaneIndicatorShell({
    super.key,
    required this.panes,
    this.activePaneId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (panes.length <= 1) return const SizedBox.shrink();

    // 全 pane の rect が 0（layout なし）の場合は空ボックスを描かない（HIGH-2）。
    // min 正規化後の全体サイズが 0 になる場合も同様（painter の早期 return では
    // シェルの背景ボックスが残るためシェル側でガードする）。
    var minLeft = panes.first.left;
    var minTop = panes.first.top;
    var maxRight = 0;
    var maxBottom = 0;
    for (final pane in panes) {
      final right = pane.left + pane.width;
      final bottom = pane.top + pane.height;
      if (pane.left < minLeft) minLeft = pane.left;
      if (pane.top < minTop) minTop = pane.top;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }
    if (maxRight - minLeft == 0 || maxBottom - minTop == 0) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    // インジケーター全体のサイズ
    const double indicatorSize = 48.0;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: 0.5,
        child: Container(
          width: indicatorSize,
          height: indicatorSize,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isDark ? Colors.black26 : Colors.black12,
            borderRadius: BorderRadius.circular(4),
          ),
          child: CustomPaint(
            size: Size(indicatorSize - 4, indicatorSize - 4),
            painter: _PaneLayoutPainter(
              panes: panes,
              activePaneId: activePaneId,
              activeColor: colorScheme.primary,
              isDark: isDark,
            ),
          ),
        ),
      ),
    );
  }
}

/// 右分割アイコン: 左に既存ペイン、右に新ペイン（+マーク付き）
class SplitRightIconPainter extends CustomPainter {
  // inventory: LEGACY-0085
  final Color color;

  SplitRightIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final pad = w * 0.1;
    final mid = w * 0.5;

    // 外枠
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2),
        // inventory: LEGACY-0086
        const Radius.circular(2),
      ),
      paint,
    );

    // 分割線（中央縦線）
    // inventory: LEGACY-0087
    canvas.drawLine(Offset(mid, pad), Offset(mid, h - pad), paint);

    // 右側に+マーク
    final plusPaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final cx = mid + (w - pad - mid) / 2;
    final cy = h / 2;
    final plusSize = w * 0.12;
    canvas.drawLine(
      Offset(cx - plusSize, cy),
      Offset(cx + plusSize, cy),
      plusPaint,
    );
    canvas.drawLine(
      Offset(cx, cy - plusSize),
      Offset(cx, cy + plusSize),
      plusPaint,
    );
  }

  @override
  bool shouldRepaint(covariant SplitRightIconPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// 下分割アイコン: 上に既存ペイン、下に新ペイン（+マーク付き）
class SplitDownIconPainter extends CustomPainter {
  final Color color;

  SplitDownIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final pad = w * 0.1;
    final mid = h * 0.5;

    // 外枠
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2),
        const Radius.circular(2),
      ),
      paint,
    );

    // 分割線（中央横線）
    canvas.drawLine(Offset(pad, mid), Offset(w - pad, mid), paint);

    // 下側に+マーク
    final plusPaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final cx = w / 2;
    final cy = mid + (h - pad - mid) / 2;
    final plusSize = w * 0.12;
    canvas.drawLine(
      Offset(cx - plusSize, cy),
      Offset(cx + plusSize, cy),
      plusPaint,
    );
    canvas.drawLine(
      Offset(cx, cy - plusSize),
      Offset(cx, cy + plusSize),
      plusPaint,
    );
  }

  @override
  bool shouldRepaint(covariant SplitDownIconPainter oldDelegate) =>
      color != oldDelegate.color;
}
