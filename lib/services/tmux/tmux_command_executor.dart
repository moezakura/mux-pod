// inventory: TMUX-EXEC-000
/// tmux 用 command executor 抽象
///
/// SSH 等の transport がこの interface を実装し、TmuxFacade は transport の
/// 詳細を知らずに tmux 操作を行える。
///
/// [CommandExecutor] を拡張し、コマンド実行は [CommandRequest] ベースで行う
/// （Codex 根本設計レビュー・バグ2 根本対応）。
library;

import 'dart:async';

import '../command/command_executor.dart';

abstract interface class TmuxCommandExecutor implements CommandExecutor {
  bool get isConnected;
  String? get tmuxPath;

  Future<void> sendKeysCommand(String command);
  Future<void> setWindowRestoreTrap(List<String> windowTargets);
  Future<void> restoreWindowsNoWait(List<String> targets);
  void write(String data);
}
