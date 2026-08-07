/// マルチプレクサ backend の共通種別。
///
/// 表示側で read-only 分岐などに使う（herdr は読み取り専用接続のみ公開）。
enum MultiplexerBackendKind {
  /// tmux backend
  tmux,

  /// herdr backend（read-only）
  herdr,
}
