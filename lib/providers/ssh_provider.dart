import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/background/foreground_task_service.dart';
import '../services/network/network_monitor.dart';
import '../services/ssh/ssh_client.dart';
import 'connection_provider.dart';

/// SSH接続状態
class SshState {
  final SshConnectionState connectionState;
  final String? error;
  final String? sessionTitle;
  final bool isReconnecting;
  final int reconnectAttempt;
  final int? reconnectDelayMs;

  /// ネットワークが利用可能か
  final bool isNetworkAvailable;

  /// 次回リトライ予定時刻
  final DateTime? nextRetryAt;

  /// 再接続が一時停止中か（ネットワーク不可時）
  final bool isPaused;

  const SshState({
    this.connectionState = SshConnectionState.disconnected,
    this.error,
    this.sessionTitle,
    this.isReconnecting = false,
    this.reconnectAttempt = 0,
    this.reconnectDelayMs,
    this.isNetworkAvailable = true,
    this.nextRetryAt,
    this.isPaused = false,
  });

  SshState copyWith({
    SshConnectionState? connectionState,
    String? error,
    String? sessionTitle,
    bool? isReconnecting,
    int? reconnectAttempt,
    int? reconnectDelayMs,
    bool? isNetworkAvailable,
    DateTime? nextRetryAt,
    bool? isPaused,
  }) {
    return SshState(
      connectionState: connectionState ?? this.connectionState,
      error: error,
      sessionTitle: sessionTitle ?? this.sessionTitle,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      reconnectDelayMs: reconnectDelayMs,
      isNetworkAvailable: isNetworkAvailable ?? this.isNetworkAvailable,
      nextRetryAt: nextRetryAt,
      isPaused: isPaused ?? this.isPaused,
    );
  }

  bool get isConnected => connectionState == SshConnectionState.connected;
  bool get isConnecting => connectionState == SshConnectionState.connecting;
  bool get isDisconnected => connectionState == SshConnectionState.disconnected;
  bool get hasError => connectionState == SshConnectionState.error;

  /// オフラインで待機中か
  bool get isWaitingForNetwork => isPaused && !isNetworkAvailable;
}

/// SSH接続を管理するNotifier
class SshNotifier extends Notifier<SshState> {
  SshClient? _client;
  final SshForegroundTaskService _foregroundService =
      SshForegroundTaskService();

  // 再接続用のキャッシュ
  Connection? _lastConnection;
  SshConnectOptions? _lastOptions;

  // 無制限リトライモード（0 = 無制限）
  static const int _maxReconnectAttempts = 0; // 無制限

  // 指数バックオフ（最大60秒）
  static const int _baseDelayMs = 1000;
  static const int _maxDelayMs = 60000;
  static const double _backoffMultiplier = 1.5;

  // 接続状態監視用
  StreamSubscription<SshConnectionState>? _connectionStateSubscription;

  // ネットワーク状態監視用
  StreamSubscription<NetworkStatus>? _networkStatusSubscription;

  // 再接続タイマー
  Timer? _reconnectTimer;

  // 再接続の single-flight（Codex B3）: timer callback と reconnectNow の同時
  // 実行を防ぎ、進行中の結果を共有する。
  bool _reconnectInFlight = false;
  Completer<bool>? _reconnectInFlightResult;

  // 切断検知コールバック（外部から設定可能）
  void Function()? onDisconnectDetected;

  // 再接続成功コールバック（外部から設定可能）
  void Function()? onReconnectSuccess;

  @override
  SshState build() {
    // ネットワーク状態を監視
    _startNetworkMonitoring();

    // クリーンアップを登録
    ref.onDispose(() {
      _reconnectTimer?.cancel();
      _connectionStateSubscription?.cancel();
      _networkStatusSubscription?.cancel();
      _client?.dispose();
      _foregroundService.stopService();
    });
    return const SshState();
  }

