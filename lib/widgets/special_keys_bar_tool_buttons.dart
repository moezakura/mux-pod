import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_colors.dart';

/// バーの固定サイズ・ツールボタン群（36pxアイコン風のナビ/矢印/数字・
/// 画像転送・'Cmd' 入力導線・鉛筆・DirectInputトグル）。状態を持たない。
///
/// タップ時の送信・修飾子消費は onTap コールバックに織り込み済みで、
/// hapticFeedback は props として受け取る（ライブ参照の維持）。

/// ボタン管理画面を開く鉛筆ボタン（32×32、行1末尾・スクロール外に固定）
class ManageButton extends StatelessWidget {
  const ManageButton({
    super.key,
    required this.onTap,
    required this.hapticFeedback,
  });

  final VoidCallback? onTap;
  final bool hapticFeedback;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (hapticFeedback) {
          HapticFeedback.selectionClick();
        }
        onTap?.call();
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: DesignColors.keyBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: const Center(
          child: Icon(Icons.edit_outlined, size: 18, color: Colors.white70),
        ),
      ),
    );
  }
}

/// ナビゲーションキーボタン（PgUp/PgDn等・36pxアイコン風）
class NavigationKeyButton extends StatelessWidget {
  const NavigationKeyButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.hapticFeedback,
  });

  final String label;
  final VoidCallback onTap;
  final bool hapticFeedback;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) {
        if (hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// 矢印キーボタン（36pxアイコン風）
class ArrowKeyButton extends StatelessWidget {
  const ArrowKeyButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.hapticFeedback,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool hapticFeedback;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) {
        if (hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, size: 16, color: colorScheme.onSurface),
      ),
    );
  }
}

/// 画像転送ボタン（36pxアイコン風）。
/// ※ 既存の `ImageTransferButton`（ConsumerWidget）とは別物のため別名。
class SpecialKeysImageButton extends StatelessWidget {
  const SpecialKeysImageButton({
    super.key,
    required this.onTap,
    required this.hapticFeedback,
  });

  final VoidCallback? onTap;
  final bool hapticFeedback;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) {
        if (hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Icon(
          Icons.image_outlined,
          size: 16,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 数字キーボタン（DirectInput有効時に矢印キー行に表示）
class NumberKeyButton extends StatelessWidget {
  const NumberKeyButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.hapticFeedback,
  });

  final String label;
  final VoidCallback onTap;
  final bool hapticFeedback;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) {
        if (hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// コマンド入力ボタン（非DirectInput時の入力欄への導線、'Cmd' ラベル）。
class CmdInputButton extends StatelessWidget {
  const CmdInputButton({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: DesignColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: DesignColors.primary.withValues(alpha: 0.2),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard,
                  size: 15,
                  color: DesignColors.primary.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  // "Cmd" keeps the non-direct toolbar compact enough for fixed nav keys.
                  'Cmd',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: DesignColors.primary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// DirectInputモードのトグルボタン
class DirectInputToggleButton extends StatelessWidget {
  const DirectInputToggleButton({
    super.key,
    required this.isEnabled,
    required this.onTap,
    required this.hapticFeedback,
  });

  final bool isEnabled;
  final VoidCallback? onTap;
  final bool hapticFeedback;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (hapticFeedback) {
          HapticFeedback.selectionClick();
        }
        onTap?.call();
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isEnabled
              ? DesignColors.success.withValues(alpha: 0.3)
              : DesignColors.keyBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isEnabled
                ? DesignColors.success.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Center(
          child: Icon(
            isEnabled ? Icons.flash_on : Icons.flash_off,
            size: 18,
            color: isEnabled ? DesignColors.success : Colors.white70,
          ),
        ),
      ),
    );
  }
}
