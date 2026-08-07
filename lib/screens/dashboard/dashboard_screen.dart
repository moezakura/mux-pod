import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/active_session_provider.dart';
import '../../providers/session_history_provider.dart';
import '../../services/backend/domain/multiplexer_backend.dart';
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
                'Recent Sessions',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
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
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final session = sessions[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SessionHistoryCard(
                        session: session,
                        onTap: () => _navigateToTerminal(context, ref, session),
                        onRemove: () => _removeFromHistory(ref, session),
                      ),
                    );
                  },
                  childCount: sessions.length,
                ),
              ),
            ),
          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 80),
          ),
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
            color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
          ),
          const SizedBox(height: 16),
          Text(
            'No recent sessions',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect to a server to get started',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToTerminal(BuildContext context, WidgetRef ref, ActiveSession session) {
    // herdr は read-only のため Terminal へは遷移せず SnackBar で案内する
    if (session.backend == MultiplexerBackendKind.herdr) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Herdr workspaces are read-only')),
      );
      return;
    }

    // 最終アクセス日時を更新
    ref.read(activeSessionsProvider.notifier).touchSession(
          session.connectionId,
          session.sessionName,
        );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TerminalScreen(
          connectionId: session.connectionId,
          sessionName: session.sessionName,
          lastWindowIndex: session.lastWindowIndex,
          lastPaneId: session.lastPaneId,
        ),
      ),
    );
  }

  void _removeFromHistory(WidgetRef ref, ActiveSession session) {
    ref.read(activeSessionsProvider.notifier).removeSession(
          session.connectionId,
          session.sessionName,
        );
  }

  void _addNewConnection(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ConnectionFormScreen(),
      ),
    );
  }
}

/// セッション履歴カード
class _SessionHistoryCard extends StatelessWidget {
  final ActiveSession session;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _SessionHistoryCard({
    required this.session,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final isAttached = session.isAttached;
    final isReadOnly = session.backend == MultiplexerBackendKind.herdr;

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
            const Icon(
              Icons.delete_outline,
              color: DesignColors.error,
            ),
            const SizedBox(height: 4),
            Text(
              'Remove',
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
                    'Remove from History?',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                      color: dialogColorScheme.onSurface,
                    ),
                  ),
                  content: Text(
                    'Remove "${session.sessionName}" from recent sessions?\n\nThe tmux session will remain active on the server.',
                    style: GoogleFonts.spaceGrotesk(color: dialogColorScheme.onSurfaceVariant),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: TextButton.styleFrom(foregroundColor: DesignColors.error),
                      child: const Text('Remove'),
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
            color: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? DesignColors.borderDark : DesignColors.borderLight,
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
                      ? (isDark ? DesignColors.connectingCardDark : DesignColors.connectingCardLight)
                      : (isDark ? DesignColors.borderDark : DesignColors.borderLight),
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
                      : (isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight),
                ),
              ),
              const SizedBox(width: 16),
              // Session Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Session Name with Connection Name
                    Text(
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
                    const SizedBox(height: 4),
                    // Host and relative time
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session.host,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          ' • ',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                          ),
                        ),
                        Text(
                          _formatRelativeTime(session.lastAccessedAt ?? session.connectedAt),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Window count and last position
                    Row(
                      children: [
                        Text(
                          '${session.windowCount} windows',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                          ),
                        ),
                        if (session.lastPaneId != null) ...[
                          Text(
                            ' • ',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                            ),
                          ),
                          Icon(
                            Icons.history,
                            size: 12,
                            color: DesignColors.primary.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'W${session.lastWindowIndex ?? 0}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: DesignColors.primary.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // READ ONLY バッジ（herdr） / 遷移矢印（tmux）
              if (isReadOnly)
                _ReadOnlyBadge(isDark: isDark)
              else
                Icon(
                  Icons.chevron_right,
                  color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      final mins = diff.inMinutes;
      return '$mins min${mins > 1 ? 's' : ''} ago';
    } else if (diff.inHours < 24) {
      final hours = diff.inHours;
      return '$hours hour${hours > 1 ? 's' : ''} ago';
    } else if (diff.inDays < 7) {
      final days = diff.inDays;
      return '$days day${days > 1 ? 's' : ''} ago';
    } else {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks week${weeks > 1 ? 's' : ''} ago';
    }
  }
}

/// READ ONLY バッジ（herdr セッション表示用）。
class _ReadOnlyBadge extends StatelessWidget {
  final bool isDark;

  const _ReadOnlyBadge({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? DesignColors.connectingCardDark.withValues(alpha: 0.5)
            : DesignColors.connectingCardLight,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark
              ? DesignColors.connectingCardBorderDark.withValues(alpha: 0.7)
              : DesignColors.connectingCardBorderLight,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 10,
            color: isDark
                ? DesignColors.connectedCardTextDark
                : DesignColors.connectedCardTextLight,
          ),
          const SizedBox(width: 4),
          Text(
            'READ ONLY',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? DesignColors.connectedCardTextDark
                  : DesignColors.connectedCardTextLight,
            ),
          ),
        ],
      ),
    );
  }
}