  /// ネットワーク状態の監視を開始
  void _startNetworkMonitoring() {
    final monitor = ref.read(networkMonitorProvider);
    _networkStatusSubscription = monitor.statusStream.listen(
      _onNetworkStatusChanged,
    );
  }

  /// ネットワーク状態変化のハンドラ
  void _onNetworkStatusChanged(NetworkStatus status) {
    final isOnline = status == NetworkStatus.online;

    state = state.copyWith(isNetworkAvailable: isOnline);

    if (isOnline) {
      // オフラインからオンラインに復帰した場合
      if (state.isPaused && state.isReconnecting) {
        // 即座に再接続を試みる（遅延なし）
        state = state.copyWith(isPaused: false, reconnectAttempt: 0);
        _reconnectTimer?.cancel();
        // 直接_doReconnectを呼んで即座に再接続
        _doReconnect();
      }
    } else {
      // オフラインになった場合
      if (state.isReconnecting) {
        // 再接続を一時停止
        state = state.copyWith(isPaused: true);
        _reconnectTimer?.cancel();
      }
    }
  }

  /// 再接続遅延を計算（指数バックオフ）
  int _calculateDelay(int attempt) {
    final delay = (_baseDelayMs * _pow(_backoffMultiplier, attempt)).round();
    return delay.clamp(_baseDelayMs, _maxDelayMs);
  }

