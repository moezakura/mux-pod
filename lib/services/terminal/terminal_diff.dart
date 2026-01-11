/// ターミナル差分計算サービス
///
/// 高頻度更新時のパフォーマンス最適化のため、
/// 行単位で差分を検出し、変更された部分だけを特定する。
class TerminalDiff {
  /// 前回のコンテンツ（行単位）
  List<String> _previousLines = [];

  /// 前回の行ごとのハッシュ値
  List<int> _previousHashes = [];

  /// 変更がない連続フレーム数
  int _unchangedFrames = 0;

  /// 差分計算結果
  DiffResult calculateDiff(String newContent) {
    final newLines = newContent.split('\n');
    final newHashes = newLines.map((line) => line.hashCode).toList();

    // 初回または行数が大きく異なる場合は全更新
    if (_previousLines.isEmpty ||
        (newLines.length - _previousLines.length).abs() > 10) {
      _previousLines = newLines;
      _previousHashes = newHashes;
      _unchangedFrames = 0;
      return DiffResult(
        hasChanges: true,
        isFullUpdate: true,
        changedLineIndices: List.generate(newLines.length, (i) => i),
        unchangedFrames: 0,
      );
    }

    // 行単位で差分を検出
    final changedIndices = <int>[];
    final maxLen =
        newLines.length > _previousLines.length ? newLines.length : _previousLines.length;

    for (int i = 0; i < maxLen; i++) {
      if (i >= _previousLines.length) {
        // 新しく追加された行
        changedIndices.add(i);
      } else if (i >= newLines.length) {
        // 削除された行（通常はない）
        changedIndices.add(i);
      } else if (_previousHashes[i] != newHashes[i]) {
        // 変更された行
        changedIndices.add(i);
      }
    }

    // 変更なしの場合はフレームカウントを増加
    if (changedIndices.isEmpty) {
      _unchangedFrames++;
    } else {
      _unchangedFrames = 0;
    }

    // 前回の状態を更新
    _previousLines = newLines;
    _previousHashes = newHashes;

    return DiffResult(
      hasChanges: changedIndices.isNotEmpty,
      isFullUpdate: false,
      changedLineIndices: changedIndices,
      unchangedFrames: _unchangedFrames,
    );
  }

  /// 差分をリセット
  void reset() {
    _previousLines = [];
    _previousHashes = [];
    _unchangedFrames = 0;
  }

  /// 変更がない連続フレーム数を取得
  int get unchangedFrames => _unchangedFrames;
}

/// 差分計算結果
class DiffResult {
  /// 変更があるかどうか
  final bool hasChanges;

  /// 全更新が必要かどうか
  final bool isFullUpdate;

  /// 変更された行のインデックス
  final List<int> changedLineIndices;

  /// 変更がない連続フレーム数
  final int unchangedFrames;

  const DiffResult({
    required this.hasChanges,
    required this.isFullUpdate,
    required this.changedLineIndices,
    required this.unchangedFrames,
  });

  /// 変更された行の割合（0.0〜1.0）
  double get changeRatio {
    if (changedLineIndices.isEmpty) return 0.0;
    // 推定の全行数
    final totalLines = changedLineIndices.isEmpty
        ? 1
        : changedLineIndices.last + 1;
    return changedLineIndices.length / totalLines;
  }
}

/// 適応型ポーリング間隔計算
///
/// コンテンツの変化頻度に応じてポーリング間隔を動的に調整する。
class AdaptivePollingInterval {
  /// 最小ポーリング間隔（ミリ秒）
  static const int minInterval = 50;

  /// 最大ポーリング間隔（ミリ秒）
  static const int maxInterval = 500;

  /// デフォルトポーリング間隔（ミリ秒）
  static const int defaultInterval = 100;

  /// 高頻度更新閾値（この回数以下の変更なしフレームで高頻度モード）
  static const int highFrequencyThreshold = 5;

  /// 低頻度更新閾値（この回数以上の変更なしフレームで低頻度モード）
  static const int lowFrequencyThreshold = 30;

  /// 現在のポーリング間隔を計算
  ///
  /// [unchangedFrames] 変更がない連続フレーム数
  /// [changeRatio] 直近の変更率
  static int calculateInterval(int unchangedFrames, double changeRatio) {
    // 高頻度更新中（htop等）
    if (unchangedFrames <= highFrequencyThreshold || changeRatio > 0.3) {
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
