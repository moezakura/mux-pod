import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/active_session_provider.dart';
import '../theme/design_colors.dart';
import 'connections/connections_screen.dart';
import 'keys/keys_screen.dart';
import 'settings/settings_screen.dart';
import 'terminal/terminal_screen.dart';

/// 現在のタブインデックス Notifier
class CurrentTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setTab(int index) => state = index;
}

final currentTabProvider = NotifierProvider<CurrentTabNotifier, int>(
  CurrentTabNotifier.new,
);

/// ホーム画面（Bottom Navigation付き）
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(currentTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentTab,
        children: const [
          ConnectionsScreen(),
          _TerminalTab(),
          KeysScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context, ref, currentTab),
    );
  }

  Widget _buildBottomNavigationBar(
    BuildContext context,
    WidgetRef ref,
    int currentTab,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignColors.backgroundDark.withValues(alpha: 0.9)
            : DesignColors.footerBackgroundLight.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: isDark ? DesignColors.surfaceDark : DesignColors.borderLight,
          ),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                context,
                ref,
                index: 0,
                icon: Icons.dns,
                label: 'Connect',
                isSelected: currentTab == 0,
              ),
              _buildNavItem(
                context,
                ref,
                index: 1,
                icon: Icons.terminal,
                label: 'Sessions',
                isSelected: currentTab == 1,
              ),
              _buildNavItem(
                context,
                ref,
                index: 2,
                icon: Icons.key,
                label: 'Keys',
                isSelected: currentTab == 2,
              ),
              _buildNavItem(
                context,
                ref,
                index: 3,
                icon: Icons.settings,
                label: 'Settings',
                isSelected: currentTab == 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    WidgetRef ref, {
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark ? DesignColors.textMuted : DesignColors.textMutedLight;
    return GestureDetector(
      onTap: () => ref.read(currentTabProvider.notifier).setTab(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // アクティブインジケーター
            if (isSelected)
              Container(
                width: 32,
                height: 2,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: DesignColors.primary,
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: [
                    BoxShadow(
                      color: DesignColors.primary.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 10),
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? DesignColors.primary
                  : inactiveColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                color: isSelected
                    ? DesignColors.primary
                    : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ターミナルタブ - アクティブセッション一覧表示
class _TerminalTab extends ConsumerWidget {
  const _TerminalTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSessionsState = ref.watch(activeSessionsProvider);
    final sessions = activeSessionsState.sessions;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, ref),
          if (sessions.isEmpty)
            const SliverFillRemaining(
              child: _EmptySessionsView(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final session = sessions[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SessionCard(
                        session: session,
                        onTap: () => _openSession(context, ref, session),
                        onClose: () => _closeSession(ref, session),
                      ),
                    );
                  },
                  childCount: sessions.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      floating: true,
      pinned: true,
      expandedHeight: 100,
      backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sessions',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'TERMINAL_MODE: READY',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.settings,
            color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
          ),
          onPressed: () => ref.read(currentTabProvider.notifier).setTab(3),
          tooltip: 'Settings',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _openSession(BuildContext context, WidgetRef ref, ActiveSession session) {
    ref.read(activeSessionsProvider.notifier).setCurrentSession(
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

  void _closeSession(WidgetRef ref, ActiveSession session) {
    ref.read(activeSessionsProvider.notifier).closeSession(
          session.connectionId,
          session.sessionName,
        );
  }
}

/// 空のセッション表示
class _EmptySessionsView extends StatelessWidget {
  const _EmptySessionsView();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? DesignColors.borderDark : DesignColors.borderLight,
              ),
            ),
            child: Icon(
              Icons.terminal,
              size: 64,
              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Active Sessions',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect to a server to start a terminal session',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// セッションカード
class _SessionCard extends StatelessWidget {
  final ActiveSession session;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _SessionCard({
    required this.session,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final isAttached = session.isAttached;

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
        child: const Icon(
          Icons.close,
          color: DesignColors.error,
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
                'Close Session?',
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.w700,
                  color: dialogColorScheme.onSurface,
                ),
              ),
              content: Text(
                'Remove "${session.sessionName}" from active sessions?',
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
                  child: const Text('Close'),
                ),
              ],
            );
          },
        ) ?? false;
      },
      onDismissed: (_) => onClose(),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isAttached
                      ? (isDark ? DesignColors.connectingCardDark : DesignColors.connectingCardLight)
                      : (isDark ? DesignColors.borderDark : DesignColors.borderLight),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isAttached
                        ? (isDark ? DesignColors.connectingCardBorderDark : DesignColors.connectingCardBorderLight)
                        : Colors.transparent,
                  ),
                ),
                child: Icon(
                  Icons.terminal,
                  size: 20,
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
                    Text(
                      session.sessionName,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${session.connectionName} • ${session.host}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${session.windowCount} windows',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                          ),
                        ),
                        // 最後に開いていたペイン情報を表示
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
                            'Last: W${session.lastWindowIndex ?? 0}',
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
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isAttached
                      ? (isDark
                          ? DesignColors.connectedCardDark.withValues(alpha: 0.5)
                          : DesignColors.connectedCardLight)
                      : (isDark ? DesignColors.borderDark : DesignColors.borderLight),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isAttached
                        ? (isDark
                            ? DesignColors.connectedCardBorderDark.withValues(alpha: 0.7)
                            : DesignColors.connectedCardBorderLight)
                        : (isDark ? DesignColors.borderDark : DesignColors.borderLight),
                  ),
                ),
                child: Text(
                  isAttached ? 'Attached' : 'Detached',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isAttached
                        ? (isDark ? DesignColors.connectedCardTextDark : DesignColors.connectedCardTextLight)
                        : (isDark ? DesignColors.textMuted : DesignColors.textMutedLight),
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