  /// 累乗計算
  double _pow(double base, int exponent) {
    double result = 1.0;
    for (int i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }

  /// SSHクライアントを取得
  SshClient? get client => _client;

  /// 最後の接続情報
  Connection? get lastConnection => _lastConnection;

  /// 最後の接続オプション
  SshConnectOptions? get lastOptions => _lastOptions;

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

      state = state.copyWith(connectionState: SshConnectionState.connected);

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

    state = state.copyWith(
      connectionState: SshConnectionState.connecting,
      error: null,
      isReconnecting: false,
      reconnectAttempt: 0,
    );

    try {
      _client = SshClient();

      // 接続状態のストリームを監視（切断検知の高速化）
      _connectionStateSubscription = _client!.connectionStateStream.listen(
        _onConnectionStateChanged,
      );

      await _client!.connect(
        host: connection.host,
        port: connection.port,
        username: connection.username,
        options: options,
      );

      // シェルは起動しない（exec専用）

      state = state.copyWith(
        connectionState: SshConnectionState.connected,
        isReconnecting: false,
        reconnectAttempt: 0,
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

  /// 接続状態変化のハンドラ
  ///
  /// Keep-aliveやソケットからの切断検知を即座に処理する。
  void _onConnectionStateChanged(SshConnectionState newState) {
    // 接続中の状態から切断/エラーになった場合
    if (state.isConnected &&
        (newState == SshConnectionState.error ||
            newState == SshConnectionState.disconnected)) {
      // 状態を更新
      state = state.copyWith(
        connectionState: newState,
        error: newState == SshConnectionState.error ? 'Connection lost' : null,
      );

      // 切断検知コールバックを呼び出し
      onDisconnectDetected?.call();

      // 自動再接続を試みる（すでに再接続中でなければ）
      if (!state.isReconnecting) {
        reconnect();
      }
    }
  }

  /// 再接続を試みる
  ///
  /// 自動再接続用。指数バックオフで無制限に試行する。
  /// ネットワークがオフラインの場合は一時停止し、復帰時に自動再開。
  Future<bool> reconnect() async {
    if (_lastConnection == null || _lastOptions == null) {
      return false;
    }

    // ネットワークがオフラインの場合は一時停止
    if (!state.isNetworkAvailable) {
      state = state.copyWith(
        isReconnecting: true,
        isPaused: true,
        error: 'Waiting for network...',
      );
      return false;
    }

    final attempt = state.reconnectAttempt;

    // 無制限リトライでない場合のみ上限チェック
    if (_maxReconnectAttempts > 0 && attempt >= _maxReconnectAttempts) {
      state = state.copyWith(
        isReconnecting: false,
        error: 'Max reconnect attempts reached',
      );
      return false;
    }

    final delayMs = _calculateDelay(attempt);
    final nextRetry = DateTime.now().add(Duration(milliseconds: delayMs));

    state = state.copyWith(
      isReconnecting: true,
      isPaused: false,
      reconnectAttempt: attempt + 1,
      reconnectDelayMs: delayMs,
      nextRetryAt: nextRetry,
    );

    // 遅延後に再接続
    final completer = Completer<bool>();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      final result = await _doReconnect();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    });

    return completer.future;
  }

  /// 実際の再接続処理
  ///
  /// **single-flight（Codex B3）**: timer callback（[reconnect]）と
  /// [reconnectNow] の両方から同時に呼ばれ得るため、実行中は重複実行せず
  /// 進行中の結果を共有する（古い完了結果による state 上書きも発生しない）。
  Future<bool> _doReconnect() async {
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
      if (!state.isNetworkAvailable) {
        state = state.copyWith(isPaused: true);
        completer.complete(false);
        return false;
      }

      // 既存の接続状態監視をキャンセル
      await _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;

      // 古いクライアントをクリーンアップ（await: 旧 managed PTY / TUI が
      // 閉じる前に新クライアントで起動しないことを保証・Codex B3）。
      await _client?.dispose();
      _client = SshClient();

      // 接続状態のストリームを監視（切断検知の高速化）
      _connectionStateSubscription = _client!.connectionStateStream.listen(
        _onConnectionStateChanged,
      );

      await _client!.connect(
        host: _lastConnection!.host,
        port: _lastConnection!.port,
        username: _lastConnection!.username,
        options: _lastOptions!,
      );

      state = state.copyWith(
        connectionState: SshConnectionState.connected,
        isReconnecting: false,
        isPaused: false,
        reconnectAttempt: 0,
        error: null,
        nextRetryAt: null,
      );

      // 再接続成功コールバック
      onReconnectSuccess?.call();

      completer.complete(true);
      return true;
    } catch (e) {
      // 再接続失敗、次の試行をスケジュール
      state = state.copyWith(
        connectionState: SshConnectionState.error,
        error: 'Reconnect failed: $e',
      );

      // 自動で次の試行をスケジュール（無制限リトライの場合）
      if (_maxReconnectAttempts == 0 ||
          state.reconnectAttempt < _maxReconnectAttempts) {
        // 非同期で次の再接続をスケジュール
        Future.microtask(() => reconnect());
      }

      completer.complete(false);
      return false;
    } finally {
      _reconnectInFlight = false;
      _reconnectInFlightResult = null;
    }
  }

  /// 今すぐ再接続を試みる（ユーザー操作用）
  Future<bool> reconnectNow() async {
    _reconnectTimer?.cancel();
    state = state.copyWith(reconnectAttempt: 0, isPaused: false);
    return _doReconnect();
  }

  /// 接続がアクティブかチェック
  bool checkConnection() {
    return _client != null && _client!.isConnected;
  }

  /// 再接続状態をリセット
  void resetReconnect() {
    _reconnectTimer?.cancel();
    state = state.copyWith(
      isReconnecting: false,
      isPaused: false,
      reconnectAttempt: 0,
      reconnectDelayMs: null,
      nextRetryAt: null,
    );
  }

  /// 切断
  Future<void> disconnect() async {
    // 再接続タイマーをキャンセル
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // 接続状態監視をキャンセル
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    // Foreground Serviceを停止
    await _foregroundService.stopService();

    await _client?.disconnect();
    _client = null;
    state = state.copyWith(
      connectionState: SshConnectionState.disconnected,
      error: null,
      sessionTitle: null,
      isReconnecting: false,
      isPaused: false,
      reconnectAttempt: 0,
      nextRetryAt: null,
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
