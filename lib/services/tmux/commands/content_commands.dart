// inventory: TMUX-CONTENT-CMD-000
/// tmux ペインコンテンツ取得のコマンド文字列生成
library;

import 'arg_quoting.dart';

/// tmux ペインコンテンツ取得のコマンド文字列生成。
class TmuxContentCommands {
  // inventory: TMUX-CMD-037
  /// ペインの内容をキャプチャ（ANSIエスケープ付き）
  static String capture(
    String paneId, {
    int? startLine,
    int? endLine,
    bool escapeSequences = true,
  }) {
    final parts = [
      'tmux',
      'capture-pane',
      '-t',
      ShellCommandComposer.quote(paneId),
      '-p',
    ];
    if (escapeSequences) parts.add('-e');
    if (startLine != null) parts.addAll(['-S', startLine.toString()]);
    if (endLine != null) parts.addAll(['-E', endLine.toString()]);
    return parts.join(' ');
  }

  // inventory: TMUX-CMD-038
  /// ペインの可視領域をキャプチャ
  static String captureVisible(String paneId) {
    return capture(paneId, escapeSequences: true);
  }

  // inventory: TMUX-CMD-039
  /// ペインのスクロールバック全体をキャプチャ
  static String captureAll(String paneId) {
    return capture(paneId, startLine: -32768, endLine: 32768);
  }

  // inventory: TMUX-CMD-033
  /// カーソル位置とペインサイズを取得
  static String cursorPosition(String target) {
    return 'tmux display-message -p -t ${ShellCommandComposer.quote(target)} "#{cursor_x},#{cursor_y},#{pane_width},#{pane_height}"';
  }

  // inventory: TMUX-CMD-034
  /// ペインのモードを取得（copy-mode検出用）
  static String getMode(String target) {
    return 'tmux display-message -p -t ${ShellCommandComposer.quote(target)} "#{pane_mode}"';
  }

  // inventory: TMUX-CMD-040
  /// 指定セッションの履歴（スクロールバック）保持行数を設定する。
  /// グローバル(-g)ではなく対象セッションのみに適用し、ユーザーの
  /// tmuxサーバ全体の設定を書き換えない。tmuxの仕様上、既存ペインには
  /// 遡って適用されず、以後そのセッションに作成されるペインに効く。
  static String setHistoryLimit(int lines, {required String target}) {
    return 'tmux set-option -t ${ShellCommandComposer.quote(target)} history-limit $lines';
  }
}
