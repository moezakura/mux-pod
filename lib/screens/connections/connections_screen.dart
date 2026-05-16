import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/active_session_provider.dart';
import '../../providers/connection_provider.dart';
import '../home_screen.dart';
import '../../services/keychain/secure_storage.dart';
import '../../services/ssh/ssh_client.dart';
import '../../services/tmux/tmux_commands.dart';
import '../../services/tmux/tmux_parser.dart';
import '../../theme/design_colors.dart';
import 'connection_form_screen.dart';
import '../terminal/terminal_screen.dart';

/// 検索バーの表示状態を管理するNotifier
class _SearchVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void hide() => state = false;
}

final _searchVisibleProvider = NotifierProvider<_SearchVisibleNotifier, bool>(() {
  return _SearchVisibleNotifier();
});

/// 接続一覧画面
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionsState = ref.watch(connectionsProvider);
    final filteredConnections = ref.watch(filteredConnectionsProvider);
    final isSearchVisible = ref.watch(_searchVisibleProvider);
    final searchQuery = ref.watch(connectionSearchProvider);

    developer.log(
      'ConnectionsScreen.build() - connections: ${connectionsState.connections.length}, isLoading: ${connectionsState.isLoading}',
      name: 'ConnectionsScreen',
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, ref, isSearchVisible, searchQuery),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
            sliver: _buildBody(context, ref, connectionsState, filteredConnections),
          ),
        ],
      ),
      floatingActionButton: _buildFAB(context, ref),
    );
  }

  Widget _buildAppBar(BuildContext context, WidgetRef ref, bool isSearchVisible, String searchQuery) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      floating: true,
      pinned: true,
      expandedHeight: isSearchVisible ? 140 : 100,
      backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connections',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            if (isSearchVisible) const SizedBox(height: 8),
            if (isSearchVisible)
              SizedBox(
                height: 36,
                width: MediaQuery.of(context).size.width - 120,
                child: _SearchField(
                  initialValue: searchQuery,
                  onChanged: (value) {
                    ref.read(connectionSearchProvider.notifier).setQuery(value);
                  },
                  onClear: () {
                    ref.read(connectionSearchProvider.notifier).clear();
                    ref.read(_searchVisibleProvider.notifier).hide();
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            isSearchVisible ? Icons.search_off : Icons.search,
            color: isSearchVisible ? colorScheme.primary : (isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight),
          ),
          onPressed: () {
            final wasVisible = isSearchVisible;
            ref.read(_searchVisibleProvider.notifier).toggle();
            if (wasVisible) {
              // 検索を閉じる際にクエリをクリア
              ref.read(connectionSearchProvider.notifier).clear();
            }
          },
          tooltip: isSearchVisible ? 'Close Search' : 'Search',
        ),
        IconButton(
          icon: Icon(Icons.sort, color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight),
          onPressed: () => _showSortDialog(context, ref),
          tooltip: 'Sort',
        ),
        IconButton(
          icon: const Icon(Icons.settings, color: DesignColors.textSecondary),
          onPressed: () => _openSettings(context, ref),
          tooltip: 'Settings',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _openSettings(BuildContext context, WidgetRef ref) {
    // 設定タブ（インデックス3）に切り替え
    ref.read(currentTabProvider.notifier).setTab(3);
  }

  void _showSortDialog(BuildContext context, WidgetRef ref) {
    final currentSort = ref.read(connectionSortProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final sheetColorScheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.sort, color: sheetColorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Sort Connections',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: sheetColorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: isDark ? DesignColors.borderDark : DesignColors.borderLight),
              _SortOptionTile(
                title: 'Name (A-Z)',
                option: ConnectionSortOption.nameAsc,
                currentOption: currentSort,
                onTap: () {
                  ref.read(connectionSortProvider.notifier).setSort(ConnectionSortOption.nameAsc);
                  Navigator.pop(context);
                },
              ),
              _SortOptionTile(
                title: 'Name (Z-A)',
                option: ConnectionSortOption.nameDesc,
                currentOption: currentSort,
                onTap: () {
                  ref.read(connectionSortProvider.notifier).setSort(ConnectionSortOption.nameDesc);
                  Navigator.pop(context);
                },
              ),
              _SortOptionTile(
                title: 'Last Connected (Recent First)',
                option: ConnectionSortOption.lastConnectedDesc,
                currentOption: currentSort,
                onTap: () {
                  ref.read(connectionSortProvider.notifier).setSort(ConnectionSortOption.lastConnectedDesc);
                  Navigator.pop(context);
                },
              ),
              _SortOptionTile(
                title: 'Last Connected (Oldest First)',
                option: ConnectionSortOption.lastConnectedAsc,
                currentOption: currentSort,
                onTap: () {
                  ref.read(connectionSortProvider.notifier).setSort(ConnectionSortOption.lastConnectedAsc);
                  Navigator.pop(context);
                },
              ),
              _SortOptionTile(
                title: 'Host (A-Z)',
                option: ConnectionSortOption.hostAsc,
                currentOption: currentSort,
                onTap: () {
                  ref.read(connectionSortProvider.notifier).setSort(ConnectionSortOption.hostAsc);
                  Navigator.pop(context);
                },
              ),
              _SortOptionTile(
                title: 'Host (Z-A)',
                option: ConnectionSortOption.hostDesc,
                currentOption: currentSort,
                onTap: () {
                  ref.read(connectionSortProvider.notifier).setSort(ConnectionSortOption.hostDesc);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFAB(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton(
      heroTag: 'fab_add_connection',
      onPressed: () => _addConnection(context, ref),
      elevation: 0,
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      child: const Icon(Icons.add),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ConnectionsState state, List<Connection> filteredConnections) {
    if (state.isLoading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null) {
      return SliverFillRemaining(
        child: _buildErrorState(context, ref, state.error!),
      );
    }

    if (state.connections.isEmpty) {
      return SliverFillRemaining(
        child: _buildEmptyState(context),
      );
    }

    if (filteredConnections.isEmpty) {
      return SliverFillRemaining(
        child: _buildNoResultsState(context, ref),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final connection = filteredConnections[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ConnectionCard(
              connection: connection,
              onConnect: (sessionName) =>
                  _connectToServer(context, ref, connection, sessionName),
              onEdit: () => _editConnection(context, ref, connection),
              onDelete: () => _deleteConnection(context, ref, connection),
            ),
          );
        },
        childCount: filteredConnections.length,
      ),
    );
  }

  Widget _buildNoResultsState(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? DesignColors.borderDark : DesignColors.borderLight),
            ),
            child: Icon(
              Icons.search_off,
              size: 64,
              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No matching connections',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              ref.read(connectionSearchProvider.notifier).clear();
              ref.read(_searchVisibleProvider.notifier).hide();
            },
            icon: const Icon(Icons.clear),
            label: const Text('Clear Search'),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: DesignColors.error),
          const SizedBox(height: 16),
          Text(
            'Error loading connections',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(error, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => ref.read(connectionsProvider.notifier).reload(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
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
              border: Border.all(color: isDark ? DesignColors.borderDark : DesignColors.borderLight),
            ),
            child: Icon(
              Icons.dns_outlined,
              size: 64,
              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No connections yet',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button below to add your first server',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }

  void _addConnection(BuildContext context, WidgetRef ref) async {
    developer.log('_addConnection() - navigating to ConnectionFormScreen', name: 'ConnectionsScreen');
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ConnectionFormScreen()),
    );
    developer.log('_addConnection() - returned', name: 'ConnectionsScreen');
    // No invalidate: ConnectionsNotifier.add() already updates state directly,
    // so the list reflects the new entry immediately via ref.watch.
  }

  void _editConnection(BuildContext context, WidgetRef ref, Connection connection) async {
    developer.log('_editConnection() - navigating to ConnectionFormScreen for ${connection.id}', name: 'ConnectionsScreen');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConnectionFormScreen(connectionId: connection.id),
      ),
    );
    developer.log('_editConnection() - returned', name: 'ConnectionsScreen');
    // No invalidate: ConnectionsNotifier.update() already updates state directly,
    // so the list reflects the change immediately via ref.watch.
  }

  Future<void> _deleteConnection(
    BuildContext context,
    WidgetRef ref,
    Connection connection,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Connection'),
        content: Text('Are you sure you want to delete "${connection.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: DesignColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final storage = SecureStorageService();
      await storage.deletePassword(connection.id);
      await ref.read(connectionsProvider.notifier).remove(connection.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${connection.name} deleted')),
        );
      }
    }
  }

  void _connectToServer(
    BuildContext context,
    WidgetRef ref,
    Connection connection,
    String? sessionName,
  ) {
    ref.read(connectionsProvider.notifier).updateLastConnected(connection.id);
    // 既存セッションを開く場合は最終アクセス日時を更新
    if (sessionName != null) {
      ref.read(activeSessionsProvider.notifier).touchSession(
            connection.id,
            sessionName,
          );
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TerminalScreen(
          connectionId: connection.id,
          sessionName: sessionName,
        ),
      ),
    );
  }
}

