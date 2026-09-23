import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/connection_provider.dart' show Connection;
import '../../theme/design_colors.dart';

/// 接続カードのヘッダー表示（status アイコン・接続情報・破損キー警告・展開）。
///
/// 元は `_ConnectionCardState.build` のヘッダー部。**provider を watch しない**
/// StatelessWidget（二重の再構築源を避けるため）。導出済みの値
/// （`statusColor` / `hasActiveSessions` / `hasDamagedKey`）は呼出側 State が
/// プロパティで渡す。
class CardHeader extends StatelessWidget {
  final Connection connection;
  final bool isExpanded;
  final bool hasActiveSessions;
  final Color statusColor;
  final bool hasDamagedKey;
  final VoidCallback onTap;

  const CardHeader({
    super.key,
    required this.connection,
    required this.isExpanded,
    required this.hasActiveSessions,
    required this.statusColor,
    required this.hasDamagedKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Status Icon
            Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: hasActiveSessions
                        ? (isDark
                              ? DesignColors.connectingCardDark
                              : DesignColors.connectingCardLight)
                        : (isDark
                              ? DesignColors.borderDark
                              : DesignColors.borderLight),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: hasActiveSessions
                          ? (isDark
                                ? DesignColors.connectingCardBorderDark
                                : DesignColors.connectingCardBorderLight)
                          : Colors.transparent,
                    ),
                  ),
                  child: Icon(
                    Icons.dns,
                    size: 20,
                    color: hasActiveSessions
                        ? colorScheme.primary
                        : (isDark
                              ? DesignColors.textSecondary
                              : DesignColors.textSecondaryLight),
                  ),
                ),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? DesignColors.surfaceDark
                            : DesignColors.surfaceLight,
                        width: 2,
                      ),
                      boxShadow: hasActiveSessions
                          ? [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.6),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            // Connection Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          connection.name,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      if (hasDamagedKey) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: colorScheme.error,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${connection.host} • ${connection.username}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: isDark
                          ? DesignColors.textMuted
                          : DesignColors.textMutedLight,
                    ),
                  ),
                  if (hasDamagedKey) ...[
                    const SizedBox(height: 4),
                    DamagedKeyBadge(),
                  ],
                ],
              ),
            ),
            // Expand Icon
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: isDark
                  ? DesignColors.textMuted
                  : DesignColors.textMutedLight,
            ),
          ],
        ),
      ),
    );
  }
}

/// 破損キー使用中のバッジ。
///
/// 元は `_ConnectionCardState._buildDamagedKeyBadge`（private）。`CardHeader`
/// 内の Connection Info 領域に同居するため同一ファイルに置く。
class DamagedKeyBadge extends StatelessWidget {
  const DamagedKeyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        context.l10n.connDamagedKeyBadge,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 9,
          color: colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
