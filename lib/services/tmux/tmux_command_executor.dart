// inventory: TMUX-EXEC-000
/// tmux 用 command executor 抽象
///
/// SSH 等の transport がこの interface を実装し、TmuxFacade は transport の
/// 詳細を知らずに tmux 操作を行える。
library;

import 'dart:async';

abstract interface class TmuxCommandExecutor {
  bool get isConnected;
  String? get tmuxPath;

  Future<String> exec(String command, {Duration? timeout});
  Future<String> execPersistent(String command, {Duration? timeout});
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  });

  Future<void> sendKeysCommand(String command);
  Future<void> setWindowRestoreTrap(List<String> windowTargets);
  Future<void> restoreWindowsNoWait(List<String> targets);
  void write(String data);
}
