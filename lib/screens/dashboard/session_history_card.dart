import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';
import '../../providers/active_session_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/key_provider.dart';
import '../../theme/design_colors.dart';

/// セッション履歴カード 1 枚分（dashboard 画面内部用）。
///
/// Dismissible のスワイプ削除・破損キー警告バッジ・相対時刻表示を保持する。
class SessionHistoryCard extends ConsumerWidget {
  final ActiveSession session;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const SessionHistoryCard({
    super.key,
    required this.session,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final isAttached = session.isAttached;

    // このセッションの接続が破損キー（秘密鍵を読み出せない鍵）を参照しているか
    final connectionsState = ref.watch(connectionsProvider);
    String? connectionKeyId;
    for (final c in connectionsState.connections) {
      if (c.id == session.connectionId) {
        connectionKeyId = c.keyId;
        break;
      }
    }
    final keysState = ref.watch(keysProvider);
    final hasDamagedKey = isKeyDamaged(keysState, connectionKeyId);

    return Dismissible(
      key: Key(session.key),
      direction: DismissDirection.endToStart,
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
            const Icon(Icons.delete_outline, color: DesignColors.error),
            const SizedBox(height: 4),
            Text(
              context.l10n.dashRemove,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: DesignColors.error,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
              context: context,
              builder: (dialogContext) {
                final dialogColorScheme = Theme.of(dialogContext).colorScheme;
                return AlertDialog(
                  backgroundColor: dialogColorScheme.surface,
                  title: Text(
                    dialogContext.l10n.dashRemoveFromHistoryTitle,
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                      color: dialogColorScheme.onSurface,
                    ),
                  ),
                  content: Text(
                    dialogContext.l10n.dashRemoveFromHistoryMessage(
                      session.sessionName,
                    ),
                    style: GoogleFonts.spaceGrotesk(
                      color: dialogColorScheme.onSurfaceVariant,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(dialogContext.l10n.appCancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: TextButton.styleFrom(
                        foregroundColor: DesignColors.error,
                      ),
                      child: Text(dialogContext.l10n.dashRemove),
                    ),
                  ],
                );
              },
            ) ??
            false;
      },
      onDismissed: (_) => onRemove(),
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
              // Terminal Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isAttached
                      ? (isDark
                            ? DesignColors.connectingCardDark
                            : DesignColors.connectingCardLight)
                      : (isDark
                            ? DesignColors.borderDark
                            : DesignColors.borderLight),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isAttached
                        ? (isDark
                              ? DesignColors.connectingCardBorderDark
                              : DesignColors.connectingCardBorderLight)
                        : Colors.transparent,
                  ),
                ),
                child: Icon(
                  Icons.terminal,
                  size: 24,
                  color: isAttached
                      ? DesignColors.primary
                      : (isDark
                            ? DesignColors.textSecondary
                            : DesignColors.textSecondaryLight),
                ),
              ),
              const SizedBox(width: 16),
              // Session Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Session Name with Connection Name
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${session.connectionName}: ${session.sessionName}',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                              letterSpacing: 0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                    const SizedBox(height: 4),
                    // Host and relative time
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session.host,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: isDark
                                  ? DesignColors.textMuted
                                  : DesignColors.textMutedLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          ' • ',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: isDark
                                ? DesignColors.textMuted
                                : DesignColors.textMutedLight,
                          ),
                        ),
                        Text(
                          _formatRelativeTime(
                            context.l10n,
                            session.lastAccessedAt ?? session.connectedAt,
                          ),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: isDark
                                ? DesignColors.textMuted
                                : DesignColors.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                    if (hasDamagedKey) ...[
                      const SizedBox(height: 4),
                      _buildDamagedKeyBadge(context),
                    ],
                    const SizedBox(height: 4),
                    // Window count and last position
                    Row(
                      children: [
                        Text(
                          context.l10n.appWindowCount(session.windowCount),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: isDark
                                ? DesignColors.textMuted
                                : DesignColors.textMutedLight,
                          ),
                        ),
                        if (session.lastPaneId != null) ...[
                          Text(
                            ' • ',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: isDark
                                  ? DesignColors.textMuted
                                  : DesignColors.textMutedLight,
                            ),
                          ),
                          Icon(
                            Icons.history,
                            size: 12,
                            color: DesignColors.primary.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            context.l10n.dashLastWindow(
                              session.lastWindowIndex ?? 0,
                            ),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: DesignColors.primary.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: isDark
                    ? DesignColors.textMuted
                    : DesignColors.textMutedLight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRelativeTime(AppLocalizations l10n, DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) {
      return l10n.dashTimeJustNow;
    } else if (diff.inMinutes < 60) {
      return l10n.dashTimeMinutesAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return l10n.dashTimeHoursAgo(diff.inHours);
    } else if (diff.inDays < 7) {
      return l10n.dashTimeDaysAgo(diff.inDays);
    } else {
      return l10n.dashTimeWeeksAgo((diff.inDays / 7).floor());
    }
  }

  /// 破損キー使用中のバッジ
  Widget _buildDamagedKeyBadge(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        context.l10n.dashDamagedKeyInUse,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 9,
          color: colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
