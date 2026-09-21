// inventory: TMUX-WINDOW-CMD-000
/// tmux ウィンドウ操作（一覧以外）のコマンド文字列生成
library;

import 'arg_quoting.dart';
import 'layout.dart';

/// tmux ウィンドウ操作（一覧以外）のコマンド文字列生成。
class TmuxWindowCommands {
  // inventory: TMUX-CMD-010
  /// 新しいウィンドウを作成
  static String create({
    required String sessionName,
    String? windowName,
    String? startDirectory,
    bool background = false,
  }) {
    // セッション名にコロンを付与し、数値セッション名（例: "1"）が
    // tmux によりウィンドウインデックスと誤解釈されるのを防ぐ。
    // （`tmux new-window -t 1` は「現在セッションのウィンドウ番号1」を指す。
    //   `-t 1:` とすればセッション「1」として正しく解決される）
    final parts = [
      'tmux',
      'new-window',
      '-t',
      ShellCommandComposer.quote('$sessionName:'),
    ];
    if (background) parts.add('-d');
    if (windowName != null) {
      parts.addAll(['-n', ShellCommandComposer.quote(windowName)]);
    }
    if (startDirectory != null) {
      parts.addAll(['-c', ShellCommandComposer.quote(startDirectory)]);
    }
    return parts.join(' ');
  }

  // inventory: TMUX-CMD-011
  /// ウィンドウを選択
  static String select(String sessionName, int windowIndex) {
    return 'tmux select-window -t ${ShellCommandComposer.quote(sessionName)}:$windowIndex';
  }

  // inventory: TMUX-CMD-012
  /// ウィンドウを削除
  static String kill(String sessionName, int windowIndex) {
    return 'tmux kill-window -t ${ShellCommandComposer.quote(sessionName)}:$windowIndex';
  }

  // inventory: TMUX-CMD-013
  /// ウィンドウ名を変更
  static String rename(String sessionName, int windowIndex, String newName) {
    return 'tmux rename-window -t ${ShellCommandComposer.quote(sessionName)}:$windowIndex ${ShellCommandComposer.quote(newName)}';
  }

  // inventory: TMUX-CMD-023
  /// ウィンドウを指定サイズにリサイズする（tmux 2.9+必須）
  static String resize(String target, {int? cols, int? rows}) {
    final args = <String>['-t', ShellCommandComposer.quote(target)];
    if (cols != null) args.addAll(['-x', '$cols']);
    if (rows != null) args.addAll(['-y', '$rows']);
    return 'tmux resize-window ${args.join(' ')}';
  }

  // inventory: TMUX-CMD-024
  /// ウィンドウを自動サイズ（クライアント追従）に戻す。
  /// -A で最大クライアントサイズへ即リサイズし、window-size の manual を解除する。
  static String resizeAuto(String target) {
    final t = ShellCommandComposer.quote(target);
    return 'tmux resize-window -t $t -A ; tmux set -uw -t $t window-size';
  }

  // inventory: TMUX-CMD-047
  /// 定義済みレイアウトを適用
  static String selectLayout(String target, TmuxLayout layout) {
    return 'tmux select-layout -t ${ShellCommandComposer.quote(target)} ${layout.name}';
  }
}
