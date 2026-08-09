import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/active_session_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/session_history_provider.dart';
import '../../services/backend/domain/multiplexer_backend.dart';
import '../../services/herdr/herdr_adapter.dart';
import '../../services/herdr/herdr_to_domain.dart';
import '../../services/keychain/secure_storage.dart';
import '../../services/ssh/ssh_client.dart';
import '../../theme/design_colors.dart';
import '../connections/connection_form_screen.dart';
import '../terminal/terminal_screen.dart';

/// ダッシュボード画面（セッション履歴ベース）
class DashboardScreen extends ConsumerWidget {
  /// SSH 接続のテスト/DI 用ファクトリ（ConnectionsScreen と同じ契約）。
  ///
  /// 提供時は workspace 操作（[DashboardScreen._connectSshFor]）がこの
  /// ファクトリで接続を取得する。null なら [SecureStorageService] 経由で
  /// 実接続する（本番経路）。
  final Future<SshClient> Function(Connection connection)? sshClientFactory;

  const DashboardScreen({super.key, this.sshClientFactory});

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
                    final isHerdr =
                        session.backend == MultiplexerBackendKind.herdr;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SessionHistoryCard(
                        session: session,
                        onTap: () => _navigateToTerminal(context, ref, session),
                        onRemove: () => _removeFromHistory(ref, session),
                        // T16（Q-05）: herdr workspace の New/Kill を有効化する。
                        onNewWorkspace: isHerdr
                            ? () => _createHerdrWorkspace(context, ref, session)
                            : null,
                        onKillWorkspace: isHerdr
                            ? () => _killHerdrWorkspace(context, ref, session)
                            : null,
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
    // T16（Q-05）: herdr も mutation 可能。readOnly は呼び出し側明示の
    // opt-in としてのみ渡す（herdr による自動付与は廃止・H6）。

    // 最終アクセス日時を更新
    ref.read(activeSessionsProvider.notifier).touchSession(
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
    ref.read(activeSessionsProvider.notifier).removeSession(
          session.connectionId,
          session.sessionName,
          sessionId: session.sessionId,
        );
  }

  void _addNewConnection(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ConnectionFormScreen(),
      ),
    );
  }

  /// [session] の接続情報（[Connection]）で SSH 接続し、接続済みクライアントを
  /// 返す（connections 画面の `_connectSsh` と同型・Q-05 の dashboard 版）。
  Future<SshClient> _connectSshFor(WidgetRef ref, ActiveSession session) async {
    final connection = ref
        .read(connectionsProvider.notifier)
        .getById(session.connectionId);
    if (connection == null) {
      throw Exception('Connection not found: ${session.connectionId}');
    }
    final factory = sshClientFactory;
    if (factory != null) return factory(connection);
    final storage = SecureStorageService();
    SshConnectOptions options;
    if (connection.authMethod == 'key' && connection.keyId != null) {
      final privateKey = await storage.getPrivateKey(connection.keyId!);
      final passphrase = await storage.getPassphrase(connection.keyId!);
      options = SshConnectOptions(
        privateKey: privateKey,
        passphrase: passphrase,
        multiplexer: connection.multiplexer,
      );
    } else {
      final password = await storage.getPassword(connection.id);
      options = SshConnectOptions(
        password: password,
        multiplexer: connection.multiplexer,
      );
    }
    final sshClient = SshClient();
    await sshClient.connect(
      host: connection.host,
      port: connection.port,
      username: connection.username,
      options: options,
      lightweight: true,
    );
    return sshClient;
  }

  /// herdr workspace を作成する（Q-05: dashboard から `workspace create`）。
  ///
  /// [session] の接続先に新しい workspace を作り、スナップショット再取得で
  /// アクティブセッション一覧を更新する。
  Future<void> _createHerdrWorkspace(
    BuildContext context,
    WidgetRef ref,
    ActiveSession session,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _WorkspaceNameDialog(
        existingNames: ref
            .read(activeSessionsProvider)
            .getSessionsForConnection(session.connectionId)
            .map((s) => s.sessionName)
            .toList(),
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;

    SshClient? client;
    try {
      client = await _connectSshFor(ref, session);
      final adapter = HerdrAdapter(client);
      await adapter.workspaceCreate(label: name);
      final snapshot = await adapter.snapshot();
      ref.read(activeSessionsProvider.notifier).updateSessionsFromDomain(
            connectionId: session.connectionId,
            connectionName: session.connectionName,
            host: session.host,
            sessions: snapshot.toDomainSessions(),
            backend: MultiplexerBackendKind.herdr,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Workspace $name created')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create workspace: $e')),
        );
      }
    } finally {
      await client?.disconnect();
    }
  }

  /// herdr workspace を閉じる（Q-05: dashboard から `workspace close`）。
  ///
  /// workspace 内の全 tab / pane が連鎖終了するため、確認ダイアログで
  /// 明示した上で実行する（R2）。閉鎖後はスナップショット再取得で一覧を
  /// 同期し、履歴からも除去する。
  Future<void> _killHerdrWorkspace(
    BuildContext context,
    WidgetRef ref,
    ActiveSession session,
  ) async {
    final workspaceId = session.sessionId;
    if (workspaceId == null || workspaceId.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot close workspace without an ID')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close Workspace?'),
        content: Text(
          'Close herdr workspace "${session.sessionName}"? '
          'All tabs and panes in this workspace will be terminated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: DesignColors.error),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    SshClient? client;
    try {
      client = await _connectSshFor(ref, session);
      final adapter = HerdrAdapter(client);
      await adapter.workspaceClose(workspaceId);
      final snapshot = await adapter.snapshot();
      ref.read(activeSessionsProvider.notifier).updateSessionsFromDomain(
            connectionId: session.connectionId,
            connectionName: session.connectionName,
            host: session.host,
            sessions: snapshot.toDomainSessions(),
            backend: MultiplexerBackendKind.herdr,
          );
      ref.read(activeSessionsProvider.notifier).removeSession(
            session.connectionId,
            session.sessionName,
            sessionId: session.sessionId,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Workspace ${session.sessionName} closed')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to close workspace: $e')),
        );
      }
    } finally {
      await client?.disconnect();
    }
  }
}

