import 'dart:async';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_lookup.dart';
import '../../services/ssh/ssh_client.dart';
import 'connection_provider.dart';
import 'ssh_state.dart';

/// SSH 接続のオーケストレーション（協調オブジェクト）
///
/// `ssh_provider.dart`（[SshNotifier]）からのみ生成・保有される。
/// SSH クライアントの生成・破棄・保有、接続状態ストリーム購読と切断検知、
/// write / resize / checkConnection を担う。再接続の必須内部状態
/// （`_lastConnection` / `_lastOptions`）の保有者でもある。
///
/// 再接続ポリシー（[SshReconnectPolicy]）とはクロージャ注入のみで結合し、
/// クラス参照を持たない（非循環）。状態の読み書きはすべて注入された
/// `getState` / `updateState` 経由で行う。
class SshConnectionOrchestrator {
  final SshState Function() _getState;
  final void Function(SshState Function(SshState)) _updateState;
  final Future<bool> Function() _requestReconnect;
  final bool Function() _shouldScheduleNextAttempt;
  final void Function(String connectionId) _onLastConnected;
  final Future<void> Function(
    String connectionName,
    String host,
    AppLocalizations l10n,
  )
  _startForeground;
  final Future<void> Function() _stopForeground;

  /// SshClient 生成の注入（テスト用・未注入時は実物）。
  final SshClient Function() _clientFactory;

  SshClient? _client;

  // 再接続用のキャッシュ
  Connection? _lastConnection;
  SshConnectOptions? _lastOptions;

  // 接続状態監視用
  StreamSubscription<SshConnectionState>? _connectionStateSubscription;

  // 再接続の single-flight（Codex B3）: timer callback と reconnectNow の同時
  // 実行を防ぎ、進行中の結果を共有する。
  bool _reconnectInFlight = false;
  Completer<bool>? _reconnectInFlightResult;

  /// 切断検知コールバック（外部から設定可能・ハンドラの単一所有者）
  void Function()? onDisconnectDetected;

  /// 再接続成功コールバック（外部から設定可能・ハンドラの単一所有者）
  void Function()? onReconnectSuccess;

  SshConnectionOrchestrator({
    required SshState Function() getState,
    required void Function(SshState Function(SshState)) updateState,
    required Future<bool> Function() requestReconnect,
    required bool Function() shouldScheduleNextAttempt,
    required void Function(String connectionId) onLastConnected,
    required Future<void> Function(
      String connectionName,
      String host,
      AppLocalizations l10n,
    )
    startForeground,
    required Future<void> Function() stopForeground,
    SshClient Function()? clientFactory,
  }) : _getState = getState,
       _updateState = updateState,
       _requestReconnect = requestReconnect,
       _shouldScheduleNextAttempt = shouldScheduleNextAttempt,
       _onLastConnected = onLastConnected,
       _startForeground = startForeground,
       _stopForeground = stopForeground,
       // テスト用注入（未注入時は実物。実装計画 §L4 テスト10: 再接続時に
       // fake SshClient が受ける options の振る舞いで検証するための注入点）。
       _clientFactory = clientFactory ?? SshClient.new;

  /// 設定言語から解決したローカライズ文字列。
  AppLocalizations get _l10n => lookupL10n();

  /// SSHクライアントを取得
  SshClient? get client => _client;

  /// 最後の接続情報
  Connection? get lastConnection => _lastConnection;

  /// 最後の接続オプション
  SshConnectOptions? get lastOptions => _lastOptions;

  /// 再接続可能な接続情報がキャッシュ済みか
  bool get hasCachedConnection =>
      _lastConnection != null && _lastOptions != null;

  /// SSH接続を確立（シェル付き - 従来方式）
  Future<void> connect(Connection connection, SshConnectOptions options) async {
    _updateState(
      (s) => s.copyWith(
        connectionState: SshConnectionState.connecting,
        error: null,
      ),
    );

    try {
      _client = _clientFactory();

      await _client!.connect(
        host: connection.host,
        port: connection.port,
        username: connection.username,
        options: options,
        l10n: _l10n,
      );

      await _client!.startShell();

      _updateState(
        (s) => s.copyWith(connectionState: SshConnectionState.connected),
      );

      // 最終接続日時を更新
      _onLastConnected(connection.id);

      // Foreground Serviceを開始してバックグラウンドでも接続を維持
      await _startForeground(connection.name, connection.host, _l10n);
    } on SshConnectionError catch (e) {
      _updateState(
        (s) => s.copyWith(
          connectionState: SshConnectionState.error,
          error: e.toString(),
        ),
      );
      _client?.dispose();
      _client = null;
    } on SshAuthenticationError catch (e) {
      _updateState(
        (s) => s.copyWith(
          connectionState: SshConnectionState.error,
          error: e.toString(),
        ),
      );
      _client?.dispose();
      _client = null;
    } catch (e) {
      _updateState(
        (s) => s.copyWith(
          connectionState: SshConnectionState.error,
          error: e.toString(),
        ),
      );
      _client?.dispose();
      _client = null;
    }
  }

