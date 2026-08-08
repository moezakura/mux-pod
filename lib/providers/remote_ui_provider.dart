import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/agent/agent_adapter.dart';
import '../services/agent/agent_registry.dart';
import '../services/agent/agent_types.dart';
import '../services/ssh/connection_credentials.dart';
import '../services/ssh/ssh_client.dart';
import '../services/tmux/tmux_commands.dart';
import '../services/tmux/tmux_parser.dart';
import 'connection_provider.dart';

/// State for the Remote UI tab: which server is connected, which agent
/// (if any) was detected in its tmux panes, and the agent's last known
/// configuration.
class RemoteUiState {
  /// Selected server connection id, null when nothing is selected.
  final String? connectionId;

  /// True while the dedicated SSH connection is being established.
  final bool isConnecting;

  /// True when the dedicated SSH connection is ready.
  final bool isConnected;

  /// Adapter of the agent detected in a tmux pane, null when no known
  /// agent runs on the connected server.
  final AgentAdapter? agent;

  /// tmux pane id the detected agent runs in.
  final String? agentPaneId;

  /// Working directory of the agent pane (`pane_current_path`).
  final String? agentPanePath;

  /// Last known agent configuration.
  final AgentConfig config;

  /// True while a config read/apply operation is in flight.
  final bool isBusy;

  /// Last error message, if any.
  final String? error;

  /// Last confirmation message from an apply operation.
  final String? notice;

  const RemoteUiState({
    this.connectionId,
    this.isConnecting = false,
    this.isConnected = false,
    this.agent,
    this.agentPaneId,
    this.agentPanePath,
    this.config = const AgentConfig(),
    this.isBusy = false,
    this.error,
    this.notice,
  });

  static const _unset = Object();

  RemoteUiState copyWith({
    Object? connectionId = _unset,
    bool? isConnecting,
    bool? isConnected,
    Object? agent = _unset,
    Object? agentPaneId = _unset,
    Object? agentPanePath = _unset,
    AgentConfig? config,
    bool? isBusy,
    Object? error = _unset,
    Object? notice = _unset,
  }) {
    return RemoteUiState(
      connectionId: connectionId == _unset
          ? this.connectionId
          : connectionId as String?,
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      agent: agent == _unset ? this.agent : agent as AgentAdapter?,
      agentPaneId:
          agentPaneId == _unset ? this.agentPaneId : agentPaneId as String?,
      agentPanePath: agentPanePath == _unset
          ? this.agentPanePath
          : agentPanePath as String?,
      config: config ?? this.config,
      isBusy: isBusy ?? this.isBusy,
      error: error == _unset ? this.error : error as String?,
      notice: notice == _unset ? this.notice : notice as String?,
    );
  }
}

/// Manages the Remote UI tab's dedicated SSH connection and live-pane
/// agent control.
///
/// The tab owns its own [SshClient] (separate from the terminal screen's
/// global `sshProvider`) so that long-running chat streams and config
/// operations never block terminal input.
class RemoteUiNotifier extends Notifier<RemoteUiState> {
  SshClient? _client;

  @override
  RemoteUiState build() {
    ref.onDispose(() {
      unawaited(_client?.disconnect());
    });
    return const RemoteUiState();
  }

  /// The dedicated SSH connection used by the Remote UI tab, null until
  /// [selectServer] succeeds.
  SshClient? get client => _client;

  /// Connects to the server [connectionId] and detects running agents.
  Future<void> selectServer(String connectionId) async {
    final connection = ref.read(connectionsProvider.notifier).getById(connectionId);
    if (connection == null) return;

    state = state.copyWith(
      isConnecting: true,
      isConnected: false,
      error: null,
      notice: null,
    );

    final previous = _client;
    _client = null;
    if (previous != null) await previous.disconnect();

    final client = SshClient();
    try {
      final options = await ConnectionCredentials.resolve(
        connectionId: connection.id,
        authMethod: connection.authMethod,
        keyId: connection.keyId,
        tmuxPath: connection.tmuxPath,
      );

      await client.connect(
        host: connection.host,
        port: connection.port,
        username: connection.username,
        options: options,
      );

      _client = client;
      state = state.copyWith(
        connectionId: connectionId,
        isConnecting: false,
        isConnected: true,
      );
      await refresh();
    } on Object catch (e) {
      await client.disconnect();
      state = state.copyWith(
        isConnecting: false,
        isConnected: false,
        agent: null,
        agentPaneId: null,
        agentPanePath: null,
        error: '$e',
      );
    }
  }

