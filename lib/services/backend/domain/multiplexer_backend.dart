/// マルチプレクサ backend の共通種別。
///
/// 表示側で操作能力（`_can`）分岐などに使う。herdr も tmux と同等に
/// 全 mutation 操作が可能（G6 合意#3 改訂・公開済み）。`bool?` による
/// 3 状態（null/false/true）の混乱を避けるため非 nullable 3 値化している
/// （A9 / L0-b-14）。
enum MultiplexerBackendKind {
  /// 接続前の初期値（backend 未確定）。
  ///
  /// 画面ローカルの初期値としてのみ使う。永続化・JSON 化はしない
  /// （A7: 外部契約を変えない。既存の接続設定 JSON / ActiveSession の
  /// シリアライズ形式には影響しない）。
  unknown,

  /// tmux backend
  tmux,

  /// herdr backend（全 mutation 操作対応・公開済み）
  herdr,
}