  /// SSH接続を確立（シェルなし - tmuxコマンド方式用）
  ///
  /// exec()のみ使用するため、シェルは起動しない。
  Future<void> connectWithoutShell(
    Connection connection,
    SshConnectOptions options,
  ) async {
    // 再接続用にキャッシュ
    _lastConnection = connection;
    _lastOptions = options;

    // 既存の接続状態監視をキャンセル
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    _updateState(
      (s) => s.copyWith(
        connectionState: SshConnectionState.connecting,
        error: null,
        isReconnecting: false,
        reconnectAttempt: 0,
      ),
    );

    try {
      _client = _clientFactory();

      // 接続状態のストリームを監視（切断検知の高速化）
      _connectionStateSubscription = _client!.connectionStateStream.listen(
        _onConnectionStateChanged,
      );

      await _client!.connect(
        host: connection.host,
        port: connection.port,
        username: connection.username,
        options: options,
        l10n: _l10n,
      );

      // シェルは起動しない（exec専用）

      _updateState(
        (s) => s.copyWith(
          connectionState: SshConnectionState.connected,
          isReconnecting: false,
          reconnectAttempt: 0,
        ),
      );

      // 最終接続日時を更新
      _onLastConnected(connection.id);

      // Foreground Serviceを開始してバックグラウンドでも接続を維持
      await _startForeground(connection.name, connection.host, _l10n);
    } on SshConnectionError catch (e) {
      _updateState(
        (s) => s.copyWith(
          connectionState: SshConnectionState.error,
          error: e.toString(),
        ),
      );
      _client?.dispose();
      _client = null;
    } on SshAuthenticationError catch (e) {
      _updateState(
        (s) => s.copyWith(
          connectionState: SshConnectionState.error,
          error: e.toString(),
        ),
      );
      _client?.dispose();
      _client = null;
    } catch (e) {
      _updateState(
        (s) => s.copyWith(
          connectionState: SshConnectionState.error,
          error: e.toString(),
        ),
      );
      _client?.dispose();
      _client = null;
    }
  }

  /// 接続状態変化のハンドラ
  ///
  /// Keep-aliveやソケットからの切断検知を即座に処理する。
  void _onConnectionStateChanged(SshConnectionState newState) {
    // 接続中の状態から切断/エラーになった場合
    if (_getState().isConnected &&
        (newState == SshConnectionState.error ||
            newState == SshConnectionState.disconnected)) {
      // 状態を更新
      _updateState(
        (s) => s.copyWith(
          connectionState: newState,
          error: newState == SshConnectionState.error
              ? (_client?.lastError ?? _l10n.sshConnectionLost)
              : null,
        ),
      );

      // 切断検知コールバックを呼び出し
      onDisconnectDetected?.call();

      // 自動再接続を試みる（すでに再接続中でなければ）
      if (!_getState().isReconnecting) {
        _requestReconnect();
      }
    }
  }

  /// 実際の再接続処理
  ///
  /// **single-flight（Codex B3）**: timer callback（[reconnect]）と
  /// [reconnectNow] の両方から同時に呼ばれ得るため、実行中は重複実行せず
  /// 進行中の結果を共有する（古い完了結果による state 上書きも発生しない）。
  Future<bool> reconnectConnection() async {
    if (_reconnectInFlight) {
      return _reconnectInFlightResult?.future ?? false;
    }
    _reconnectInFlight = true;
    final completer = Completer<bool>();
    _reconnectInFlightResult = completer;
    try {
      if (_lastConnection == null || _lastOptions == null) {
        completer.complete(false);
        return false;
      }

      // ネットワークがオフラインの場合は中断
      if (!_getState().isNetworkAvailable) {
        _updateState((s) => s.copyWith(isPaused: true));
        completer.complete(false);
        return false;
      }

      // 既存の接続状態監視をキャンセル
      await _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;

      // 古いクライアントをクリーンアップ（await: 旧 managed PTY / TUI が
      // 閉じる前に新クライアントで起動しないことを保証・Codex B3）。
      await _client?.dispose();
      _client = _clientFactory();

      // 接続状態のストリームを監視（切断検知の高速化）
      _connectionStateSubscription = _client!.connectionStateStream.listen(
        _onConnectionStateChanged,
      );

      await _client!.connect(
        host: _lastConnection!.host,
        port: _lastConnection!.port,
        username: _lastConnection!.username,
        options: _lastOptions!,
        l10n: _l10n,
      );

      _updateState(
        (s) => s.copyWith(
          connectionState: SshConnectionState.connected,
          isReconnecting: false,
          isPaused: false,
          reconnectAttempt: 0,
          error: null,
          nextRetryAt: null,
        ),
      );

      // 再接続成功コールバック
      onReconnectSuccess?.call();

      completer.complete(true);
      return true;
    } catch (e) {
      // 再接続失敗、次の試行をスケジュール
      _updateState(
        (s) => s.copyWith(
          connectionState: SshConnectionState.error,
          error: _l10n.sshReconnectFailed(e.toString()),
        ),
      );

      // 自動で次の試行をスケジュール（無制限リトライの場合）
      if (_shouldScheduleNextAttempt()) {
        // 非同期で次の再接続をスケジュール
        Future.microtask(() => _requestReconnect());
      }

      completer.complete(false);
      return false;
    } finally {
      _reconnectInFlight = false;
      _reconnectInFlightResult = null;
    }
  }

  /// 接続がアクティブかチェック
  bool checkConnection() {
    return _client != null && _client!.isConnected;
  }

  /// 切断（接続状態監視のキャンセル以降）
  Future<void> disconnect() async {
    // 接続状態監視をキャンセル
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    // Foreground Serviceを停止
    await _stopForeground();

    await _client?.disconnect();
    _client = null;
    _updateState(
      (s) => s.copyWith(
        connectionState: SshConnectionState.disconnected,
        error: null,
        sessionTitle: null,
        isReconnecting: false,
        isPaused: false,
        reconnectAttempt: 0,
        nextRetryAt: null,
      ),
    );
  }

  /// データを送信
  void write(String data) {
    _client?.write(data);
  }

  /// ターミナルサイズを変更
  void resize(int cols, int rows) {
    _client?.resize(cols, rows);
  }

  /// onDispose 用クリーンアップ（接続状態監視・クライアント）
  void dispose() {
    _connectionStateSubscription?.cancel();
    _client?.dispose();
  }
}
