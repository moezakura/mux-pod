/// コマンド実行の汎用抽象。
///
/// backend（SSH / tmux / herdr）に依存しない中立レイヤー。
/// [BackendAdapter] がこの interface を実装する（Codex 根本設計レビュー・
/// バグ2 根本対応）。従来の `exec` / `execPersistent` / `execWithExitCode` /
/// `execPersistentWithExitCode` の直積を [CommandRequest] に統合する。
library;

import 'command_request.dart';
import 'command_result.dart';

/// コマンド実行の抽象。
abstract interface class CommandExecutor {
  /// [request] に基づいてコマンドを実行する。
  ///
  /// - transport / output の要件は [CommandRequest] で明示する。
  /// - 失敗は [CommandResult] の exitCode または例外（接続断・タイムアウト等）。
  /// - timeout は `execute()` 全体の deadline。timeout 後にコマンドの自動
  ///   再実行はしない（実行結果が不明のため）。
  Future<CommandResult> execute(CommandRequest request);
}