/// 接続カード（展開可能、tmuxセッション表示）
class _ConnectionCard extends ConsumerStatefulWidget {
  final Connection connection;
  final void Function(String? sessionName) onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ConnectionCard({
    required this.connection,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  ConsumerState<_ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends ConsumerState<_ConnectionCard> {
  bool _isExpanded = false;
  bool _isLoadingSessions = false;
  List<TmuxSession> _sessions = [];
  String? _sessionError;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    // アクティブセッションからこの接続のセッション情報を取得
    final activeSessionsState = ref.watch(activeSessionsProvider);
    final activeSessions =
        activeSessionsState.getSessionsForConnection(widget.connection.id);
    final hasActiveSessions = activeSessions.isNotEmpty;

    // 接続状態の判定（アクティブセッションがあるか、lastConnectedAtがあるか）
    final isConnected = hasActiveSessions || widget.connection.lastConnectedAt != null;
    final statusColor = hasActiveSessions
        ? DesignColors.success
        : (isConnected ? Colors.orange : (isDark ? DesignColors.textMuted : DesignColors.textMutedLight));

    return Container(
      decoration: BoxDecoration(
        color: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? DesignColors.borderDark : DesignColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Card Header
          InkWell(
            onTap: () => _toggleExpand(),
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
                              ? (isDark ? DesignColors.connectingCardDark : DesignColors.connectingCardLight)
                              : (isDark ? DesignColors.borderDark : DesignColors.borderLight),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: hasActiveSessions
                                ? (isDark ? DesignColors.connectingCardBorderDark : DesignColors.connectingCardBorderLight)
                                : Colors.transparent,
                          ),
                        ),
                        child: Icon(
                          Icons.dns,
                          size: 20,
                          color: hasActiveSessions
                              ? colorScheme.primary
                              : (isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight),
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
                              color: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
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
                        Text(
                          widget.connection.name,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.connection.host} • ${widget.connection.username}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Expand Icon
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                  ),
                ],
              ),
            ),
          ),
          // Expanded Content - Sessions List
          if (_isExpanded) _buildExpandedContent(activeSessions, isDark, colorScheme),
        ],
      ),
    );
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    // 展開時にセッション情報をフェッチ
    if (_isExpanded && _sessions.isEmpty && !_isLoadingSessions) {
      _fetchSessions();
    }
  }

  Future<void> _fetchSessions() async {
    setState(() {
      _isLoadingSessions = true;
      _sessionError = null;
    });

    try {
      final connection = widget.connection;
      final storage = SecureStorageService();

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

      final cmd = TmuxCommands.listSessions();
      debugPrint('_fetchSessions: tmuxPath=${sshClient.tmuxPath}, cmd="$cmd"');
      final result = await sshClient.execWithExitCode(cmd);
      debugPrint('_fetchSessions: stdout="${result.stdout.trim()}", stderr="${result.stderr.trim()}", exitCode=${result.exitCode}');
      if (result.exitCode != null && result.exitCode != 0) {
        throw SshConnectionError(
          result.stderr.isNotEmpty ? result.stderr.trim() : 'tmux command failed (exit code: ${result.exitCode})',
        );
      }
      final sessions = TmuxParser.parseSessions(result.stdout);
      debugPrint('_fetchSessions: parsed ${sessions.length} sessions');

      // 切断
      await sshClient.disconnect();

      if (!mounted) return;

      setState(() {
        _sessions = sessions;
        _isLoadingSessions = false;
      });

      // ActiveSessionsProviderを更新
      ref.read(activeSessionsProvider.notifier).updateSessionsForConnection(
            connectionId: connection.id,
            connectionName: connection.name,
            host: connection.host,
            tmuxSessions: sessions,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSessions = false;
        _sessionError = e.toString();
      });
    }
  }

  Widget _buildExpandedContent(List<ActiveSession> activeSessions, bool isDark, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15161C) : const Color(0xFFF8F9FA),
        border: Border(top: BorderSide(color: isDark ? DesignColors.borderDark : DesignColors.borderLight)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sessions Section Header with Reload Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'ACTIVE SESSIONS',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: Icon(
                      Icons.refresh,
                      color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                    ),
                    onPressed: _isLoadingSessions ? null : _fetchSessions,
                    tooltip: 'Reload sessions',
                  ),
                ),
              ],
            ),
          ),
          // Sessions List
          if (_isLoadingSessions)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_sessionError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _sessionError!,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: DesignColors.error,
                ),
              ),
            )
          else if (_sessions.isEmpty && activeSessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No tmux sessions found',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                ),
              ),
            )
          else
            // セッションリスト（_sessionsまたはactiveSessionsを使用）
            ..._buildSessionItems(isDark, colorScheme),
          // New Session Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: OutlinedButton.icon(
              onPressed: _showNewSessionDialog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Session'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.primary.withValues(alpha: 0.8),
                side: BorderSide(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  style: BorderStyle.solid,
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
          ),
          Divider(color: isDark ? DesignColors.borderDark : DesignColors.borderLight, height: 1),
          // Action Buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: DesignColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showNewSessionDialog() async {
    final sessionName = await showDialog<String>(
      context: context,
      builder: (context) => _NewSessionDialog(
        existingSessionNames: _sessions.map((s) => s.name).toList(),
      ),
    );

    if (sessionName != null && sessionName.isNotEmpty) {
      widget.onConnect(sessionName);
    }
  }

  List<Widget> _buildSessionItems(bool isDark, ColorScheme colorScheme) {
    // _sessionsを使用（フェッチ結果）
    final sessions = _sessions;
    if (sessions.isEmpty) return [];

    return sessions.map((session) {
      final isAttached = session.attached;
      return InkWell(
        onTap: () => widget.onConnect(session.name),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.terminal,
                size: 16,
                color: isAttached ? colorScheme.primary : (isDark ? DesignColors.textMuted : DesignColors.textMutedLight),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${session.windowCount} windows',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                      ),
                    ),
                  ],
                ),
              ),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isAttached
                      ? (isDark ? DesignColors.connectedCardDark.withValues(alpha: 0.5) : DesignColors.connectedCardLight)
                      : (isDark ? DesignColors.borderDark : DesignColors.borderLight),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isAttached
                        ? (isDark ? DesignColors.connectedCardBorderDark.withValues(alpha: 0.7) : DesignColors.connectedCardBorderLight)
                        : (isDark ? DesignColors.borderDark : DesignColors.borderLight),
                  ),
                ),
                child: Text(
                  isAttached ? 'Attached' : 'Detached',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
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
      );
    }).toList();
  }
}

