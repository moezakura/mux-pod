/// tmuxコマンド生成サービス
///
/// tmuxコマンドを生成するユーティリティクラス。
/// TmuxParserと対応するフォーマット文字列を使用。
class TmuxCommands {
  /// デフォルトの区切り文字（SSH経由でタブが変換されるため|||を使用）
  static const String delimiter = '|||';

  // ===== セッション =====

  /// セッション一覧を取得するコマンド（詳細版）
  ///
  /// 出力フォーマット: `session_name\tsession_created\tsession_attached\tsession_windows\tsession_id`
  static String listSessions() {
    return 'tmux list-sessions -F "'
        '#{session_name}$delimiter'
        '#{session_created}$delimiter'
        '#{session_attached}$delimiter'
        '#{session_windows}$delimiter'
        '#{session_id}'
        '"';
  }

  /// セッション一覧を取得するコマンド（簡易版）
  ///
  /// 出力フォーマット: `session_name:session_windows:session_attached`
  static String listSessionsSimple() {
    return 'tmux list-sessions -F "#{session_name}:#{session_windows}:#{session_attached}"';
  }

  /// セッションが存在するか確認
  static String hasSession(String sessionName) {
    return 'tmux has-session -t ${_escapeArg(sessionName)} 2>/dev/null && echo "1" || echo "0"';
  }

  /// 新しいセッションを作成
  static String newSession({
    required String name,
    String? windowName,
    String? startDirectory,
    bool detached = true,
  }) {
    final parts = ['tmux', 'new-session'];
    if (detached) parts.add('-d');
    parts.addAll(['-s', _escapeArg(name)]);
    if (windowName != null) parts.addAll(['-n', _escapeArg(windowName)]);
    if (startDirectory != null) parts.addAll(['-c', _escapeArg(startDirectory)]);
    return parts.join(' ');
  }

  /// セッションを削除
  static String killSession(String sessionName) {
    return 'tmux kill-session -t ${_escapeArg(sessionName)}';
  }

  /// セッション名を変更
  static String renameSession(String oldName, String newName) {
    return 'tmux rename-session -t ${_escapeArg(oldName)} ${_escapeArg(newName)}';
  }

  // ===== ウィンドウ =====

  /// ウィンドウ一覧を取得するコマンド（詳細版）
  ///
  /// 出力フォーマット: `window_index\twindow_id\twindow_name\twindow_active\twindow_panes\twindow_flags`
  static String listWindows(String sessionName) {
    return 'tmux list-windows -t ${_escapeArg(sessionName)} -F "'
        '#{window_index}$delimiter'
        '#{window_id}$delimiter'
        '#{window_name}$delimiter'
        '#{window_active}$delimiter'
        '#{window_panes}$delimiter'
        '#{window_flags}'
        '"';
  }

  /// ウィンドウ一覧を取得するコマンド（簡易版）
  ///
  /// 出力フォーマット: `window_index:window_name:window_active:window_panes`
  static String listWindowsSimple(String sessionName) {
    return 'tmux list-windows -t ${_escapeArg(sessionName)} -F "'
        '#{window_index}:#{window_name}:#{window_active}:#{window_panes}"';
  }

  /// 新しいウィンドウを作成
  static String newWindow({
    required String sessionName,
    String? windowName,
    String? startDirectory,
    bool background = false,
  }) {
    final parts = ['tmux', 'new-window', '-t', _escapeArg(sessionName)];
    if (background) parts.add('-d');
    if (windowName != null) parts.addAll(['-n', _escapeArg(windowName)]);
    if (startDirectory != null) parts.addAll(['-c', _escapeArg(startDirectory)]);
    return parts.join(' ');
  }

  /// ウィンドウを選択
  static String selectWindow(String sessionName, int windowIndex) {
    return 'tmux select-window -t ${_escapeArg(sessionName)}:$windowIndex';
  }

  /// ウィンドウを削除
  static String killWindow(String sessionName, int windowIndex) {
    return 'tmux kill-window -t ${_escapeArg(sessionName)}:$windowIndex';
  }

  /// ウィンドウ名を変更
  static String renameWindow(String sessionName, int windowIndex, String newName) {
    return 'tmux rename-window -t ${_escapeArg(sessionName)}:$windowIndex ${_escapeArg(newName)}';
  }

