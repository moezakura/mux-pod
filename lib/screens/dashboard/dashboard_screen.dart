import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/active_session_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/key_provider.dart';
import '../../providers/session_history_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';
import '../../theme/design_colors.dart';
import '../connections/connection_form_screen.dart';
import '../terminal/terminal_screen.dart';

/// ダッシュボード画面（セッション履歴ベース）
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionHistoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // AppBar
          SliverAppBar(
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: isDark
                ? DesignColors.backgroundDark.withValues(alpha: 0.95)
                : DesignColors.backgroundLight.withValues(alpha: 0.95),
            title: Text(
              'MuxPod',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          // Section Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                context.l10n.dashRecentSessions,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? DesignColors.textMuted
                      : DesignColors.textMutedLight,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          // Session List or Empty State
          if (sessions.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(context, isDark),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final session = sessions[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SessionHistoryCard(
                      session: session,
                      onTap: () => _navigateToTerminal(context, ref, session),
                      onRemove: () => _removeFromHistory(ref, session),
                    ),
                  );
                }, childCount: sessions.length),
              ),
            ),
          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addNewConnection(context),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.terminal_outlined,
            size: 64,
            color: isDark
                ? DesignColors.textMuted
                : DesignColors.textMutedLight,
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.dashNoRecentSessions,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? DesignColors.textSecondary
                  : DesignColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.dashConnectToServerToStart,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: isDark
                  ? DesignColors.textMuted
                  : DesignColors.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToTerminal(
    BuildContext context,
    WidgetRef ref,
    ActiveSession session,
  ) {
    // T16（Q-05）: herdr も mutation 可能。readOnly は呼び出し側明示の
    // opt-in としてのみ渡す（herdr による自動付与は廃止・H6）。

    // 最終アクセス日時を更新
    ref
        .read(activeSessionsProvider.notifier)
        .touchSession(
          session.connectionId,
          session.sessionName,
          sessionId: session.sessionId,
        );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TerminalScreen(
          connectionId: session.connectionId,
          sessionName: session.sessionName,
          sessionId: session.sessionId,
          lastWindowIndex: session.lastWindowIndex,
          lastPaneId: session.lastPaneId,
        ),
      ),
    );
  }

  void _removeFromHistory(WidgetRef ref, ActiveSession session) {
    ref
        .read(activeSessionsProvider.notifier)
        .removeSession(
          session.connectionId,
          session.sessionName,
          sessionId: session.sessionId,
        );
  }

  void _addNewConnection(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ConnectionFormScreen()),
    );
  }
}

/// セッション履歴カード
class _SessionHistoryCard extends ConsumerWidget {
  final ActiveSession session;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _SessionHistoryCard({
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
