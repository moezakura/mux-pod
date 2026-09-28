import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../../l10n/app_localizations.dart';
import 'ssh_models.dart';

/// Keep-alive の単一所有者。
///
/// Timer スケジュール・間隔の動的調整・失敗閾値判定と、カウンタ3種
/// （failure / success / currentInterval）を保持する。probe 実行（HEAD
/// `SshClient._sendKeepAlive` の execute 部相当）と故障通知（onDead）は
/// facade が配線したクロージャ経由で行う。
class SshKeepAlive {
  SshKeepAlive({
    required this.timerFactory,
    required this.probe,
    required this.onDead,
    required this.isConnected,
    required this.client,
    required this.l10n,
  });

  /// Timer 生成の注入（テスト用）。
  final Timer Function(Duration duration, void Function() callback)
  timerFactory;

  /// keep-alive プローブの実行経路（HEAD `_sendKeepAlive` の execute 相当）。
  final Future<void> Function() probe;

  /// 失敗閾値到達時の状態遷移・イベント発火の統括（メッセージを受ける）。
  /// facade が state controller / event broker へ配線する。
  final void Function(String message) onDead;

  /// 接続中かどうか（現在値を返すクロージャ）。probe 継続判定。
  final bool Function() isConnected;

  /// SSH トランスポート本体（現在値を返すクロージャ）。
  final SSHClient? Function() client;

  /// ローカライズ文字列プロバイダ（現在値を返すクロージャ）。
  final AppLocalizations? Function() l10n;

  /// Keep-aliveタイマー
  Timer? _keepAliveTimer;
  bool _running = false;
  int _generation = 0;

  /// Keep-alive最小間隔（秒）
  static const int _minKeepAliveIntervalSeconds = 5;

  /// Keep-alive最大間隔（秒）
  static const int _maxKeepAliveIntervalSeconds = 30;

  /// Keep-alive timeout. 3s gives fast detection and holds on a LAN, but a
  /// cellular link, a VPN or a relayed hop misses a 3s round trip routinely,
  /// and the phone throttling timers in the background makes it likelier still.
  ///
  /// probe クロージャ（facade 配線）の CommandRequest タイムアウトで使用する。
  ///
  /// 🤝3: 接続個別・全体設定での上書きが可能（[keepAliveProbeTimeoutSeconds]）。
  /// この static const は「自動」時の基準値兼インスタンス値の既定値。
  static const int keepAliveTimeoutSeconds = 10;

  /// 自動式（`10 + hops × 5`）で hop 1 本あたりに加算する秒数。
  ///
  /// R7 由来: jump 経由の往復はホップ毎に遅延・ジッタが増えるため、
  /// 直接接続と同じ 10 秒では誤死判定（R7）が起きやすい。
  static const int keepAliveTimeoutPerHopSeconds = 5;

  /// Consecutive keep-alive failures before the connection is declared dead.
  /// A single lost probe is normal on a mobile link and must not tear down a
  /// live session; detection stays fast because the probe interval already
  /// shortens on failure.
  static const int _keepAliveFailureThreshold = 3;

  /// Consecutive keep-alive failures so far.
  int _keepAliveFailureCount = 0;

  /// 現在のKeep-alive間隔（動的に調整）
  int _currentKeepAliveIntervalSeconds = 10;

  /// Keep-alive連続成功回数
  int _keepAliveSuccessCount = 0;

  /// keepalive プローブのタイムアウト（秒・🤝3）。
  ///
  /// facade が接続時に解決した値を設定する（[resolveKeepAliveTimeoutSeconds]）。
  /// 未設定（既定）時は従来どおり [keepAliveTimeoutSeconds]（10 秒）で、
  /// 直接接続・未設定の既定挙動は不変。probe クロージャはこの現在値を参照する。
  int keepAliveProbeTimeoutSeconds = keepAliveTimeoutSeconds;

  /// keepalive プローブタイムアウト（秒）を解決する純関数（🤝3）。
  ///
  /// 優先順位: perConnection（接続個別） > global（全体設定） > 自動。
  /// 自動式: proxy あり = [keepAliveTimeoutSeconds] +
  /// hops × [keepAliveTimeoutPerHopSeconds] / なし = [keepAliveTimeoutSeconds]。
  ///
  /// 配置根拠（OQ-3）: 依存方向を models → keep_alive にしないため
  /// ssh_keep_alive 側に置き、[SshProxyOptions] 型のため ssh_models を
  /// import する（models は keep_alive を import しない）。
  static int resolveKeepAliveTimeoutSeconds({
    int? perConnection,
    int? global,
    SshProxyOptions? proxy,
  }) {
    if (perConnection != null) return perConnection;
    if (global != null) return global;
    return keepAliveTimeoutSeconds +
        (proxy?.hops.length ?? 0) * keepAliveTimeoutPerHopSeconds;
  }

  /// Keep-aliveを開始（HEAD `SshClient._startKeepAlive` 相当）。
  void start() {
    stop();
    _running = true;
    _currentKeepAliveIntervalSeconds = 10; // 初期値10秒
    _keepAliveSuccessCount = 0;
    _keepAliveFailureCount = 0;
    // inventory: SSH-LIFE-009
    _scheduleNextKeepAlive();
  }

  /// 次のKeep-aliveをスケジュール
  void _scheduleNextKeepAlive() {
    if (!_running) return;
    final generation = _generation;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = timerFactory(
      Duration(seconds: _currentKeepAliveIntervalSeconds),
      () async {
        // inventory: SSH-LIFE-012
        if (!_running || generation != _generation) return;
        await _sendKeepAlive(generation);
        if (_running && generation == _generation && isConnected()) {
          _scheduleNextKeepAlive();
        }
      },
    );
  }

  /// Keep-aliveを停止
  void stop() {
    _running = false;
    _generation++;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  // inventory: SSH-LIFE-011
  /// Keep-alive間隔を調整
  void _adjustKeepAliveInterval({required bool success}) {
    if (success) {
      _keepAliveSuccessCount++;
      // 3回連続成功で間隔を延長
      if (_keepAliveSuccessCount >= 3) {
        _currentKeepAliveIntervalSeconds =
            (_currentKeepAliveIntervalSeconds + 5).clamp(
              _minKeepAliveIntervalSeconds,
              _maxKeepAliveIntervalSeconds,
            );
        _keepAliveSuccessCount = 0;
      }
    } else {
      // 失敗時は最小間隔に戻す
      _currentKeepAliveIntervalSeconds = _minKeepAliveIntervalSeconds;
      _keepAliveSuccessCount = 0;
    }
  }

  /// Keep-aliveパケットを送信（HEAD `SshClient._sendKeepAlive` 相当）。
  Future<void> _sendKeepAlive(int generation) async {
    if (!isConnected() || client() == null) {
      return;
    }

    try {
      // 持続的シェル経由でkeep-alive（高速）
      // inventory: SSH-033
      // inventory: LEGACY-0159
      await probe();
      if (!_running || generation != _generation) return;
      _keepAliveFailureCount = 0;
      _adjustKeepAliveInterval(success: true);
    } catch (e) {
      if (!_running || generation != _generation) return;
      _adjustKeepAliveInterval(success: false);
      _keepAliveFailureCount++;
      if (_keepAliveFailureCount < _keepAliveFailureThreshold) {
        // Probe more often (the interval already shortened) and give the link
        // a chance to come back before tearing the session down.
        return;
      }
      final message =
          l10n()?.sshConnectionLostDetail(e.toString()) ??
          'Connection lost: $e';
      onDead(message);
    }
  }
}
