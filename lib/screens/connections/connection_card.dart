import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/active_session_provider.dart'
    show ActiveSession, activeSessionsProvider;
import '../../providers/connection_provider.dart' show Connection;
import '../../providers/key_provider.dart' show isKeyDamaged, keysProvider;
import '../../services/backend/backend_type.dart' show BackendType;
import '../../services/backend/domain/multiplexer_backend.dart'
    show MultiplexerBackendKind;
import '../../services/backend/domain/multiplexer_session.dart'
    show MultiplexerSession;
import '../../services/herdr/herdr_models.dart' show HerdrSnapshot;
import '../../services/herdr/herdr_to_domain.dart';
import '../../services/ssh/ssh_client.dart' show SshClient;
import '../../services/tmux/tmux_models.dart' show TmuxSession;
import '../../services/tmux/tmux_to_domain.dart';
import '../../theme/design_colors.dart';

import 'connection_card_header.dart' show CardHeader;
import 'connection_new_session_dialog.dart' show NewSessionDialog;
import 'connection_session_operations.dart' show ConnectionSessionOperations;
import 'connection_sessions_panel.dart' show ExpandedSessionsPanel;

/// 接続カード（展開可能、tmux セッション / herdr workspace 表示）。
///
/// P3 分割: private `_ConnectionCard` から素の public に昇格
/// （feature 内部利用。分割に伴う公開化）。
class ConnectionCard extends ConsumerStatefulWidget {
  final Connection connection;
  final Future<SshClient> Function(Connection connection)? sshClientFactory;
  final void Function(String? sessionName, {String? sessionId}) onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ConnectionCard({
    super.key,
    required this.connection,
    this.sshClientFactory,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  ConsumerState<ConnectionCard> createState() => ConnectionCardState();
}

class ConnectionCardState extends ConsumerState<ConnectionCard> {
  /// セッション操作の協調オブジェクト（ref 非依存・戻り値受領）。
  final ConnectionSessionOperations _operations = ConnectionSessionOperations();

  bool _isExpanded = false;
  bool _isLoadingSessions = false;
  List<TmuxSession> _sessions = [];
  String? _sessionError;

  /// herdr 接続のスナップショット（T16/Q-05: workspace 一覧表示 + mutation 後同期用）。
  HerdrSnapshot? _herdrSnapshot;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // アクティブセッションからこの接続のセッション情報を取得
    final activeSessionsState = ref.watch(activeSessionsProvider);
    final activeSessions = activeSessionsState.getSessionsForConnection(
      widget.connection.id,
    );
    final hasActiveSessions = activeSessions.isNotEmpty;

    // 破損キー（秘密鍵を読み出せない鍵）を参照している接続かどうか
    final keysState = ref.watch(keysProvider);
    final hasDamagedKey = isKeyDamaged(keysState, widget.connection.keyId);

    // 接続状態の判定（アクティブセッションがあるか、lastConnectedAtがあるか）
    final isConnected =
        hasActiveSessions || widget.connection.lastConnectedAt != null;
    final statusColor = hasActiveSessions
        ? DesignColors.success
        : (isConnected
              ? Colors.orange
              : (isDark
                    ? DesignColors.textMuted
                    : DesignColors.textMutedLight));

    return Container(
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
      child: Column(
        children: [
          // Card Header
          CardHeader(
            connection: widget.connection,
            isExpanded: _isExpanded,
            hasActiveSessions: hasActiveSessions,
            statusColor: statusColor,
            hasDamagedKey: hasDamagedKey,
            onTap: _toggleExpand,
          ),
          // Expanded Content - Sessions List
          if (_isExpanded) _buildExpandedContent(activeSessions),
        ],
      ),
    );
  }

  /// 接続の backend 種別（表示側の backend 固有分岐用）。
  MultiplexerBackendKind get _backendKind {
    return switch (widget.connection.multiplexer.backend) {
      BackendType.tmux => MultiplexerBackendKind.tmux,
      BackendType.herdr => MultiplexerBackendKind.herdr,
    };
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    // 展開時にセッション/スナップショット情報をフェッチ
    if (!_isExpanded) return;
    final isHerdr = _backendKind == MultiplexerBackendKind.herdr;
    if (isHerdr) {
      if (_herdrSnapshot == null && !_isLoadingSessions) {
        _fetchSessions();
      }
    } else if (_sessions.isEmpty && !_isLoadingSessions) {
      _fetchSessions();
    }
  }

  /// セッション一覧を取得し、状態と provider へ反映する。
  ///
  /// 接続（[ConnectionSessionOperations.connect]）は呼び出し時に行い、
  /// 戻り値（snapshot / raw sessions）をこの State が受領して
  /// `updateSessionsFromDomain` へ渡す（operations は ref 非依存）。
  Future<void> _fetchSessions() async {
    setState(() {
      _isLoadingSessions = true;
      _sessionError = null;
    });

    SshClient? client;
    try {
      client = await _operations.connect(
        connection: widget.connection,
        factory: widget.sshClientFactory,
        l10n: context.l10n,
      );
      if (_backendKind == MultiplexerBackendKind.herdr) {
        // herdr: スナップショットを取得して共通 domain に変換する。
        final snapshot = await _operations.fetchHerdrSnapshot(client);
        if (!mounted) return;
        setState(() {
          _herdrSnapshot = snapshot;
          _isLoadingSessions = false;
        });
        // アクティブセッションへも共通 domain 経由で登録する。
        ref
            .read(activeSessionsProvider.notifier)
            .updateSessionsFromDomain(
              connectionId: widget.connection.id,
              connectionName: widget.connection.name,
              host: widget.connection.host,
              sessions: snapshot.toDomainSessions(),
              backend: MultiplexerBackendKind.herdr,
            );
      } else {
        await _reloadSessions(client);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSessions = false;
        _sessionError = e.toString();
      });
    } finally {
      await client?.disconnect();
    }
  }

