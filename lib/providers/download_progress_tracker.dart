import '../services/sftp/transfer_format.dart';
import '../services/sftp/transfer_progress.dart';

/// 進捗サンプル（間引き判定結果）。
class ProgressSample {
  const ProgressSample({
    required this.shouldPublish,
    required this.cumulative,
    required this.speedLabel,
  });

  /// state 反映すべきか（100ms 間引きを通過したか）。
  final bool shouldPublish;

  /// 全アイテムの累積受信バイト。
  final int cumulative;

  /// 直近の転送速度表示（`formatTransferSpeed` 済み）。非 publish 時は空文字。
  final String speedLabel;
}

/// 進捗の内部累積・100ms 間引き判定・EMA 速度・速度ラベルを計算する。
///
/// state 反映（DownloadState 更新）は行わず、間引きを通過したサンプルのみ
/// [ProgressSample.shouldPublish] を true にして呼び出し側（shell）に報告する。
/// アイテム境界では [reset] で速度区間をリセットする（全体速度の過小表示防止）。
class DownloadProgressTracker {
  DownloadProgressTracker({
    this.progressThrottle = const Duration(milliseconds: 100),
    DateTime Function()? clock,
  }) : _ema = TransferSpeedEma(clock: clock);

  /// state 反映（進捗）の最小間隔。100ms 間引きは転送タスク層の責務。
  final Duration progressThrottle;

  final TransferSpeedEma _ema;
  DateTime? _lastProgressAt;

  /// 累積受信バイト [doneBytes] を報告し、間引き判定・EMA 速度・速度ラベルを計算する。
  ///
  /// [totalBytes] はアイテムの総バイト（0 以下はサイズ未知）。間引きの判定と速度
  /// 計算には使わない（サイズ反映は保持側 [DownloadBatchSession.items] が行う）が、
  /// 進捗サンプルの完全性のため受け取る。初回サンプル（間引き判定が真）は速度 0。
  ProgressSample update(int doneBytes, int totalBytes, DateTime now) {
    final shouldPublish =
        _lastProgressAt == null ||
        now.difference(_lastProgressAt!) >= progressThrottle;
    if (!shouldPublish) {
      return ProgressSample(
        shouldPublish: false,
        cumulative: doneBytes,
        speedLabel: '',
      );
    }
    _lastProgressAt = now;
    final speed = _ema.update(doneBytes, now: now);
    final speedLabel = formatTransferSpeed(speed);
    return ProgressSample(
      shouldPublish: true,
      cumulative: doneBytes,
      speedLabel: speedLabel,
    );
  }

  /// 速度算出状態をリセットする（アイテム境界・バッチ開始時）。
  void reset() {
    _ema.reset();
    _lastProgressAt = null;
  }
}
