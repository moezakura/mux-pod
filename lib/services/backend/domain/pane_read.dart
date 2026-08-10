/// ペイン読み取りの共通 domain（read intent ベース）。
///
/// 従来の `PaneContentReader.readPane` は `historyLines` の符号と大きさ
/// （`-120` = ライブ / `-100000` = 深い履歴）で利用目的を推測していた。
/// これは tmux の `capture-pane -S` 由来の負数規約を公開しており、herdr の
/// `pane read --lines N`（正数のみ）と非対称だった。読み取りの「目的」と
/// 「行数」を [PaneReadPurpose] と [PaneReadRequest] に分離して明示する
/// （バグ4 根本対応・魔法数 `-120/-100000/-32768` の意味判定を廃止）。
library;

/// ペイン読み取りの利用目的。
enum PaneReadPurpose {
  /// ライブポーリング（直近 tail 行のみ・描画のホットパス）。
  live,

  /// スクロールバック全体（深い履歴・スクロールモード / オーバースクロール）。
  scrollback,
}

/// ペイン読み取りの要求（backend 非依存）。
///
/// [maxLines] は「この行数まで取得する」上限。backend ごとの解釈は
/// reader 実装（`PaneHistoryPolicy` 経由）が担う:
/// - tmux: `capture-pane -S -maxLines`（サーバ側 history-limit でクランプ）
/// - herdr: `pane read --lines maxLines`（要求行数をそのまま上限にする）
class PaneReadRequest {
  /// 読み取り対象の pane ID。
  final String paneId;

  /// 読み取りの目的（ライブ / スクロールバック）。
  final PaneReadPurpose purpose;

  /// 取得する最大行数（正の値）。
  final int maxLines;

  const PaneReadRequest({
    required this.paneId,
    required this.purpose,
    required this.maxLines,
  });

  /// ライブポーリング要求を作る。
  ///
  /// [maxLines] はライブ窓の行数（既定 [PaneHistoryPolicy.liveTailLines]）。
  const PaneReadRequest.live({
    required this.paneId,
    this.purpose = PaneReadPurpose.live,
    this.maxLines = 120,
  });

  /// スクロールバック全体の要求を作る。
  ///
  /// [maxLines] はスクロールバック上限（既定は policy が解決する）。
  const PaneReadRequest.scrollback({
    required this.paneId,
    this.purpose = PaneReadPurpose.scrollback,
    this.maxLines = 100000,
  });

  @override
  String toString() => 'PaneReadRequest($paneId, $purpose, maxLines=$maxLines)';
}