  /// 接続済みクライアントでセッション一覧を取得し、状態とproviderへ反映する。
  Future<void> _reloadSessions(SshClient client) async {
    final sessions = await _operations.fetchTmuxSessions(client);
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _isLoadingSessions = false;
    });
    ref
        .read(activeSessionsProvider.notifier)
        .updateSessionsFromDomain(
          connectionId: widget.connection.id,
          connectionName: widget.connection.name,
          host: widget.connection.host,
          sessions: sessions.map((s) => s.toDomain()).toList(),
          backend: MultiplexerBackendKind.tmux,
        );
  }

  /// セッション / workspace を kill する（確認ダイアログ付き）。
  ///
  /// tmux: `kill-session` / herdr: `workspace close`（連鎖 close の警告）。
  /// kill と一覧再取得を同一接続で行い、SSH往復を1回に抑える。
  Future<void> _killSession(MultiplexerSession session) async {
    if (_backendKind == MultiplexerBackendKind.herdr) {
      await _killHerdrWorkspace(session);
      return;
    }

    final sessionName = session.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.connKillSessionTitle),
        content: Text(context.l10n.connKillSessionMessage(sessionName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.connCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: DesignColors.error),
            child: Text(context.l10n.connKill),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isLoadingSessions = true;
      _sessionError = null;
    });

    SshClient? client;
    try {
      client = await _operations.connect(
        connection: widget.connection,
        factory: widget.sshClientFactory,
        l10n: context.l10n,
      );
      // 同一接続でそのまま一覧を再取得（kill → reload の await 順序を維持）
      final sessions = await _operations.killSessionAndReload(
        client,
        sessionName,
      );
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _isLoadingSessions = false;
      });
      ref
          .read(activeSessionsProvider.notifier)
          .updateSessionsFromDomain(
            connectionId: widget.connection.id,
            connectionName: widget.connection.name,
            host: widget.connection.host,
            sessions: sessions.map((s) => s.toDomain()).toList(),
            backend: MultiplexerBackendKind.tmux,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.connSessionKilled(sessionName))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSessions = false;
        _sessionError = e.toString();
      });
    } finally {
      await client?.disconnect();
    }
  }

  /// herdr workspace を閉じる（Q-05: `herdr workspace close`）。
  ///
  /// workspace 内の全 tab / pane が連鎖終了するため、確認ダイアログで
  /// 明示した上で実行する（R2: 連鎖 close の破壊）。閉鎖後の一覧は
  /// スナップショット再取得で同期する。
  Future<void> _killHerdrWorkspace(MultiplexerSession workspace) async {
    final workspaceId = workspace.id;
    if (workspaceId == null || workspaceId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.connCannotCloseWorkspace)),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.connCloseWorkspaceTitle),
        content: Text(context.l10n.connCloseWorkspaceMessage(workspace.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.connCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: DesignColors.error),
            child: Text(context.l10n.connClose),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isLoadingSessions = true;
      _sessionError = null;
    });

    SshClient? client;
    try {
      client = await _operations.connect(
        connection: widget.connection,
        factory: widget.sshClientFactory,
        l10n: context.l10n,
      );
      final snapshot = await _operations.closeWorkspace(client, workspaceId);
      if (!mounted) return;
      setState(() {
        _herdrSnapshot = snapshot;
        _isLoadingSessions = false;
      });
      ref
          .read(activeSessionsProvider.notifier)
          .updateSessionsFromDomain(
            connectionId: widget.connection.id,
            connectionName: widget.connection.name,
            host: widget.connection.host,
            sessions: snapshot.toDomainSessions(),
            backend: MultiplexerBackendKind.herdr,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.connWorkspaceClosed(workspace.name)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSessions = false;
        _sessionError = e.toString();
      });
    } finally {
      await client?.disconnect();
    }
  }

  Widget _buildExpandedContent(List<ActiveSession> activeSessions) {
    // Tmux/Herdr を共通 domain モデル（MultiplexerSession）で表示する。
    // T16（Q-05）: herdr も workspace 操作（New/Kill）を有効化する。
    final sessions = _backendKind == MultiplexerBackendKind.herdr
        ? (_herdrSnapshot?.toDomainSessions() ?? const <MultiplexerSession>[])
        : _sessions.map((s) => s.toDomain()).toList();

    // tmux / herdr とも provider の最新ウィンドウ数を優先（ターミナルでの
    // ウィンドウ作成/削除後もカウンタが追従するようにする）。
    // キーは sessionId ?? sessionName（ID 優先）で、同名ラベル（herdr の
    // "tmp" w3/w4）によるカウント混線を防ぐ。
    final liveWindowCounts = {
      for (final a in activeSessions)
        a.sessionId ?? a.sessionName: a.windowCount,
    };

    return ExpandedSessionsPanel(
      sessions: sessions,
      liveWindowCounts: liveWindowCounts,
      isLoading: _isLoadingSessions,
      sessionError: _sessionError,
      backendKind: _backendKind,
      onReload: _fetchSessions,
      onNewSession: _showNewSessionDialog,
      onEdit: widget.onEdit,
      onDelete: widget.onDelete,
      onSessionTap: (sessionName, sessionId) =>
          widget.onConnect(sessionName, sessionId: sessionId),
      onKill: _killSession,
    );
  }

  Future<void> _showNewSessionDialog() async {
    // tmux: セッション名 / herdr: workspace 名。既存名で重複チェックする。
    final existingSessionNames = _backendKind == MultiplexerBackendKind.herdr
        ? (_herdrSnapshot?.toDomainSessions() ?? const <MultiplexerSession>[])
              .map((s) => s.name)
              .toList()
        : _sessions.map((s) => s.name).toList();

    final sessionName = await showDialog<String>(
      context: context,
      builder: (context) =>
          NewSessionDialog(existingSessionNames: existingSessionNames),
    );

    if (sessionName == null || sessionName.isEmpty) return;
    if (_backendKind == MultiplexerBackendKind.herdr) {
      // Q-05: herdr は workspace を作成する。
      await _createHerdrWorkspace(sessionName);
    } else {
      widget.onConnect(sessionName);
    }
  }

  /// herdr workspace を作成する（Q-05: `herdr workspace create`）。
  ///
  /// 作成とスナップショット再取得を同一 SSH 接続で行い、一覧と
  /// アクティブセッションを更新する。
  Future<void> _createHerdrWorkspace(String label) async {
    setState(() {
      _isLoadingSessions = true;
      _sessionError = null;
    });

    SshClient? client;
    try {
      client = await _operations.connect(
        connection: widget.connection,
        factory: widget.sshClientFactory,
        l10n: context.l10n,
      );
      final snapshot = await _operations.createWorkspace(client, label);
      if (!mounted) return;
      setState(() {
        _herdrSnapshot = snapshot;
        _isLoadingSessions = false;
      });
      ref
          .read(activeSessionsProvider.notifier)
          .updateSessionsFromDomain(
            connectionId: widget.connection.id,
            connectionName: widget.connection.name,
            host: widget.connection.host,
            sessions: snapshot.toDomainSessions(),
            backend: MultiplexerBackendKind.herdr,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.connWorkspaceCreated(label))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSessions = false;
        _sessionError = e.toString();
      });
    } finally {
      await client?.disconnect();
    }
  }
}