  // ===== ペイン =====

  /// ペイン一覧を取得するコマンド（詳細版）
  ///
  /// 出力フォーマット: `pane_index\tpane_id\tpane_active\tpane_current_command\tpane_title\tpane_width\tpane_height\tcursor_x\tcursor_y`
  static String listPanes(String sessionName, int windowIndex) {
    return 'tmux list-panes -t ${_escapeArg(sessionName)}:$windowIndex -F "'
        '#{pane_index}$delimiter'
        '#{pane_id}$delimiter'
        '#{pane_active}$delimiter'
        '#{pane_current_command}$delimiter'
        '#{pane_title}$delimiter'
        '#{pane_width}$delimiter'
        '#{pane_height}$delimiter'
        '#{cursor_x}$delimiter'
        '#{cursor_y}'
        '"';
  }

  /// ペイン一覧を取得するコマンド（簡易版）
  ///
  /// 出力フォーマット: `pane_index:pane_id:pane_active:pane_width x pane_height`
  static String listPanesSimple(String sessionName, int windowIndex) {
    return 'tmux list-panes -t ${_escapeArg(sessionName)}:$windowIndex -F "'
        '#{pane_index}:#{pane_id}:#{pane_active}:#{pane_width}x#{pane_height}"';
  }

  /// 全ペインを取得するコマンド（セッションツリー構築用）
  ///
  /// 出力フォーマット: 完全なツリー情報
  static String listAllPanes() {
    return 'tmux list-panes -a -F "'
        '#{session_name}$delimiter'
        '#{session_id}$delimiter'
        '#{window_index}$delimiter'
        '#{window_id}$delimiter'
        '#{window_name}$delimiter'
        '#{window_active}$delimiter'
        '#{pane_index}$delimiter'
        '#{pane_id}$delimiter'
        '#{pane_active}$delimiter'
        '#{pane_width}$delimiter'
        '#{pane_height}$delimiter'
        '#{pane_left}$delimiter'
        '#{pane_top}$delimiter'
        '#{pane_title}$delimiter'
        '#{pane_current_command}$delimiter'
        '#{cursor_x}$delimiter'
        '#{cursor_y}'
        '"';
  }

  /// ペインを選択
  static String selectPane(String paneId) {
    return 'tmux select-pane -t ${_escapeArg(paneId)}';
  }

  /// ペインを分割（水平）
  static String splitWindowHorizontal({
    required String target,
    String? startDirectory,
    int? percentage,
  }) {
    final parts = ['tmux', 'split-window', '-h', '-t', _escapeArg(target)];
    if (percentage != null) parts.addAll(['-p', percentage.toString()]);
    if (startDirectory != null) parts.addAll(['-c', _escapeArg(startDirectory)]);
    return parts.join(' ');
  }

  /// ペインを分割（垂直）
  static String splitWindowVertical({
    required String target,
    String? startDirectory,
    int? percentage,
  }) {
    final parts = ['tmux', 'split-window', '-v', '-t', _escapeArg(target)];
    if (percentage != null) parts.addAll(['-p', percentage.toString()]);
    if (startDirectory != null) parts.addAll(['-c', _escapeArg(startDirectory)]);
    return parts.join(' ');
  }

  /// ペインを削除
  static String killPane(String paneId) {
    return 'tmux kill-pane -t ${_escapeArg(paneId)}';
  }

  /// ペインをズーム/アンズーム
  static String resizePane(String paneId, {bool zoom = true}) {
    return 'tmux resize-pane -t ${_escapeArg(paneId)} ${zoom ? '-Z' : '-z'}';
  }

  // ===== 入力・キー送信 =====

  /// キーを送信
  static String sendKeys(String paneId, String keys, {bool literal = false}) {
    final escapedKeys = _escapeArg(keys);
    if (literal) {
      return 'tmux send-keys -t ${_escapeArg(paneId)} -l $escapedKeys';
    }
    return 'tmux send-keys -t ${_escapeArg(paneId)} $escapedKeys';
  }

  /// Enterキーを送信
  static String sendEnter(String paneId) {
    return 'tmux send-keys -t ${_escapeArg(paneId)} Enter';
  }

