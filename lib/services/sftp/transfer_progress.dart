/// 転送の進捗を表す共通データ型。
///
/// #40（ダウンロード）と #41（アップロード）が両方で使う転送進捗の正と
/// するための共通部品。速度の算出は [TransferSpeedEma]、キャンセルは
/// [TransferCancelToken] / [TransferCancelledException] で行う。
library;

/// 単一転送の進捗データ。
///
/// - [doneBytes]: 転送済みバイト数（累積）
/// - [totalBytes]: 総バイト数。0 以下は「サイズ未知」（UI 側は速度のみ表示）
/// - [bytesPerSec]: 直近の転送速度（B/s）。[TransferSpeedEma] が更新する
class TransferProgress {
  final int doneBytes;
  final int totalBytes;
  final double bytesPerSec;

  const TransferProgress({
    required this.doneBytes,
    required this.totalBytes,
    this.bytesPerSec = 0,
  });

  /// 0.0〜1.0 の進捗率。totalBytes が 0 以下（サイズ未知）なら null。
  ///
  /// `LinearProgressIndicator(value:)` が 0-1 を要求するため、ここを正とする
  /// （C-12）。[percent] は 0-100 の別 getter として提供する。
  double? get fraction => totalBytes > 0 ? doneBytes / totalBytes : null;

  /// 0〜100 の進捗率。サイズ未知なら null。
  int? get percent => fraction == null ? null : (fraction! * 100).round();

  TransferProgress copyWith({
    int? doneBytes,
    int? totalBytes,
    double? bytesPerSec,
  }) {
    return TransferProgress(
      doneBytes: doneBytes ?? this.doneBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSec: bytesPerSec ?? this.bytesPerSec,
    );
  }

  /// 進捗管理の基本として、累積バイト数から生成する。
  ///
  /// [TransferSpeedEma] の速度計算は、このビルダ側の doneBytes を直渡しして
  /// 行う（[fromFraction] は使わない）。
  factory TransferProgress.fromBytes(
    int doneBytes, {
    required int totalBytes,
    double bytesPerSec = 0,
  }) {
    return TransferProgress(
      doneBytes: doneBytes,
      totalBytes: totalBytes,
      bytesPerSec: bytesPerSec,
    );
  }

  /// UI 表示専用: 進捗率（0.0〜1.0）から TransferProgress を生成する。
  ///
  /// totalBytes 不明の fraction から真の累積 doneBytes は復元できないため、
  /// **EMA 速度計算には使わないこと**（Ch-4）。表示目的では 1000 分率の整数比
  /// として [fraction] が概ね再現されるようにする。
  factory TransferProgress.fromFraction(double fraction, {double bytesPerSec = 0}) {
    final f = fraction.clamp(0.0, 1.0);
    return TransferProgress(
      doneBytes: (f * 1000).round(),
      totalBytes: 1000,
      bytesPerSec: bytesPerSec,
    );
  }

  @override
  String toString() =>
      'TransferProgress($doneBytes/$totalBytes bytes, ${bytesPerSec.toStringAsFixed(1)} B/s)';
}

/// 転送速度の指数移動平均（EMA）。
///
/// α で過去の影響を調整（既定 α=0.3）。このクラスは「サンプル毎の純粋な計算」
/// のみを行い、**100ms 間引きは転送タスク層（#40/#41 側）の責務**とする（R12）。
class TransferSpeedEma {
  /// 平滑化係数（0 < alpha < 1）。大きいほど直近を重視。
  final double alpha;

  /// テスト用の clock 注入。null なら [DateTime.now] を使う。
  final DateTime Function()? clock;

  int? _lastDoneBytes;
  DateTime? _lastTime;
  double _speed = 0;

  TransferSpeedEma({this.alpha = 0.3, this.clock});

  DateTime _now() => clock?.call() ?? DateTime.now();

  /// 累積バイト数 [doneBytes] で速度を更新し、現在の速度（B/s）を返す。
  ///
  /// 契約（C-4）:
  /// - 引数は**累積 doneBytes**（内部で前回値との差分を計算する）
  /// - **100ms 間引き後のサンプル**で呼ぶ（間引き責務は転送タスク層）
  /// - 初回は速度が無いため **0** を返す
  double update(int doneBytes, {DateTime? now}) {
    final t = now ?? _now();
    if (_lastDoneBytes == null || _lastTime == null) {
      _lastDoneBytes = doneBytes;
      _lastTime = t;
      _speed = 0;
      return _speed;
    }
    final dtSeconds =
        t.difference(_lastTime!).inMilliseconds / 1000.0;
    final deltaBytes = doneBytes - _lastDoneBytes!;
    _lastDoneBytes = doneBytes;
    _lastTime = t;
    if (dtSeconds <= 0 || deltaBytes < 0) {
      // 経過ゼロ・巻き戻りは速度 0 とみなす。
      _speed = 0;
      return _speed;
    }
    final instant = deltaBytes / dtSeconds;
    // 初回実サンプル（_speed==0）は instant をそのまま採用し、以降は EMA で平滑化。
    _speed = _speed == 0
        ? instant
        : (alpha * instant) + (1 - alpha) * _speed;
    return _speed;
  }

  /// 速度算出状態をリセットする（次回 update は初回扱いになり 0 を返す）。
  void reset() {
    _lastDoneBytes = null;
    _lastTime = null;
    _speed = 0;
  }
}

/// 転送がキャンセルされたことを表す共通例外。
class TransferCancelledException implements Exception {
  final String message;

  const TransferCancelledException([this.message = 'Transfer cancelled']);

  @override
  String toString() => 'TransferCancelledException: $message';
}

/// キャンセル要求を表す共通トークン。
///
/// キャンセルの実行（部分ファイル削除等）は方向別（UL=`sftp.remove` /
/// DL=ローカル削除）で各 Issue が行う。ここでは要求の伝達のみを共通化する（L-4）。
class TransferCancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() => _isCancelled = true;
}
