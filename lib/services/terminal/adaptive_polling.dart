/// 適応型ポーリング間隔計算
///
/// コンテンツの変化がない連続ポーリング数に応じて、ポーリング間隔を
/// 動的に調整する。高頻度更新時は短く、アイドル時は長くする。
class AdaptivePollingInterval {
  /// 最小ポーリング間隔（ミリ秒）
  static const int minInterval = 50;

  /// 最大ポーリング間隔（ミリ秒）-- アイドル時
  static const int maxInterval = 2000;

  /// デフォルトポーリング間隔（ミリ秒）
  static const int defaultInterval = 100;

  /// 高頻度更新閾値（この回数以下の変更なしフレームで高頻度モード）
  static const int highFrequencyThreshold = 3;

  /// 低頻度更新閾値（この回数以上の変更なしフレームで低頻度モード）
  static const int lowFrequencyThreshold = 15;

  /// 現在のポーリング間隔を計算する。
  ///
  /// [unchangedFrames] 変更がない連続ポーリング数。
  static int calculateInterval(int unchangedFrames) {
    // 高頻度更新中（htop等）
    if (unchangedFrames <= highFrequencyThreshold) {
      return minInterval;
    }

    // 低頻度更新中（アイドル状態）
    if (unchangedFrames >= lowFrequencyThreshold) {
      return maxInterval;
    }

    // 中間状態：線形補間
    final ratio = (unchangedFrames - highFrequencyThreshold) /
        (lowFrequencyThreshold - highFrequencyThreshold);
    return (minInterval + (maxInterval - minInterval) * ratio).round();
  }
}