/// セッション履歴カード
class _SessionHistoryCard extends StatelessWidget {
  final ActiveSession session;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  /// T16（Q-05）: herdr workspace の New / Kill アクション（null なら非表示）。
  final VoidCallback? onNewWorkspace;
  final VoidCallback? onKillWorkspace;

  const _SessionHistoryCard({
    required this.session,
    required this.onTap,
    required this.onRemove,
    this.onNewWorkspace,
    this.onKillWorkspace,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final isAttached = session.isAttached;
    final hasWorkspaceActions =
        onNewWorkspace != null || onKillWorkspace != null;

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
              // T16（Q-05）: herdr は workspace 操作メニュー（New / Kill）、
              // tmux は遷移矢印を表示する。
              if (hasWorkspaceActions)
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: isDark
                        ? DesignColors.textSecondary
                        : DesignColors.textSecondaryLight,
                  ),
                  tooltip: 'Workspace actions',
                  padding: EdgeInsets.zero,
                  itemBuilder: (menuContext) => [
                    if (onNewWorkspace != null)
                      PopupMenuItem(
                        value: 'new',
                        child: Row(
                          children: [
                            Icon(
                              Icons.add,
                              size: 18,
                              color: colorScheme.onSurface,
                            ),
                            const SizedBox(width: 8),
                            const Text('New Workspace'),
                          ],
                        ),
                      ),
                    if (onKillWorkspace != null)
                      PopupMenuItem(
                        value: 'kill',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: DesignColors.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Kill Workspace',
                              style: TextStyle(color: DesignColors.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onSelected: (value) {
                    if (value == 'new') onNewWorkspace?.call();
                    if (value == 'kill') onKillWorkspace?.call();
                  },
                )
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

/// 新規 herdr workspace 名の入力ダイアログ（Q-05: dashboard の New Workspace）。
class _WorkspaceNameDialog extends StatefulWidget {
  final List<String> existingNames;

  const _WorkspaceNameDialog({required this.existingNames});

  @override
  State<_WorkspaceNameDialog> createState() => _WorkspaceNameDialogState();
}

class _WorkspaceNameDialogState extends State<_WorkspaceNameDialog> {
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
    while (widget.existingNames.contains('workspace-$index')) {
      index++;
    }
    return 'workspace-$index';
  }

  String? _validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a workspace name';
    }
    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(value)) {
      return 'Only letters, numbers, - _ . allowed';
    }
    if (widget.existingNames.contains(value)) {
      return 'Workspace "$value" already exists';
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
        'New Workspace',
        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Workspace Name',
            hintText: 'workspace-1',
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
          validator: _validateName,
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
