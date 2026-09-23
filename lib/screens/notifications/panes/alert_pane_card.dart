import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/notification_panes_provider.dart';

import '../../../theme/design_colors.dart';
import 'alert_flag_style.dart';

/// アラートペインカード（通知一覧の 1 枚分の表示）。
///
/// タップ・スワイプ破棄のコールバックは親（[NotificationPanesScreen] の
/// State）から props で受け取り、自身では状態を持たない表示専用 widget。
class AlertPaneCard extends StatelessWidget {
  final AlertPane alert;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const AlertPaneCard({
    super.key,
    required this.alert,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: Key(alert.key),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: DesignColors.error.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_off, color: DesignColors.error),
            const SizedBox(height: 4),
            Text(
              context.l10n.notifDismiss,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: DesignColors.error,
              ),
            ),
          ],
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? DesignColors.surfaceDark
                : DesignColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? DesignColors.borderDark
                  : DesignColors.borderLight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Flag Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: alertFlagBackgroundColor(alert.primaryFlag, isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: alertFlagBorderColor(alert.primaryFlag, isDark),
                  ),
                ),
                child: Icon(
                  alertFlagIcon(alert.primaryFlag),
                  size: 24,
                  color: alertFlagIconColor(alert.primaryFlag),
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alert.connectionName}: ${alert.sessionName}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.host,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: isDark
                            ? DesignColors.textMuted
                            : DesignColors.textMutedLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            context.l10n.notifWindowPosition(
                              alert.windowIndex,
                              alert.windowName,
                            ),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: isDark
                                  ? DesignColors.textMuted
                                  : DesignColors.textMutedLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            context.l10n.notifPanePosition(alert.paneIndex),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: isDark
                                  ? DesignColors.textMuted
                                  : DesignColors.textMutedLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (alert.currentCommand != null) ...[
                          Text(
                            ' • ',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: isDark
                                  ? DesignColors.textMuted
                                  : DesignColors.textMutedLight,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              alert.currentCommand!,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: isDark
                                    ? DesignColors.textMuted
                                    : DesignColors.textMutedLight,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Flag Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: alertFlagBadgeBackground(alert.primaryFlag, isDark),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: alertFlagBadgeBorder(alert.primaryFlag, isDark),
                  ),
                ),
                child: Text(
                  alertFlagLabel(context.l10n, alert.primaryFlag),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: alertFlagIconColor(alert.primaryFlag),
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
