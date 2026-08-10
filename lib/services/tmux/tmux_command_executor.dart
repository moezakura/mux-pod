// inventory: TMUX-EXEC-000
/// tmux 用 command executor 抽象
///
/// SSH 等の transport がこの interface を実装し、TmuxFacade は transport の
/// 詳細を知らずに tmux 操作を行える。
///
/// [CommandExecutor] を拡張し、コマンド実行は [CommandRequest] ベースで行う
/// （Codex 根本設計レビュー・バグ2 根本対応）。旧 `exec` / `execPersistent` /
/// `execWithExitCode` は deprecated の互換 API（呼び出し移行後に削除予定）。
library;

import 'dart:async';

import '../command/command_executor.dart';

abstract interface class TmuxCommandExecutor implements CommandExecutor {
  bool get isConnected;
  String? get tmuxPath;

  /// deprecated: [CommandExecutor.execute] を使う。
  Future<String> exec(String command, {Duration? timeout});

  /// deprecated: [CommandExecutor.execute] を使う。
  Future<String> execPersistent(String command, {Duration? timeout});

  /// deprecated: [CommandExecutor.execute] を使う。
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  });

  Future<void> sendKeysCommand(String command);
  Future<void> setWindowRestoreTrap(List<String> windowTargets);
  Future<void> restoreWindowsNoWait(List<String> targets);
  void write(String data);
}
