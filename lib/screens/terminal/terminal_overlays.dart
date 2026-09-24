import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_colors.dart';
import '../../l10n/l10n_ext.dart';

// inventory: TERM-DIALOG-009
/// レイテンシ表示
class LatencyIndicator extends StatelessWidget {
  final int latency;

  const LatencyIndicator({super.key, required this.latency});
  @override
  Widget build(BuildContext context) {
    // レイテンシに応じた色を決定
    // inventory: LEGACY-0076
    Color indicatorColor;
    if (latency < 100) {
      indicatorColor = DesignColors.success; // 緑: 良好
    } else if (latency < 300) {
      indicatorColor = DesignColors.primary; // シアン: 普通
    } else if (latency < 500) {
      indicatorColor = DesignColors.warning; // オレンジ: やや遅い
    } else {
      indicatorColor = DesignColors.error; // 赤: 遅い
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bolt,
          size: 10,
          color: indicatorColor.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 4),
        Text(
          '${latency}ms',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: indicatorColor.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

/// 未接続バナー。
///
/// 特殊キーバー（SpecialKeysBar）の代わりに表示し、未接続（書き込み不可）
/// であることを示す。キー入力が無効なため、デザイン上の注意書きのみを担う。
class DisconnectedBanner extends StatelessWidget {
  final bool isDark;

  const DisconnectedBanner({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isDark
          ? DesignColors.connectingCardDark.withValues(alpha: 0.4)
          : DesignColors.connectingCardLight,
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 14,
            color: isDark
                ? DesignColors.connectedCardTextDark
                : DesignColors.connectedCardTextLight,
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n.termDisconnectedBanner,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? DesignColors.connectedCardTextDark
                  : DesignColors.connectedCardTextLight,
            ),
          ),
          const Spacer(),
          Text(
            'Herdr',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