  /// Disconnects from the current server and clears detection state.
  Future<void> disconnect() async {
    final client = _client;
    _client = null;
    if (client != null) await client.disconnect();
    state = const RemoteUiState();
  }

  /// Re-scans the server's tmux panes for a known agent and re-reads its
  /// configuration.
  Future<void> refresh() async {
    final client = _client;
    if (client == null || !client.isConnected) return;

    state = state.copyWith(isBusy: true, error: null);
    try {
      final output = await client.execPersistent(TmuxCommands.listAllPanes());
      final sessions = TmuxParser.parseFullTree(output);

      AgentAdapter? found;
      String? paneId;
      String? panePath;
      for (final session in sessions) {
        for (final window in session.windows) {
          for (final pane in window.panes) {
            final adapter = AgentRegistry.detect(pane.currentCommand);
            if (adapter != null) {
              found = adapter;
              paneId = pane.id;
              panePath = pane.currentPath;
              break;
            }
          }
          if (found != null) break;
        }
        if (found != null) break;
      }

      var config = const AgentConfig();
      if (found != null) {
        config = await found.readConfig(
          AgentContext(
            ssh: client,
            paneId: paneId!,
            paneWorkingDirectory: panePath,
          ),
        );
      }

      state = state.copyWith(
        agent: found,
        agentPaneId: paneId,
        agentPanePath: panePath,
        config: config,
        isBusy: false,
      );
    } on Object catch (e) {
      state = state.copyWith(isBusy: false, error: '$e');
    }
  }

  /// Applies a model switch to the detected live-pane agent.
  Future<void> applyModel(String model) =>
      _apply((adapter, context) => adapter.applyModel(context, model));

  /// Applies a reasoning-effort change to the detected live-pane agent.
  Future<void> applyIntelligence(UnifiedIntelligence level) =>
      _apply((adapter, context) => adapter.applyIntelligence(context, level));

  /// Applies an autonomy/permission change to the detected live-pane
  /// agent.
  Future<void> applyPermission(UnifiedPermission level) =>
      _apply((adapter, context) => adapter.applyPermission(context, level));

  /// Toggles plan/spec mode on the detected live-pane agent.
  Future<void> setPlanMode(bool enabled) =>
      _apply((adapter, context) => adapter.setPlanMode(context, enabled));

  /// Clears the current notice/error after the UI has shown it.
  void clearMessages() {
    state = state.copyWith(error: null, notice: null);
  }

  Future<void> _apply(
    Future<String> Function(AgentAdapter adapter, AgentContext context)
        action,
  ) async {
    final adapter = state.agent;
    final client = _client;
    final paneId = state.agentPaneId;
    if (adapter == null || client == null || paneId == null) return;

    state = state.copyWith(isBusy: true, error: null, notice: null);
    final context = AgentContext(
      ssh: client,
      paneId: paneId,
      paneWorkingDirectory: state.agentPanePath,
    );
    try {
      final message = await action(adapter, context);
      // Re-read the effective config best effort; a failed re-read must
      // not mask the successful apply.
      var config = state.config;
      try {
        config = await adapter.readConfig(context);
      } on Object {
        // Keep the previous snapshot.
      }
      state = state.copyWith(isBusy: false, notice: message, config: config);
    } on Object catch (e) {
      state = state.copyWith(isBusy: false, error: '$e');
    }
  }
}

/// Provider for the Remote UI tab.
final remoteUiProvider =
    NotifierProvider<RemoteUiNotifier, RemoteUiState>(RemoteUiNotifier.new);
