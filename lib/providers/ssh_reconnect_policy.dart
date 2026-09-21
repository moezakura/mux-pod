import 'dart:async';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_lookup.dart';
import '../../services/network/network_monitor.dart';
import 'ssh_state.dart';

/// 再接続ポリシー（協調オブジェクト）
///
/// `ssh_provider.dart`（[SshNotifier]）からのみ生成・保有される。
/// 「いつ・どれだけ待って試すか」を担う: 指数バックオフ（1s / 1.5x /
/// 最大60s・無制限リトライ）、Timer スケジュール、single-flight
/// （[SshConnectionOrchestrator.reconnectConnection] 側）、ネットワーク
/// pause/resume（オフラインで一時停止・復帰で即時再開）、reconnectNow /
/// reset。実際の再接続実行は注入された `reconnectAction` に依頼する。
class SshReconnectPolicy {
  // 無制限リトライモード（0 = 無制限）
  static const int _maxReconnectAttempts = 0; // 無制限

  // 指数バックオフ（最大60秒）
  static const int _baseDelayMs = 1000;
  static const int _maxDelayMs = 60000;
  static const double _backoffMultiplier = 1.5;

  final Future<bool> Function() _reconnectAction;
  final bool Function() _hasLastConnection;
  final SshState Function() _getState;
  final void Function(SshState Function(SshState)) _updateState;

  // ネットワーク状態監視用
  StreamSubscription<NetworkStatus>? _networkStatusSubscription;

  // 再接続タイマー
  Timer? _reconnectTimer;

  SshReconnectPolicy({
    required Future<bool> Function() reconnectAction,
    required bool Function() hasLastConnection,
    required SshState Function() getState,
    required void Function(SshState Function(SshState)) updateState,
  }) : _reconnectAction = reconnectAction,
       _hasLastConnection = hasLastConnection,
       _getState = getState,
       _updateState = updateState;

  /// 設定言語から解決したローカライズ文字列。
  AppLocalizations get _l10n => lookupL10n();

  /// 再接続をスケジュールしてよいか（無制限リトライまたは上限未達）
  bool get shouldScheduleNextAttempt =>
      _maxReconnectAttempts == 0 ||
      _getState().reconnectAttempt < _maxReconnectAttempts;

  /// ネットワーク状態の監視を開始
  void startNetworkMonitoring(Stream<NetworkStatus> stream) {
    _networkStatusSubscription = stream.listen(_onNetworkStatusChanged);
  }

  /// ネットワーク状態変化のハンドラ
  void _onNetworkStatusChanged(NetworkStatus status) {
    final isOnline = status == NetworkStatus.online;

    _updateState((s) => s.copyWith(isNetworkAvailable: isOnline));

    if (isOnline) {
      // オフラインからオンラインに復帰した場合
      if (_getState().isPaused && _getState().isReconnecting) {
        // 即座に再接続を試みる（遅延なし）
        _updateState((s) => s.copyWith(isPaused: false, reconnectAttempt: 0));
        _reconnectTimer?.cancel();
        // 直接reconnectConnectionを呼んで即座に再接続
        _reconnectAction();
      }
    } else {
      // オフラインになった場合
      if (_getState().isReconnecting) {
        // 再接続を一時停止
        _updateState((s) => s.copyWith(isPaused: true));
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

  /// 再接続を試みる
  ///
  /// 自動再接続用。指数バックオフで無制限に試行する。
  /// ネットワークがオフラインの場合は一時停止し、復帰時に自動再開。
  Future<bool> reconnect() async {
    if (!_hasLastConnection()) {
      return false;
    }

    // ネットワークがオフラインの場合は一時停止
    if (!_getState().isNetworkAvailable) {
      _updateState(
        (s) => s.copyWith(
          isReconnecting: true,
          isPaused: true,
          error: _l10n.termWaitingForNetwork,
        ),
      );
      return false;
    }

    final attempt = _getState().reconnectAttempt;

    // 無制限リトライでない場合のみ上限チェック
    if (_maxReconnectAttempts > 0 && attempt >= _maxReconnectAttempts) {
      _updateState(
        (s) => s.copyWith(
          isReconnecting: false,
          error: _l10n.sshMaxReconnectAttemptsReached,
        ),
      );
      return false;
    }

    final delayMs = _calculateDelay(attempt);
    final nextRetry = DateTime.now().add(Duration(milliseconds: delayMs));

    _updateState(
      (s) => s.copyWith(
        isReconnecting: true,
        isPaused: false,
        reconnectAttempt: attempt + 1,
        reconnectDelayMs: delayMs,
        nextRetryAt: nextRetry,
      ),
    );

    // 遅延後に再接続
    final completer = Completer<bool>();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      final result = await _reconnectAction();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    });

    return completer.future;
  }

  /// 今すぐ再接続を試みる（ユーザー操作用）
  Future<bool> reconnectNow() async {
    _reconnectTimer?.cancel();
    _updateState((s) => s.copyWith(reconnectAttempt: 0, isPaused: false));
    return _reconnectAction();
  }

  /// 再接続状態をリセット
  void reset() {
    _reconnectTimer?.cancel();
    _updateState(
      (s) => s.copyWith(
        isReconnecting: false,
        isPaused: false,
        reconnectAttempt: 0,
        reconnectDelayMs: null,
        nextRetryAt: null,
      ),
    );
  }

  /// 再接続タイマーのみをキャンセル（disconnect 用）
  void cancelTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// onDispose 用クリーンアップ（タイマー・ネットワーク監視）
  void stop() {
    _reconnectTimer?.cancel();
    _networkStatusSubscription?.cancel();
  }
}