  /// Ctrl+Cを送信
  static String sendInterrupt(String paneId) {
    return 'tmux send-keys -t ${_escapeArg(paneId)} C-c';
  }

  /// エスケープキーを送信
  static String sendEscape(String paneId) {
    return 'tmux send-keys -t ${_escapeArg(paneId)} Escape';
  }

  /// カーソル位置とペインサイズを取得
  static String getCursorPosition(String target) {
    return 'tmux display-message -p -t ${_escapeArg(target)} "#{cursor_x},#{cursor_y},#{pane_width},#{pane_height}"';
  }

  // ===== ペインコンテンツ =====

  /// ペインの内容をキャプチャ（ANSIエスケープ付き）
  static String capturePane(
    String paneId, {
    int? startLine,
    int? endLine,
    bool escapeSequences = true,
  }) {
    final parts = ['tmux', 'capture-pane', '-t', _escapeArg(paneId), '-p'];
    if (escapeSequences) parts.add('-e');
    if (startLine != null) parts.addAll(['-S', startLine.toString()]);
    if (endLine != null) parts.addAll(['-E', endLine.toString()]);
    return parts.join(' ');
  }

  /// ペインの可視領域をキャプチャ
  static String capturePaneVisible(String paneId) {
    return capturePane(paneId, escapeSequences: true);
  }

  /// ペインのスクロールバック全体をキャプチャ
  static String capturePaneAll(String paneId) {
    return capturePane(paneId, startLine: -32768, endLine: 32768);
  }

  // ===== セッション/アタッチ =====

  /// セッションにアタッチ
  static String attachSession(String sessionName) {
    return 'tmux attach-session -t ${_escapeArg(sessionName)}';
  }

  /// セッションをデタッチ
  static String detachClient({String? sessionName}) {
    if (sessionName != null) {
      return 'tmux detach-client -s ${_escapeArg(sessionName)}';
    }
    return 'tmux detach-client';
  }

  // ===== サーバー =====

  /// tmuxサーバーが起動しているか確認
  static String serverInfo() {
    return 'tmux server-info 2>&1';
  }

  /// tmuxバージョンを取得
  static String version() {
    return 'tmux -V';
  }

  /// tmuxサーバーを起動
  static String startServer() {
    return 'tmux start-server';
  }

  /// tmuxサーバーを終了
  static String killServer() {
    return 'tmux kill-server';
  }

  // ===== レイアウト =====

  /// 定義済みレイアウトを適用
  static String selectLayout(String target, TmuxLayout layout) {
    return 'tmux select-layout -t ${_escapeArg(target)} ${layout.name}';
  }

  // ===== ユーティリティ =====

  /// 引数をエスケープ
  static String _escapeArg(String arg) {
    // シェルの特殊文字をエスケープ
    // 特殊文字: スペース、クォート、バックスラッシュ、変数展開、バッククォート、その他
    if (arg.contains(RegExp(r'[\s"' "'" r'\\$`!{}\[\]<>|&;()]'))) {
      // ダブルクォートでラップし、内部の特殊文字をエスケープ
      final escaped = arg
          .replaceAll(r'\', r'\\')
          .replaceAll('"', r'\"')
          .replaceAll(r'$', r'\$')
          .replaceAll('`', r'\`');
      return '"$escaped"';
    }
    return arg;
  }

  /// 複数のコマンドを連結
  static String chain(List<String> commands) {
    return commands.join(' && ');
  }

  /// コマンドをパイプで連結
  static String pipe(List<String> commands) {
    return commands.join(' | ');
  }
}

/// tmuxレイアウト
enum TmuxLayout {
  /// 均等に水平分割
  evenHorizontal,

  /// 均等に垂直分割
  evenVertical,

  /// メインペインを上に配置
  mainHorizontal,

  /// メインペインを左に配置
  mainVertical,

  /// タイル状に配置
  tiled,
}

extension TmuxLayoutExtension on TmuxLayout {
  String get name {
    switch (this) {
      case TmuxLayout.evenHorizontal:
        return 'even-horizontal';
      case TmuxLayout.evenVertical:
        return 'even-vertical';
      case TmuxLayout.mainHorizontal:
        return 'main-horizontal';
      case TmuxLayout.mainVertical:
        return 'main-vertical';
      case TmuxLayout.tiled:
        return 'tiled';
    }
  }
}
