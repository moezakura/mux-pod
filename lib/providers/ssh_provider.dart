import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/background/foreground_task_service.dart';
import '../services/ssh/ssh_client.dart';
import 'connection_provider.dart';

/// SSH接続状態
class SshState {
  final SshConnectionState connectionState;
  final String? error;
  final String? sessionTitle;

  const SshState({
    this.connectionState = SshConnectionState.disconnected,
    this.error,
    this.sessionTitle,
  });

  SshState copyWith({
    SshConnectionState? connectionState,
    String? error,
    String? sessionTitle,
  }) {
    return SshState(
      connectionState: connectionState ?? this.connectionState,
      error: error,
      sessionTitle: sessionTitle ?? this.sessionTitle,
    );
  }

  bool get isConnected => connectionState == SshConnectionState.connected;
  bool get isConnecting => connectionState == SshConnectionState.connecting;
  bool get isDisconnected => connectionState == SshConnectionState.disconnected;
  bool get hasError => connectionState == SshConnectionState.error;
}

/// SSH接続を管理するNotifier
class SshNotifier extends Notifier<SshState> {
  SshClient? _client;
  final SshForegroundTaskService _foregroundService = SshForegroundTaskService();

  @override
  SshState build() {
    // クリーンアップを登録
    ref.onDispose(() {
      _client?.dispose();
      _foregroundService.stopService();
    });
    return const SshState();
  }

  /// SSHクライアントを取得
  SshClient? get client => _client;

  /// SSH接続を確立（シェル付き - 従来方式）
  Future<void> connect(Connection connection, SshConnectOptions options) async {
    state = state.copyWith(
      connectionState: SshConnectionState.connecting,
      error: null,
    );

    try {
      _client = SshClient();

      await _client!.connect(
        host: connection.host,
        port: connection.port,
        username: connection.username,
        options: options,
      );

      await _client!.startShell();

      state = state.copyWith(
        connectionState: SshConnectionState.connected,
      );

      // 最終接続日時を更新
      ref.read(connectionsProvider.notifier).updateLastConnected(connection.id);

      // Foreground Serviceを開始してバックグラウンドでも接続を維持
      await _foregroundService.startService(
        connectionName: connection.name,
        host: connection.host,
      );
    } on SshConnectionError catch (e) {
      state = state.copyWith(
        connectionState: SshConnectionState.error,
        error: e.message,
      );
      _client?.dispose();
      _client = null;
    } on SshAuthenticationError catch (e) {
      state = state.copyWith(
        connectionState: SshConnectionState.error,
        error: e.message,
      );
      _client?.dispose();
      _client = null;
    } catch (e) {
      state = state.copyWith(
        connectionState: SshConnectionState.error,
        error: e.toString(),
      );
      _client?.dispose();
      _client = null;
    }
  }

  /// SSH接続を確立（シェルなし - tmuxコマンド方式用）
  ///
  /// exec()のみ使用するため、シェルは起動しない。
  Future<void> connectWithoutShell(Connection connection, SshConnectOptions options) async {
    state = state.copyWith(
      connectionState: SshConnectionState.connecting,
      error: null,
    );

    try {
      _client = SshClient();

      await _client!.connect(
        host: connection.host,
        port: connection.port,
        username: connection.username,
        options: options,
      );

      // シェルは起動しない（exec専用）

      state = state.copyWith(
        connectionState: SshConnectionState.connected,
      );

      // 最終接続日時を更新
      ref.read(connectionsProvider.notifier).updateLastConnected(connection.id);

      // Foreground Serviceを開始してバックグラウンドでも接続を維持
      await _foregroundService.startService(
        connectionName: connection.name,
        host: connection.host,
      );
    } on SshConnectionError catch (e) {
      state = state.copyWith(
        connectionState: SshConnectionState.error,
        error: e.message,
      );
      _client?.dispose();
      _client = null;
    } on SshAuthenticationError catch (e) {
      state = state.copyWith(
        connectionState: SshConnectionState.error,
        error: e.message,
      );
      _client?.dispose();
      _client = null;
    } catch (e) {
      state = state.copyWith(
        connectionState: SshConnectionState.error,
        error: e.toString(),
      );
      _client?.dispose();
      _client = null;
    }
  }

  /// 切断
  Future<void> disconnect() async {
    // Foreground Serviceを停止
    await _foregroundService.stopService();

    await _client?.disconnect();
    _client = null;
    state = state.copyWith(
      connectionState: SshConnectionState.disconnected,
      error: null,
      sessionTitle: null,
    );
  }

  /// セッションタイトルを更新
  void updateSessionTitle(String title) {
    state = state.copyWith(sessionTitle: title);
  }

  /// データを送信
  void write(String data) {
    _client?.write(data);
  }

  /// ターミナルサイズを変更
  void resize(int cols, int rows) {
    _client?.resize(cols, rows);
  }
}

/// SSHプロバイダー
final sshProvider = NotifierProvider<SshNotifier, SshState>(() {
  return SshNotifier();
});
