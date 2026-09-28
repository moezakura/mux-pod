import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../navigation/current_tab_provider.dart' show currentTabProvider;
import '../../providers/active_session_provider.dart'
    show activeSessionsProvider;
import '../../providers/connection_provider.dart'
    show
        Connection,
        ConnectionsState,
        connectionSearchProvider,
        connectionsProvider,
        filteredConnectionsProvider;
import '../../services/keychain/secure_storage.dart' show SecureStorageService;
import '../../services/ssh/ssh_client.dart' show SshClient;
import '../../theme/design_colors.dart';

import '../terminal/terminal_screen.dart' show TerminalScreen;
import 'connection_card.dart' show ConnectionCard;
import 'connection_form_screen.dart' show ConnectionFormScreen;
import 'connection_list_states.dart'
    show buildConnectionEmptyState, buildConnectionNoResultsState;
import 'connection_search_field.dart' show SearchField;
import 'connection_sort_sheet.dart' show showSortDialog;

/// 検索バーの表示状態を管理するNotifier
///
/// 定義と使用がこのファイル内で完結するため private のまま維持。
class _SearchVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void hide() => state = false;
}

final _searchVisibleProvider = NotifierProvider<_SearchVisibleNotifier, bool>(
  () {
    return _SearchVisibleNotifier();
  },
);

/// 接続一覧画面
class ConnectionsScreen extends ConsumerWidget {
  final Future<SshClient> Function(Connection connection)? sshClientFactory;

  const ConnectionsScreen({super.key, this.sshClientFactory});

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
            sliver: _buildBody(
              context,
              ref,
              connectionsState,
              filteredConnections,
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFAB(context, ref),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    bool isSearchVisible,
    String searchQuery,
  ) {
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
              context.l10n.connTitle,
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
                child: SearchField(
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
            color: isSearchVisible
                ? colorScheme.primary
                : (isDark
                      ? DesignColors.textSecondary
                      : DesignColors.textSecondaryLight),
          ),
          onPressed: () {
            final wasVisible = isSearchVisible;
            ref.read(_searchVisibleProvider.notifier).toggle();
            if (wasVisible) {
              // 検索を閉じる際にクエリをクリア
              ref.read(connectionSearchProvider.notifier).clear();
            }
          },
          tooltip: isSearchVisible
              ? context.l10n.connCloseSearch
              : context.l10n.connSearch,
        ),
        IconButton(
          icon: Icon(
            Icons.sort,
            color: isDark
                ? DesignColors.textSecondary
                : DesignColors.textSecondaryLight,
          ),
          onPressed: () => showSortDialog(context, ref),
          tooltip: context.l10n.connSort,
        ),
        IconButton(
          icon: const Icon(Icons.settings, color: DesignColors.textSecondary),
          onPressed: () => _openSettings(context, ref),
          tooltip: context.l10n.connSettings,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _openSettings(BuildContext context, WidgetRef ref) {
    // 設定タブに切り替え（中立モジュール経由・home シムには依存しない）
    ref.read(currentTabProvider.notifier).setTab(3);
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

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ConnectionsState state,
    List<Connection> filteredConnections,
  ) {
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
      return SliverFillRemaining(child: buildConnectionEmptyState(context));
    }

    if (filteredConnections.isEmpty) {
      return SliverFillRemaining(
        child: buildConnectionNoResultsState(
          context,
          onClearSearch: () {
            ref.read(connectionSearchProvider.notifier).clear();
            ref.read(_searchVisibleProvider.notifier).hide();
          },
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final connection = filteredConnections[index];
        return Padding(
          key: ValueKey(connection.id),
          padding: const EdgeInsets.only(bottom: 12),
          child: RepaintBoundary(
            child: ConnectionCard(
              connection: connection,
              sshClientFactory: sshClientFactory,
              onConnect: (sessionName, {sessionId}) => _connectToServer(
                context,
                ref,
                connection,
                sessionName,
                sessionId: sessionId,
              ),
              onEdit: () => _editConnection(context, ref, connection),
              onDelete: () => _deleteConnection(context, ref, connection),
            ),
          ),
        );
      }, childCount: filteredConnections.length),
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
            context.l10n.connLoadError,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(error, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => ref.read(connectionsProvider.notifier).reload(),
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.connRetry),
          ),
        ],
      ),
    );
  }

  void _addConnection(BuildContext context, WidgetRef ref) async {
    developer.log(
      '_addConnection() - navigating to ConnectionFormScreen',
      name: 'ConnectionsScreen',
    );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ConnectionFormScreen()),
    );
    developer.log('_addConnection() - returned', name: 'ConnectionsScreen');
    // No invalidate: ConnectionsNotifier.add() already updates state directly,
    // so the list reflects the new entry immediately via ref.watch.
  }

  void _editConnection(
    BuildContext context,
    WidgetRef ref,
    Connection connection,
  ) async {
    developer.log(
      '_editConnection() - navigating to ConnectionFormScreen for ${connection.id}',
      name: 'ConnectionsScreen',
    );
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
        title: Text(context.l10n.connDeleteConfirmTitle),
        content: Text(context.l10n.connDeleteConfirmMessage(connection.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.connCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: DesignColors.error),
            child: Text(context.l10n.connDelete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final storage = SecureStorageService();
      await storage.deletePassword(connection.id);
      // ジャンプホストの認証情報も全 hop 分削除する（MR-4・🤝2 orphan 対応）。
      await storage.deleteProxyPassword(connection.id);
      await ref.read(connectionsProvider.notifier).remove(connection.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.connDeletedMessage(connection.name)),
          ),
        );
      }
    }
  }

  void _connectToServer(
    BuildContext context,
    WidgetRef ref,
    Connection connection,
    String? sessionName, {
    String? sessionId,
  }) {
    ref.read(connectionsProvider.notifier).updateLastConnected(connection.id);
    // 既存セッションを開く場合は最終アクセス日時を更新
    if (sessionName != null) {
      ref
          .read(activeSessionsProvider.notifier)
          .touchSession(connection.id, sessionName, sessionId: sessionId);
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TerminalScreen(
          connectionId: connection.id,
          sessionName: sessionName,
          sessionId: sessionId,
        ),
      ),
    );
  }
}
