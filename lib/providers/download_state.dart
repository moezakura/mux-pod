/// ダウンロード転送の不変状態モデル（enum + 値オブジェクト + 派生集計）を定義する。
library;

/// ダウンロード転送のフェーズ。
enum DownloadPhase {
  /// 待機中（何もしていない状態）。
  idle,

  /// 保存先選択・事前スキャン中。
  selecting,

  /// 順次ダウンロードキュー実行中。
  downloading,

  /// 単一ダウンロードの Save-As エクスポート待ち（ユーザーの保存先選択中）。
  exporting,

  /// 同名衝突の上書き確認待ち（事前スキャンで検出）。
  awaitingOverwrite,

  /// ユーザーキャンセルで中断・確定済み。
  cancelled,

  /// 全アイテムの処理完了（一部失敗・スキップ含む）。
  completed,

  /// SSH 切断等でエラー確定。
  error,
}

/// ダウンロード 1 アイテムの状態。
class DownloadItemState {
  final String remotePath;

  /// サニタイズ済みの表示名（basename）。
  final String name;

  /// 総バイト数。0 以下はサイズ未知（基盤契約・未知は不確定表示）。
  final int totalBytes;

  /// 転送済みバイト数（累積）。
  final int bytesReceived;

  /// 端末上の保存先を表す表示用パス。
  ///
  /// - 単一（[DownloadNotifier.startSingleTmpDownload]）: 当初は tmp の実パス。Save-As エクスポート完了後に
  ///   戻り値パス（例: `Download/sample.txt`）へ更新される。
  /// - 一括（[DownloadNotifier.startDownloads]）: サニタイズ済みの name のみ（実パスは
  ///   [DownloadDestination] が管理）。
  final String localPath;

  /// 転送エラー（書込 I/O エラー含む）で失敗したか。
  final bool isError;

  /// 上書き確認で「スキップ」決定されたか（キューから除外）。
  final bool isSkipped;

  /// 転送が正常に完了したか（集計 completedCount の正確化のための拡張）。
  final bool isCompleted;

  /// 失敗理由（アイテム単位のエラー詳細）。
  final String? errorMessage;

  /// `destination.open(name, overwrite:)` に渡す上書きフラグ。
  ///
  /// 既定は `false`（新規作成・保存先実装による採番）。上書き決定・リネーム採番時に
  /// `true` になる（SAF 側の自動採番を抑止し、決定した名前を確実に使う）。
  final bool overwrite;

  const DownloadItemState({
    required this.remotePath,
    required this.name,
    required this.localPath,
    this.totalBytes = 0,
    this.bytesReceived = 0,
    this.isError = false,
    this.isSkipped = false,
    this.isCompleted = false,
    this.errorMessage,
    this.overwrite = false,
  });

  DownloadItemState copyWith({
    String? name,
    String? localPath,
    int? totalBytes,
    int? bytesReceived,
    bool? isError,
    bool? isSkipped,
    bool? isCompleted,
    String? errorMessage,
    bool? overwrite,
  }) {
    return DownloadItemState(
      remotePath: remotePath,
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      isError: isError ?? this.isError,
      isSkipped: isSkipped ?? this.isSkipped,
      isCompleted: isCompleted ?? this.isCompleted,
      errorMessage: errorMessage ?? this.errorMessage,
      overwrite: overwrite ?? this.overwrite,
    );
  }
}

/// ダウンロード転送全体の状態。
class DownloadState {
  final DownloadPhase phase;
  final List<DownloadItemState> items;

  /// バッチ全体（または切断・開始失敗）のエラーメッセージ。
  final String? errorMessage;

  /// 同名衝突で上書き確認待ちになったアイテム（awaitingOverwrite 中のみ非空）。
  final List<DownloadItemState> collidingItems;

  /// 直近の転送速度表示（`formatTransferSpeed` 済み・フィールド実装）。
  /// EMA 状態は DownloadNotifier が保持するため純 getter では導出できない。
  final String speedLabel;

  const DownloadState({
    this.phase = DownloadPhase.idle,
    this.items = const [],
    this.errorMessage,
    this.collidingItems = const [],
    this.speedLabel = '',
  });

  /// 転送済みバイト数（全アイテム累積）。
  int get receivedBytes => items.fold(0, (s, i) => s + i.bytesReceived);

  /// 総バイト数（未知=0 は除外・表示用）。
  int get totalBytes =>
      items.fold(0, (s, i) => s + (i.totalBytes > 0 ? i.totalBytes : 0));

  /// 正常完了アイテム数。
  int get completedCount =>
      items.where((i) => i.isCompleted && !i.isError).length;

  /// 失敗アイテム数。
  int get failedCount => items.where((i) => i.isError).length;

  /// スキップされたアイテム数。
  int get skippedCount => items.where((i) => i.isSkipped).length;

  /// 全体進捗率（0.0〜1.0）。**既知サイズ分の累積/総和**で部分進捗を表示し、
  /// 既知サイズが無い場合は null（不確定表示・基盤契約 totalBytes<=0=サイズ未知）。
  double? get fraction {
    var knownTotal = 0;
    var knownReceived = 0;
    for (final i in items) {
      if (i.totalBytes <= 0) continue;
      knownTotal += i.totalBytes;
      knownReceived += i.bytesReceived > i.totalBytes
          ? i.totalBytes
          : i.bytesReceived;
    }
    if (knownTotal <= 0) return null;
    return knownReceived / knownTotal;
  }

  DownloadState copyWith({
    DownloadPhase? phase,
    List<DownloadItemState>? items,
    String? errorMessage,
    bool clearError = false,
    List<DownloadItemState>? collidingItems,
    String? speedLabel,
  }) {
    return DownloadState(
      phase: phase ?? this.phase,
      items: items ?? this.items,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      collidingItems: collidingItems ?? this.collidingItems,
      speedLabel: speedLabel ?? this.speedLabel,
    );
  }
}
