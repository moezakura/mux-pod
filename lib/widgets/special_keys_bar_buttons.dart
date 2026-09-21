import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_colors.dart';

/// バーのキー風プッシュボタン群（32px・ラベル表示・Expanded/固定幅両対応）。
/// アクセント（RET / S-RET）を含む。状態を持たない。
///
/// タップ時の送信・修飾子消費は onTap コールバックに織り込み済みで、
/// hapticFeedback は props として受け取る（ライブ参照の維持）。
/// 固定サイズ・アイコン風のツールボタン群は special_keys_bar_tool_buttons.dart。

/// 特殊キーボタン（tmux形式で送信）
class SpecialKeyButton extends StatelessWidget {
  const SpecialKeyButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.hapticFeedback,
    this.width,
  });

  final String label;
  final VoidCallback onTap;
  final bool hapticFeedback;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final button = GestureDetector(
      onTapDown: (_) {
        if (hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: onTap,
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.black : Colors.grey.shade400,
              width: 2,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
    return width == null
        ? Expanded(child: button)
        : SizedBox(width: width, child: button);
  }
}

/// リテラルキーボタン（そのまま文字として送信）
class LiteralKeyButton extends StatelessWidget {
  const LiteralKeyButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.hapticFeedback,
    this.width,
  });

  final String label;
  final VoidCallback onTap;
  final bool hapticFeedback;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final button = GestureDetector(
      onTapDown: (_) {
        if (hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: onTap,
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.black : Colors.grey.shade400,
              width: 2,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
    return width == null
        ? Expanded(child: button)
        : SizedBox(width: width, child: button);
  }
}

/// ソフトウェア修飾子ボタン（押下状態を色で表現）。押下状態は
/// [isPressed] で受け取り、トグル処理は [onPressed] に委譲する。
class ModifierButton extends StatelessWidget {
  const ModifierButton({
    super.key,
    required this.label,
    required this.isPressed,
    required this.onPressed,
    required this.hapticFeedback,
    this.width,
  });

  final String label;
  final bool isPressed;
  final VoidCallback onPressed;
  final bool hapticFeedback;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final button = GestureDetector(
      onTapDown: (_) {
        if (hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: onPressed,
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isPressed
              ? colorScheme.primary
              : (isDark
                    ? DesignColors.keyBackground
                    : DesignColors.keyBackgroundLight),
          borderRadius: BorderRadius.circular(4),
          border: Border(
            bottom: BorderSide(
              color: isPressed
                  ? colorScheme.primary
                  : (isDark ? Colors.black : Colors.grey.shade400),
              width: 2,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isPressed ? colorScheme.onPrimary : colorScheme.primary,
            ),
          ),
        ),
      ),
    );
    return width == null
        ? Expanded(child: button)
        : SizedBox(width: width, child: button);
  }
}

/// Shift+Enterキーボタン（Claude CodeのAcceptEdits等用）
class ShiftEnterKeyButton extends StatelessWidget {
  const ShiftEnterKeyButton({
    super.key,
    required this.onTap,
    required this.hapticFeedback,
    this.width,
  });

  final VoidCallback onTap;
  final bool hapticFeedback;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTapDown: (_) {
        if (hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: onTap,
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: DesignColors.secondary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border(
            bottom: BorderSide(
              color: DesignColors.secondary.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'S-RET',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: DesignColors.secondary,
            ),
          ),
        ),
      ),
    );
    return width == null
        ? Expanded(child: button)
        : SizedBox(width: width, child: button);
  }
}

/// ENTERキーボタン（単体でEnterを送信）
class EnterKeyButton extends StatelessWidget {
  const EnterKeyButton({
    super.key,
    required this.onTap,
    required this.hapticFeedback,
    this.width,
  });

  final VoidCallback onTap;
  final bool hapticFeedback;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTapDown: (_) {
        if (hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: onTap,
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: DesignColors.primary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border(
            bottom: BorderSide(
              color: DesignColors.primary.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_return,
                  size: 12,
                  color: DesignColors.primary,
                ),
                const SizedBox(width: 2),
                Text(
                  'RET',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: DesignColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return width == null
        ? Expanded(child: button)
        : SizedBox(width: width, child: button);
  }
}
