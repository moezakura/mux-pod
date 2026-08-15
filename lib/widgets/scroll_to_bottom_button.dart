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

  const ScrollToBottomButton({super.key, required this.onPressed});

  @override
  State<ScrollToBottomButton> createState() => ScrollToBottomButtonState();
}

class ScrollToBottomButtonState extends State<ScrollToBottomButton> {
  bool _active = false;
  bool _visible = false;
  Timer? _fadeTimer;

  /// ボタンをアクティブ表示にし、3秒後に非アクティブに遷移する
  void show() {
    if (!mounted) return;
    _fadeTimer?.cancel();
    setState(() {
      _active = true;
      _visible = true;
    });
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
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final bgColor = _active
        ? (isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight)
        : Colors.transparent;

    final borderColor = _active
        ? colorScheme.outline.withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.15);

    final iconColor = _active
        ? colorScheme.onSurface.withValues(alpha: 0.8)
        : Colors.white.withValues(alpha: 0.15);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onPressed();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: _active
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
          builder: (context, color, _) =>
              Icon(Icons.keyboard_double_arrow_down, size: 18, color: color),
        ),
      ),
    );
  }
}
