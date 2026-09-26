import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/background/foreground_task_service.dart';
import '../services/network/network_monitor.dart';
import '../services/ssh/ssh_client.dart';
import 'connection_provider.dart';
import 'ssh_connection_orchestrator.dart';
import 'ssh_reconnect_policy.dart';
import 'ssh_state.dart';

export 'ssh_state.dart';

/// SSH接続を管理するNotifier
///
/// 公開面（facade）: [SshState] を公開し、接続オーケストレーション
/// （[SshConnectionOrchestrator]）と再接続ポリシー（[SshReconnectPolicy]）
/// を合成する。build() でネットワーク監視の開始と onDispose クリーンアップ
/// を統括し、SSH の全公開 API を orchestrator / policy へ委譲する。
class SshNotifier extends Notifier<SshState> {
  final SshForegroundTaskService _foregroundService =
      SshForegroundTaskService();

  /// 接続オーケストレーション（クライアント保有・切断検知・再接続実行）
  late final SshConnectionOrchestrator _orchestrator =
      SshConnectionOrchestrator(
        getState: () => state,
        updateState: (transform) {
          state = transform(state);
        },
        requestReconnect: () => _reconnectPolicy.reconnect(),
        shouldScheduleNextAttempt: () =>
            _reconnectPolicy.shouldScheduleNextAttempt,
        onLastConnected: (id) {
          ref.read(connectionsProvider.notifier).updateLastConnected(id);
        },
        startForeground: (connectionName, host, l10n) =>
            _foregroundService.startService(
              connectionName: connectionName,
              host: host,
              l10n: l10n,
            ),
        stopForeground: () => _foregroundService.stopService(),
      );

  /// 再接続ポリシー（バックオフ・ネットワーク監視）
  late final SshReconnectPolicy _reconnectPolicy = SshReconnectPolicy(
    reconnectAction: () => _orchestrator.reconnectConnection(),
    hasLastConnection: () => _orchestrator.hasCachedConnection,
    getState: () => state,
    updateState: (transform) {
      state = transform(state);
    },
  );

  @override
  SshState build() {
    // ネットワーク状態を監視
    final monitor = ref.read(networkMonitorProvider);
    _reconnectPolicy.startNetworkMonitoring(monitor.statusStream);

    // クリーンアップを登録
    ref.onDispose(() {
      _reconnectPolicy.stop();
      _orchestrator.dispose();
      _foregroundService.stopService();
    });
    return const SshState();
  }

  /// 切断検知コールバック（外部から設定可能）
  void Function()? get onDisconnectDetected =>
      _orchestrator.onDisconnectDetected;
  set onDisconnectDetected(void Function()? v) =>
      _orchestrator.onDisconnectDetected = v;

  /// 再接続成功コールバック（外部から設定可能）
  void Function()? get onReconnectSuccess => _orchestrator.onReconnectSuccess;
  set onReconnectSuccess(void Function()? v) =>
      _orchestrator.onReconnectSuccess = v;

  /// SSHクライアントを取得
  SshClient? get client => _orchestrator.client;

  /// 最後の接続情報
  Connection? get lastConnection => _orchestrator.lastConnection;

  /// 最後の接続オプション
  SshConnectOptions? get lastOptions => _orchestrator.lastOptions;

  /// SSH接続を確立（シェル付き - 従来方式）
  Future<void> connect(Connection connection, SshConnectOptions options) =>
      _orchestrator.connect(connection, options);

  /// SSH接続を確立（シェルなし - tmuxコマンド方式用）
  ///
  /// exec()のみ使用するため、シェルは起動しない。
  Future<void> connectWithoutShell(
    Connection connection,
    SshConnectOptions options,
  ) => _orchestrator.connectWithoutShell(connection, options);

  /// 再接続を試みる
  ///
  /// 自動再接続用。指数バックオフで無制限に試行する。
  /// ネットワークがオフラインの場合は一時停止し、復帰時に自動再開。
  Future<bool> reconnect() => _reconnectPolicy.reconnect();

  /// 今すぐ再接続を試みる（ユーザー操作用）
  Future<bool> reconnectNow() => _reconnectPolicy.reconnectNow();

  void setMaintenanceEnabled(bool enabled) {
    _orchestrator.setMaintenanceEnabled(enabled);
    _reconnectPolicy.setEnabled(enabled);
  }

  Future<void> verifyOrReconnect() async {
    // A lifecycle resume must not tear down an initial/manual connection.
    if (state.isConnecting || state.isReconnecting) return;
    final current = client;
    if (current != null && await current.verifyConnection()) return;
    if (!ref.mounted ||
        current != client ||
        state.isConnecting ||
        state.isReconnecting) {
      return;
    }
    await _reconnectPolicy.reconnectNow();
  }

  /// 接続がアクティブかチェック
  bool checkConnection() => _orchestrator.checkConnection();

  /// 再接続状態をリセット
  void resetReconnect() => _reconnectPolicy.reset();

  /// 切断
  Future<void> disconnect() async {
    // 再接続タイマーをキャンセル
    _reconnectPolicy.cancelTimer();
    await _orchestrator.disconnect();
  }

  /// セッションタイトルを更新
  void updateSessionTitle(String title) {
    state = state.copyWith(sessionTitle: title);
  }

  /// データを送信
  void write(String data) => _orchestrator.write(data);

  /// ターミナルサイズを変更
  void resize(int cols, int rows) => _orchestrator.resize(cols, rows);
}

/// SSHプロバイダー
final sshProvider = NotifierProvider<SshNotifier, SshState>(() {
  return SshNotifier();
});
