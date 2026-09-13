import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/design_colors.dart';

/// 画面下部へスクロールするボタン
///
/// ESC/TABバーの上に配置され、タップで最下部にスクロールする。
/// アクティブ時は塗りつぶし背景で表示、非アクティブ時は薄い白枠+白矢印+透明背景。
class ScrollToBottomButton extends StatefulWidget {
  final VoidCallback onPressed;

  /// 長押し時（最下部ロック）のコールバック。null なら長押しは無効。
  final VoidCallback? onLongPress;

  /// 最下部ロック中は常時表示・アクティブ表示を維持する。
  final bool locked;

  const ScrollToBottomButton({
    super.key,
    required this.onPressed,
    this.onLongPress,
    this.locked = false,
  });

  @override
  State<ScrollToBottomButton> createState() => ScrollToBottomButtonState();
}

class ScrollToBottomButtonState extends State<ScrollToBottomButton> {
  bool _active = false;
  bool _visible = false;
  Timer? _fadeTimer;

  /// ボタンをアクティブ表示にし、3秒後に非アクティブに遷移する。
  /// ロック中は常時アクティブ表示のためフェードタイマーを予約しない。
  void show() {
    if (!mounted) return;
    _fadeTimer?.cancel();
    setState(() {
      _active = true;
      _visible = true;
    });
    if (widget.locked) return;
    _fadeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _active = false;
      });
    });
  }

  /// ボタンを完全に非表示にする
  void hide() {
    if (!mounted) return;
    _fadeTimer?.cancel();
    setState(() {
      _active = false;
      _visible = false;
    });
  }

  @override
  void didUpdateWidget(ScrollToBottomButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ロック解除後も表示中なら 3 秒フェードを予約する（残留対策）。
    if (oldWidget.locked && !widget.locked && _visible) {
      _fadeTimer?.cancel();
      _fadeTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _active = false;
        });
      });
    }
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible || widget.locked;
    if (!visible) return const SizedBox.shrink();

    final active = _active || widget.locked;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final bgColor = active
        ? (isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight)
        : Colors.transparent;

    final borderColor = active
        ? colorScheme.outline.withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.15);

    final iconColor = active
        ? colorScheme.onSurface.withValues(alpha: 0.8)
        : Colors.white.withValues(alpha: 0.15);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onPressed();
      },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: iconColor),
          duration: const Duration(milliseconds: 300),
          builder: (context, color, _) => Icon(
            widget.locked
                ? Icons.vertical_align_bottom
                : Icons.keyboard_double_arrow_down,
            size: 18,
            color: color,
          ),
        ),
      ),
    );
  }
}
