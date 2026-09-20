// 自動再接続待機中のカウントダウン表示ロジック。
//
// Flutter ウィジェットに依存しない純粋なロジックとして切り出しており、
// ValueNotifier/Timer のみを使用するため unit test 可能（terminal_zoom.dart と
// 同じ方針）。ssh_provider の状態型にも依存せず、同期に必要な値のみを
// 引数で受け取る。

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 次回リトライ時刻までの残り秒（切り上げ）。
///
/// 待機開始直後は `now + 5s` でも差分が 4.99s になるため、切り捨てる
/// （inSeconds）と「4s」表示から始まってしまう。カウントダウンとしては
/// 「5s → 4s → …」と減っていくべきため切り上げで丸める。
int remainingSecondsUntil(DateTime until, {DateTime? now}) {
  final ms = (now ?? DateTime.now()).difference(until).inMilliseconds.abs();
  if (ms <= 0) return 0;
  return (ms / 1000).ceil();
}

/// 自動再接続待機中のカウントダウン（残り秒）を管理するロジック。
///
/// 待機中は state 遷移がないため、1 秒周期の Timer で Notifier のみ更新し、
/// インジケーター部品だけを再構築する（親 build() は走らない）。待機終了・
/// 再接続完了・停止時は null に戻す（表示が接続処理中の Reconnecting に戻る）。
class ReconnectCountdown {
  final ValueNotifier<int?> _notifier = ValueNotifier<int?>(null);
  Timer? _timer;
  bool _disposed = false;

  /// 残り秒（null = 非表示）。
  ValueListenable<int?> get remaining => _notifier;

  /// 再接続待機中のカウントダウンを state 遷移と同期する。
  ///
  /// 自動再接続はバックオフ待機（[nextRetryAt] が未来）と実際の接続処理
  /// （待機終了後）に分かれる。待機中は残り秒を 1 秒周期で Notifier へ流す。
  void sync({
    required bool isReconnecting,
    required bool isWaitingForNetwork,
    DateTime? nextRetryAt,
  }) {
    if (_disposed) return;
    final waitingForRetry =
        isReconnecting &&
        !isWaitingForNetwork &&
        nextRetryAt != null &&
        nextRetryAt.isAfter(DateTime.now());

    if (!waitingForRetry) {
      _stopTimer();
      return;
    }

    // 待機開始時の残り秒を初期値にしたデクリメントカウンタ方式。tick ごとに
    // DateTime.now() を読み直すとタイマー発火と実壁時計のズレで表示が飛んだり
    // 更新されなくなったりするため、Timer の 1 秒周期に同期して減らす。待機の
    // 実スケジュールは ssh_provider 側のタイマーが管理するため、表示用の
    // カウンタとして十分。state 変化（次の nextRetryAt 設定等）で再同期される。
    _timer?.cancel();
    _notifier.value = remainingSecondsUntil(nextRetryAt);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      final remaining = _notifier.value;
      if (remaining == null || remaining <= 1) {
        // 待機終了 → 接続処理中の表示へ戻す
        _stopTimer();
        return;
      }
      _notifier.value = remaining - 1;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _notifier.value = null;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _notifier.dispose();
  }
}
