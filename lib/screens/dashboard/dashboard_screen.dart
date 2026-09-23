import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/active_session_provider.dart';
import '../../providers/session_history_provider.dart';
import '../../theme/design_colors.dart';
import '../connections/connection_form_screen.dart';
import '../terminal/terminal_screen.dart';
import 'session_history_card.dart';

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
                    child: SessionHistoryCard(
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