/// 検索フィールドウィジェット
class _SearchField extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.initialValue,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text && widget.initialValue.isEmpty) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      autofocus: true,
      onChanged: widget.onChanged,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 12,
        color: colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        hintText: 'Search connections...',
        hintStyle: GoogleFonts.jetBrainsMono(
          fontSize: 12,
          color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
        ),
        filled: true,
        fillColor: isDark ? DesignColors.inputDark : DesignColors.inputLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 1),
        ),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _controller.clear();
                  widget.onClear();
                },
                color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            : null,
      ),
    );
  }
}

/// ソートオプションタイル
class _SortOptionTile extends StatelessWidget {
  final String title;
  final ConnectionSortOption option;
  final ConnectionSortOption currentOption;
  final VoidCallback onTap;

  const _SortOptionTile({
    required this.title,
    required this.option,
    required this.currentOption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = option == currentOption;
    return ListTile(
      title: Text(
        title,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary, size: 20)
          : null,
      onTap: onTap,
    );
  }
}

/// 新規セッション作成ダイアログ
class _NewSessionDialog extends StatefulWidget {
  final List<String> existingSessionNames;

  const _NewSessionDialog({required this.existingSessionNames});

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _generateDefaultName());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _generateDefaultName() {
    int index = 1;
    while (widget.existingSessionNames.contains('session-$index')) {
      index++;
    }
    return 'session-$index';
  }

  String? _validateSessionName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a session name';
    }
    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(value)) {
      return 'Only letters, numbers, - _ . allowed';
    }
    if (widget.existingSessionNames.contains(value)) {
      return 'Session "$value" already exists';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _nameController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        'New Session',
        style: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Session Name',
            hintText: 'session-1',
            hintStyle: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
            ),
            filled: true,
            fillColor: isDark ? DesignColors.inputDark : DesignColors.inputLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.error),
            ),
          ),
          style: GoogleFonts.jetBrainsMono(fontSize: 14),
          validator: _validateSessionName,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
