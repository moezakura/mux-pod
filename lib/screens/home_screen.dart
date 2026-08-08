import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/active_session_provider.dart';
import '../providers/connection_provider.dart';
import '../services/keychain/secure_storage.dart';
import '../services/ssh/ssh_client.dart';
import '../services/tmux/tmux_commands.dart';
import '../services/tmux/tmux_parser.dart';
import '../theme/design_colors.dart';
import 'connections/connections_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'keys/keys_screen.dart';
import 'notifications/notification_panes_screen.dart';
import 'remote_ui/remote_ui_screen.dart';
import 'settings/settings_screen.dart';
import 'terminal/terminal_screen.dart';
import 'home_tab_index.dart';

/// 現在のタブインデックス Notifier
/// タブ順序:
/// 0=Servers, 1=Keys, 2=Dashboard, 3=Remote UI, 4=Notify, 5=Settings
class CurrentTabNotifier extends Notifier<int> {
  @override
  int build() => HomeTabIndex.dashboard; // Dashboard（中央）をデフォルトに

  void setTab(int index) => state = index;
}

final currentTabProvider = NotifierProvider<CurrentTabNotifier, int>(
  CurrentTabNotifier.new,
);

/// ホーム画面（Bottom Navigation付き）
/// タブ順序: Servers | Keys | [Dashboard] | Remote UI | Notify | Settings
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(currentTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentTab,
        children: const [
          ConnectionsScreen(),        // 0: Servers
          KeysScreen(),               // 1: Keys
          DashboardScreen(),          // 2: Dashboard（中央）
          RemoteUiScreen(),           // 3: Remote UI
          NotificationPanesScreen(),  // 4: Alerts
          SettingsScreen(),           // 5: Settings
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
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 通常のナビゲーションアイテム（5つ均等配置）
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Servers（左端）
                  Expanded(
                    child: _buildNavItem(
                      context,
                      ref,
                      index: HomeTabIndex.servers,
                      icon: Icons.dns,
                      label: 'Servers',
                      isSelected: currentTab == HomeTabIndex.servers,
                    ),
                  ),
                  // Keys（左寄り）
                  Expanded(
                    child: _buildNavItem(
                      context,
                      ref,
                      index: HomeTabIndex.keys,
                      icon: Icons.key,
                      label: 'Keys',
                      isSelected: currentTab == HomeTabIndex.keys,
                    ),
                  ),
                  // 中央スペーサー（Dashboardボタンの場所）
                  const SizedBox(width: 64),
                  // Remote UI（右寄り1）
                  Expanded(
                    child: _buildNavItem(
                      context,
                      ref,
                      index: HomeTabIndex.remoteUi,
                      icon: Icons.chat_bubble_outline,
                      label: 'Remote UI',
                      isSelected: currentTab == HomeTabIndex.remoteUi,
                    ),
                  ),
                  // Notify（右寄り2）
                  Expanded(
                    child: _buildNavItem(
                      context,
                      ref,
                      index: HomeTabIndex.notifications,
                      icon: Icons.notifications_outlined,
                      label: 'Notify',
                      isSelected: currentTab == HomeTabIndex.notifications,
                    ),
                  ),
                  // Settings（右端）
                  Expanded(
                    child: _buildNavItem(
                      context,
                      ref,
                      index: HomeTabIndex.settings,
                      icon: Icons.settings,
                      label: 'Settings',
                      isSelected: currentTab == HomeTabIndex.settings,
                    ),
                  ),
                ],
              ),
              // Dashboard（中央・大きくはみ出すボタン）
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(
                  child: _buildCenterButton(context, ref, isSelected: currentTab == 2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 中央のDashboardボタン（大きくはみ出す）
  Widget _buildCenterButton(
    BuildContext context,
    WidgetRef ref, {
    required bool isSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => ref.read(currentTabProvider.notifier).setTab(2),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    DesignColors.primary,
                    DesignColors.primary.withValues(alpha: 0.8),
                  ],
                )
              : null,
          color: isSelected
              ? null
              : (isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight),
          border: Border.all(
            color: isSelected
                ? DesignColors.primary
                : (isDark ? DesignColors.borderDark : DesignColors.borderLight),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? DesignColors.primary.withValues(alpha: 0.5)
                  : Colors.black.withValues(alpha: isDark ? 0.4 : 0.2),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          Icons.terminal,
          size: 36,
          color: isSelected
              ? Colors.white
              : (isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight),
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
        // No fixed width: the parent Row wraps items in Expanded so the
        // bar fits narrow screens (foldables, split-screen) without
        // overflowing now that there are six tabs.
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // アクティブインジケーター
              if (isSelected)
                Container(
                  width: 24,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: DesignColors.primary,
                    borderRadius: BorderRadius.circular(1),
                    boxShadow: [
                      BoxShadow(
                        color: DesignColors.primary.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 8),
              Icon(
                icon,
                size: 22,
                color: isSelected ? DesignColors.primary : inactiveColor,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                  color: isSelected ? DesignColors.primary : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ターミナルタブ - アクティブセッション一覧表示
class _TerminalTab extends ConsumerStatefulWidget {
  const _TerminalTab();

  @override
  ConsumerState<_TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends ConsumerState<_TerminalTab> {
  bool _isReloading = false;

  @override
  Widget build(BuildContext context) {
    final activeSessionsState = ref.watch(activeSessionsProvider);
    // 接続中（isAttached == true）のセッションのみ表示
    final sessions = activeSessionsState.sessions
        .where((s) => s.isAttached)
        .toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
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
                        onTap: () => _openSession(session),
                        onClose: () => _closeSession(session),
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

  Widget _buildAppBar(BuildContext context) {
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
        title: Text(
          'Active Sessions',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: _isReloading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
                  ),
                )
              : Icon(
                  Icons.refresh,
                  color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
                ),
          onPressed: _isReloading ? null : _reloadSessions,
          tooltip: 'Reload sessions',
        ),
        IconButton(
          icon: Icon(
            Icons.settings,
            color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
          ),
          onPressed: () => ref.read(currentTabProvider.notifier).setTab(HomeTabIndex.settings),
          tooltip: 'Settings',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Future<void> _reloadSessions() async {
    setState(() => _isReloading = true);

    try {
      final connectionsState = ref.read(connectionsProvider);
      final connections = connectionsState.connections;
      final storage = SecureStorageService();

      for (final connection in connections) {
        try {
          // 認証オプションを取得
          SshConnectOptions options;
          if (connection.authMethod == 'key' && connection.keyId != null) {
            final privateKey = await storage.getPrivateKey(connection.keyId!);
            final passphrase = await storage.getPassphrase(connection.keyId!);
            options = SshConnectOptions(privateKey: privateKey, passphrase: passphrase, tmuxPath: connection.tmuxPath);
          } else {
            final password = await storage.getPassword(connection.id);
            options = SshConnectOptions(password: password, tmuxPath: connection.tmuxPath);
          }

          // SSH接続してセッション一覧を取得
          final sshClient = SshClient();
          await sshClient.connect(
            host: connection.host,
            port: connection.port,
            username: connection.username,
            options: options,
          );

          final result = await sshClient.execWithExitCode(TmuxCommands.listSessions());
          final tmuxSessions = (result.exitCode == 0)
              ? TmuxParser.parseSessions(result.stdout)
              : <TmuxSession>[];

          // 切断
          await sshClient.disconnect();

          // ActiveSessionsProviderを更新
          ref.read(activeSessionsProvider.notifier).updateSessionsForConnection(
                connectionId: connection.id,
                connectionName: connection.name,
                host: connection.host,
                tmuxSessions: tmuxSessions,
              );
        } catch (e) {
          // 個別の接続エラーは無視（他の接続は続行）
          debugPrint('Failed to reload sessions for ${connection.name}: $e');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isReloading = false);
      }
    }
  }

  void _openSession(ActiveSession session) {
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

  void _closeSession(ActiveSession session) {
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
