// inventory: TMUX-SESSION-CMD-000
/// tmux セッション操作（一覧以外）のコマンド文字列生成
library;

import 'arg_quoting.dart';

/// tmux セッション操作（一覧以外）のコマンド文字列生成。
class TmuxSessionCommands {
  // inventory: TMUX-CMD-004
  /// セッションが存在するか確認
  static String has(String sessionName) {
    return 'tmux has-session -t ${ShellCommandComposer.quote(sessionName)} 2>/dev/null && echo "1" || echo "0"';
  }

  // inventory: TMUX-CMD-005
  /// 新しいセッションを作成
  static String create({
    required String name,
    String? windowName,
    String? startDirectory,
    bool detached = true,
  }) {
    final parts = ['tmux', 'new-session'];
    if (detached) parts.add('-d');
    parts.addAll(['-s', ShellCommandComposer.quote(name)]);
    if (windowName != null) {
      parts.addAll(['-n', ShellCommandComposer.quote(windowName)]);
    }
    if (startDirectory != null) {
      parts.addAll(['-c', ShellCommandComposer.quote(startDirectory)]);
    }
    return parts.join(' ');
  }

  // inventory: TMUX-CMD-006
  /// セッションを削除
  static String kill(String sessionName) {
    return 'tmux kill-session -t ${ShellCommandComposer.quote(sessionName)}';
  }

  // inventory: TMUX-CMD-007
  /// セッション名を変更
  static String rename(String oldName, String newName) {
    return 'tmux rename-session -t ${ShellCommandComposer.quote(oldName)} ${ShellCommandComposer.quote(newName)}';
  }

  // inventory: TMUX-CMD-041
  /// セッションにアタッチ
  static String attach(String sessionName) {
    return 'tmux attach-session -t ${ShellCommandComposer.quote(sessionName)}';
  }

  // inventory: TMUX-CMD-042
  /// セッションをデタッチ
  static String detach({String? sessionName}) {
    if (sessionName != null) {
      return 'tmux detach-client -s ${ShellCommandComposer.quote(sessionName)}';
    }
    return 'tmux detach-client';
  }

  // inventory: TMUX-CMD-043
  /// tmuxサーバーが起動しているか確認
  static String serverInfo() {
    return 'tmux server-info 2>&1';
  }

  // inventory: TMUX-CMD-044
  /// tmuxバージョンを取得
  static String version() {
    return 'tmux -V';
  }

  // inventory: TMUX-CMD-045
  /// tmuxサーバーを起動
  static String startServer() {
    return 'tmux start-server';
  }

  // inventory: TMUX-CMD-046
  /// tmuxサーバーを終了
  static String killServer() {
    return 'tmux kill-server';
  }
}
