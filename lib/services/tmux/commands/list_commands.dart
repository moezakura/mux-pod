// inventory: TMUX-LIST-CMD-000
/// tmux 一覧取得コマンドの生成（`-F` 出力）
library;

import '../tmux_delimiters.dart';
import 'arg_quoting.dart';

/// tmux 一覧取得（`-F` 出力）コマンドの生成と共用フォーマット生成。
///
/// TmuxParser と対応するフォーマット文字列を使用。
class TmuxListCommands {
  // inventory: TMUX-CMD-001
  /// Renders the `-F` argument of a list command from [fields].
  ///
  /// The delimiters are supplied per call ([TmuxDelimiters.random]) rather
  /// than fixed, so no session, window or pane name can contain one: see
  /// [TmuxDelimiters] for why they must also stay printable.
  static String _format(List<String> fields, TmuxDelimiters delimiters) =>
      '${fields.join(delimiters.field)}${delimiters.record}';

  // inventory: TMUX-CMD-002
  /// セッション一覧を取得するコマンド（詳細版）
  ///
  /// 出力フォーマット: `session_name\tsession_created\tsession_attached\tsession_windows\tsession_id`
  static String sessions(TmuxDelimiters delimiters) {
    const fields = [
      '#{session_name}',
      '#{session_created}',
      '#{session_attached}',
      '#{session_windows}',
      '#{session_id}',
    ];
    return 'tmux list-sessions -F "${_format(fields, delimiters)}"';
  }

  // inventory: TMUX-CMD-003
  /// セッション一覧を取得するコマンド（簡易版）
  ///
  /// 出力フォーマット: `session_name:session_windows:session_attached`
  static String sessionsSimple() {
    return 'tmux list-sessions -F "#{session_name}:#{session_windows}:#{session_attached}"';
  }

  // inventory: TMUX-CMD-008
  /// ウィンドウ一覧を取得するコマンド（詳細版）
  ///
  /// 出力フォーマット: `window_index\twindow_id\twindow_name\twindow_active\twindow_panes\twindow_flags`
  static String windows(String sessionName, TmuxDelimiters delimiters) {
    const fields = [
      '#{window_index}',
      '#{window_id}',
      '#{window_name}',
      '#{window_active}',
      '#{window_panes}',
      '#{window_flags}',
    ];
    return 'tmux list-windows -t ${ShellCommandComposer.quote(sessionName)} -F "${_format(fields, delimiters)}"';
  }

  // inventory: TMUX-CMD-009
  /// ウィンドウ一覧を取得するコマンド（簡易版）
  ///
  /// 出力フォーマット: `window_index:window_name:window_active:window_panes`
  static String windowsSimple(String sessionName) {
    return 'tmux list-windows -t ${ShellCommandComposer.quote(sessionName)} -F "'
        '#{window_index}:#{window_name}:#{window_active}:#{window_panes}"';
  }

  // inventory: TMUX-CMD-014
  /// ペイン一覧を取得するコマンド（詳細版）
  ///
  /// 出力フォーマット: `pane_index\tpane_id\tpane_active\tpane_current_command\tpane_title\tpane_width\tpane_height\tcursor_x\tcursor_y`
  static String panes(
    String sessionName,
    int windowIndex,
    TmuxDelimiters delimiters,
  ) {
    const fields = [
      '#{pane_index}',
      '#{pane_id}',
      '#{pane_active}',
      '#{pane_current_command}',
      '#{pane_title}',
      '#{pane_width}',
      '#{pane_height}',
      '#{cursor_x}',
      '#{cursor_y}',
    ];
    return 'tmux list-panes -t ${ShellCommandComposer.quote(sessionName)}:$windowIndex '
        '-F "${_format(fields, delimiters)}"';
  }

  // inventory: TMUX-CMD-015
  /// ペイン一覧を取得するコマンド（簡易版）
  ///
  /// 出力フォーマット: `pane_index:pane_id:pane_active:pane_width x pane_height`
  static String panesSimple(String sessionName, int windowIndex) {
    return 'tmux list-panes -t ${ShellCommandComposer.quote(sessionName)}:$windowIndex -F "'
        '#{pane_index}:#{pane_id}:#{pane_active}:#{pane_width}x#{pane_height}"';
  }

  // inventory: TMUX-CMD-016
  /// 全ペインを取得するコマンド（セッションツリー構築用）
  ///
  /// 出力フォーマット: 完全なツリー情報（window_flags含む）
  static String allPanes(TmuxDelimiters delimiters) {
    const fields = [
      '#{session_name}',
      '#{session_id}',
      '#{window_index}',
      '#{window_id}',
      '#{window_name}',
      '#{window_active}',
      '#{pane_index}',
      '#{pane_id}',
      '#{pane_active}',
      '#{pane_width}',
      '#{pane_height}',
      '#{pane_left}',
      '#{pane_top}',
      '#{pane_title}',
      '#{pane_current_command}',
      '#{cursor_x}',
      '#{cursor_y}',
      '#{pane_current_path}',
      '#{window_flags}',
    ];
    return 'tmux list-panes -a -F "${_format(fields, delimiters)}"';
  }
}
