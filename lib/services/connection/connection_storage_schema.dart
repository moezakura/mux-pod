/// 接続設定の永続化スキーマのバージョン定数。
///
/// 新旧 JSON を共存させるため（G6 合意#4: schema 番号で新旧共存）、
/// provider 層（`Connection`）と service 層（`ConnectionMigration`）の
/// 両方から参照する。service 層から provider 層を import すると循環依存に
/// なるため、依存の起点とならない独立ファイルに置く。
abstract final class ConnectionStorageSchema {
  /// 現在の永続化スキーマバージョン（このアプリが書き込む新形式）。
  ///
  /// 新形式では downgrade 互換のため、tmux backend に限り旧 `tmuxPath`
  /// フィールドも併記する。`storageSchemaVersion == current` のレコードは
  /// migration 不要として扱う。
  static const int current = 2;

  /// 旧 JSON（schemaVersion キーなし・tmuxPath 形式）のバージョン。
  static const int legacy = 1;
}
