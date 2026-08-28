// inventory: TMUX-CMD-BUILDER-000
/// tmux コマンド文字列生成
library;

import 'dart:convert';
import 'dart:math';

import 'tmux_executable_resolver.dart';

// inventory: TMUX-CMD-000
/// tmuxコマンド生成サービス
///
/// tmuxコマンドを生成するユーティリティクラス。
/// TmuxParserと対応するフォーマット文字列を使用。
class TmuxCommands {
  // inventory: TMUX-CMD-001
  /// Field delimiter. Printable on purpose: tmux 3.7 rewrites every
  /// non-printable byte in `-F` output to `_`, so a control character here
  /// arrives indistinguishable from the next one and parsing yields nothing.
  static const String fieldDelimiter = '@@F@@';

  /// Record delimiter, appended after each record so a newline inside a field
  /// cannot split it. Printable for the same reason as [fieldDelimiter].
  static const String recordDelimiter = '@@R@@';

  /// 旧区切り文字（後方互換）。
  @Deprecated('Use fieldDelimiter')
  static const String delimiter = fieldDelimiter;

  // ===== セッション =====

  // inventory: TMUX-CMD-002
  /// セッション一覧を取得するコマンド（詳細版）
  ///
  /// 出力フォーマット: `session_name\tsession_created\tsession_attached\tsession_windows\tsession_id`
  static String listSessions() {
    return 'tmux list-sessions -F "'
        '#{session_name}$fieldDelimiter'
        '#{session_created}$fieldDelimiter'
        '#{session_attached}$fieldDelimiter'
        '#{session_windows}$fieldDelimiter'
        '#{session_id}$recordDelimiter'
        '"';
  }

  // inventory: TMUX-CMD-003
  /// セッション一覧を取得するコマンド（簡易版）
  ///
  /// 出力フォーマット: `session_name:session_windows:session_attached`
  static String listSessionsSimple() {
    return 'tmux list-sessions -F "#{session_name}:#{session_windows}:#{session_attached}"';
  }

  // inventory: TMUX-CMD-004
  /// セッションが存在するか確認
  static String hasSession(String sessionName) {
    return 'tmux has-session -t ${_escapeArg(sessionName)} 2>/dev/null && echo "1" || echo "0"';
  }

  // inventory: TMUX-CMD-005
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
    if (startDirectory != null) {
      parts.addAll(['-c', _escapeArg(startDirectory)]);
    }
    return parts.join(' ');
  }

  // inventory: TMUX-CMD-006
  /// セッションを削除
  static String killSession(String sessionName) {
    return 'tmux kill-session -t ${_escapeArg(sessionName)}';
  }

  // inventory: TMUX-CMD-007
  /// セッション名を変更
  static String renameSession(String oldName, String newName) {
    return 'tmux rename-session -t ${_escapeArg(oldName)} ${_escapeArg(newName)}';
  }

  // ===== ウィンドウ =====

  // inventory: TMUX-CMD-008
  /// ウィンドウ一覧を取得するコマンド（詳細版）
  ///
  /// 出力フォーマット: `window_index\twindow_id\twindow_name\twindow_active\twindow_panes\twindow_flags`
  static String listWindows(String sessionName) {
    return 'tmux list-windows -t ${_escapeArg(sessionName)} -F "'
        '#{window_index}$fieldDelimiter'
        '#{window_id}$fieldDelimiter'
        '#{window_name}$fieldDelimiter'
        '#{window_active}$fieldDelimiter'
        '#{window_panes}$fieldDelimiter'
        '#{window_flags}$recordDelimiter'
        '"';
  }

  // inventory: TMUX-CMD-009
  /// ウィンドウ一覧を取得するコマンド（簡易版）
  ///
  /// 出力フォーマット: `window_index:window_name:window_active:window_panes`
  static String listWindowsSimple(String sessionName) {
    return 'tmux list-windows -t ${_escapeArg(sessionName)} -F "'
        '#{window_index}:#{window_name}:#{window_active}:#{window_panes}"';
  }

  // inventory: TMUX-CMD-010
  /// 新しいウィンドウを作成
  static String newWindow({
    required String sessionName,
    String? windowName,
    String? startDirectory,
    bool background = false,
  }) {
    // セッション名にコロンを付与し、数値セッション名（例: "1"）が
    // tmux によりウィンドウインデックスと誤解釈されるのを防ぐ。
    // （`tmux new-window -t 1` は「現在セッションのウィンドウ番号1」を指す。
    //   `-t 1:` とすればセッション「1」として正しく解決される）
    final parts = ['tmux', 'new-window', '-t', _escapeArg('$sessionName:')];
    if (background) parts.add('-d');
    if (windowName != null) parts.addAll(['-n', _escapeArg(windowName)]);
    if (startDirectory != null) {
      parts.addAll(['-c', _escapeArg(startDirectory)]);
    }
    return parts.join(' ');
  }

  // inventory: TMUX-CMD-011
  /// ウィンドウを選択
  static String selectWindow(String sessionName, int windowIndex) {
    return 'tmux select-window -t ${_escapeArg(sessionName)}:$windowIndex';
  }

  // inventory: TMUX-CMD-012
  /// ウィンドウを削除
  static String killWindow(String sessionName, int windowIndex) {
    return 'tmux kill-window -t ${_escapeArg(sessionName)}:$windowIndex';
  }

  // inventory: TMUX-CMD-013
  /// ウィンドウ名を変更
  static String renameWindow(
    String sessionName,
    int windowIndex,
    String newName,
  ) {
    return 'tmux rename-window -t ${_escapeArg(sessionName)}:$windowIndex ${_escapeArg(newName)}';
  }

  // ===== ペイン =====

  // inventory: TMUX-CMD-014
  /// ペイン一覧を取得するコマンド（詳細版）
  ///
  /// 出力フォーマット: `pane_index\tpane_id\tpane_active\tpane_current_command\tpane_title\tpane_width\tpane_height\tcursor_x\tcursor_y`
  static String listPanes(String sessionName, int windowIndex) {
    return 'tmux list-panes -t ${_escapeArg(sessionName)}:$windowIndex -F "'
        '#{pane_index}$fieldDelimiter'
        '#{pane_id}$fieldDelimiter'
        '#{pane_active}$fieldDelimiter'
        '#{pane_current_command}$fieldDelimiter'
        '#{pane_title}$fieldDelimiter'
        '#{pane_width}$fieldDelimiter'
        '#{pane_height}$fieldDelimiter'
        '#{cursor_x}$fieldDelimiter'
        '#{cursor_y}$recordDelimiter'
        '"';
  }

  // inventory: TMUX-CMD-015
  /// ペイン一覧を取得するコマンド（簡易版）
  ///
  /// 出力フォーマット: `pane_index:pane_id:pane_active:pane_width x pane_height`
  static String listPanesSimple(String sessionName, int windowIndex) {
    return 'tmux list-panes -t ${_escapeArg(sessionName)}:$windowIndex -F "'
        '#{pane_index}:#{pane_id}:#{pane_active}:#{pane_width}x#{pane_height}"';
  }

  // inventory: TMUX-CMD-016
  /// 全ペインを取得するコマンド（セッションツリー構築用）
  ///
  /// 出力フォーマット: 完全なツリー情報（window_flags含む）
  static String listAllPanes() {
    return 'tmux list-panes -a -F "'
        '#{session_name}$fieldDelimiter'
        '#{session_id}$fieldDelimiter'
        '#{window_index}$fieldDelimiter'
        '#{window_id}$fieldDelimiter'
        '#{window_name}$fieldDelimiter'
        '#{window_active}$fieldDelimiter'
        '#{pane_index}$fieldDelimiter'
        '#{pane_id}$fieldDelimiter'
        '#{pane_active}$fieldDelimiter'
        '#{pane_width}$fieldDelimiter'
        '#{pane_height}$fieldDelimiter'
        '#{pane_left}$fieldDelimiter'
        '#{pane_top}$fieldDelimiter'
        '#{pane_title}$fieldDelimiter'
        '#{pane_current_command}$fieldDelimiter'
        '#{cursor_x}$fieldDelimiter'
        '#{cursor_y}$fieldDelimiter'
        '#{pane_current_path}$fieldDelimiter'
        '#{window_flags}$recordDelimiter'
        '"';
  }

  // inventory: TMUX-CMD-017
  /// ペインを選択
  static String selectPane(String paneId) {
    return 'tmux select-pane -t ${_escapeArg(paneId)}';
  }

  // inventory: TMUX-CMD-018
  /// ペインを分割（水平）
  static String splitWindowHorizontal({
    required String target,
    String? startDirectory,
    int? percentage,
  }) {
    final parts = ['tmux', 'split-window', '-h', '-t', _escapeArg(target)];
    if (percentage != null) parts.addAll(['-p', percentage.toString()]);
    if (startDirectory != null) {
      parts.addAll(['-c', _escapeArg(startDirectory)]);
    }
    return parts.join(' ');
  }

  // inventory: TMUX-CMD-019
  /// ペインを分割（垂直）
  static String splitWindowVertical({
    required String target,
    String? startDirectory,
    int? percentage,
  }) {
    final parts = ['tmux', 'split-window', '-v', '-t', _escapeArg(target)];
    if (percentage != null) parts.addAll(['-p', percentage.toString()]);
    if (startDirectory != null) {
      parts.addAll(['-c', _escapeArg(startDirectory)]);
    }
    return parts.join(' ');
  }

  // inventory: TMUX-CMD-020
  /// ペインを削除
  static String killPane(String paneId) {
    return 'tmux kill-pane -t ${_escapeArg(paneId)}';
  }

  // inventory: TMUX-CMD-021
  /// ペインをズーム/アンズーム
  static String resizePane(String paneId, {bool zoom = true}) {
    return 'tmux resize-pane -t ${_escapeArg(paneId)} ${zoom ? '-Z' : '-z'}';
  }

  // inventory: TMUX-CMD-022
  /// ペインを指定サイズにリサイズする
  /// cols/rowsはオプション（片方のみ指定可、tmuxは未指定の方を変更しない）
  static String resizePaneToSize(String paneId, {int? cols, int? rows}) {
    final args = <String>['-t', _escapeArg(paneId)];
    if (cols != null) args.addAll(['-x', '$cols']);
    if (rows != null) args.addAll(['-y', '$rows']);
    return 'tmux resize-pane ${args.join(' ')}';
  }

  // inventory: TMUX-CMD-023
  /// ウィンドウを指定サイズにリサイズする（tmux 2.9+必須）
  static String resizeWindow(String target, {int? cols, int? rows}) {
    final args = <String>['-t', _escapeArg(target)];
    if (cols != null) args.addAll(['-x', '$cols']);
    if (rows != null) args.addAll(['-y', '$rows']);
    return 'tmux resize-window ${args.join(' ')}';
  }

  // inventory: TMUX-CMD-024
  /// ウィンドウを自動サイズ（クライアント追従）に戻す。
  /// -A で最大クライアントサイズへ即リサイズし、window-size の manual を解除する。
  static String resizeWindowAuto(String target) {
    final t = _escapeArg(target);
    return 'tmux resize-window -t $t -A ; tmux set -uw -t $t window-size';
  }

  // inventory: TMUX-CMD-025
  /// AutoResizeで縮めたウィンドウを、接続断時にサーバ側で自動復元するtrapを組み立てる。
  ///
  /// アプリがスワイプ終了・強制終了・クラッシュで復元コマンドを送れずに死んでも、
  /// SSHチャネルが閉じて入力シェルがHUP/EXIT/TERMする際にtmuxウィンドウが自動サイズへ
  /// 戻る（tmuxサーバはSSHシェルとは別プロセスなので生存しており復元コマンドは届く）。
  ///
  /// [tmuxBin] は検出済みのtmux絶対パス（シェル終了時はPATHが最小化される場合が
  /// あるため絶対パスを使う）。[targets] が空なら [clearWindowRestoreTrap] を返す。
  static String windowRestoreTrap(
    List<String> targets, {
    required String tmuxBin,
  }) {
    if (targets.isEmpty) return clearWindowRestoreTrap();
    // 全ターゲットを1回のtmux起動にまとめ、\;でコマンド連結する。teardown中に
    // 2つ目のtmuxプロセス起動がSIGKILLで打ち切られ、サイズ復元だけ実行されて
    // window-size manualの解除が漏れるのを防ぐ（単一プロセスなら両方まとめて完了）。
    final seq = targets
        .map((t) {
          final tt = _escapeArg(t);
          return 'resize-window -t $tt -A \\; set -uw -t $tt window-size';
        })
        .join(' \\; ');
    final quotedBin = TmuxExecutableResolver.shQuote(tmuxBin);
    final body = '$quotedBin $seq 2>/dev/null';
    // HUP必須: PTYチャネルclose時のSIGHUPはHUPを明示トラップしないとEXIT trapを
    // 実行せずシェルを終了させる。bodyは冪等なのでHUP後のEXITで二重実行しても無害。
    // ダブルクォートで囲み、quotedBin 内のシングルクォートを安全に埋め込む。
    return 'trap "$body" EXIT HUP TERM';
  }

  // inventory: TMUX-CMD-026
  /// [windowRestoreTrap] で設定したtrapを解除する。
  static String clearWindowRestoreTrap() => 'trap - EXIT HUP TERM';

  // ===== 入力・キー送信 =====

  // inventory: TMUX-CMD-027
  /// キーを送信
  static String sendKeys(String paneId, String keys, {bool literal = false}) {
    final escapedKeys = _escapeArg(keys);
    // `--` で tmux 側のオプション解析を打ち切る。これがないと、ダッシュで
    // 始まる入力（例: `-X`）が send-keys のオプションとして解釈され、
    // 文字入力ではなくコピーモード操作等に化ける。
    if (literal) {
      return 'tmux send-keys -t ${_escapeArg(paneId)} -l -- $escapedKeys';
    }
    return 'tmux send-keys -t ${_escapeArg(paneId)} -- $escapedKeys';
  }

  // inventory: TMUX-CMD-028
  /// Enterキーを送信
  static String sendEnter(String paneId) {
    return 'tmux send-keys -t ${_escapeArg(paneId)} Enter';
  }

  // inventory: TMUX-CMD-029
  /// Build a single shell command that loads [text] into a named tmux
  /// buffer and pastes it into the given [target] pane using bracketed
  /// paste mode (`paste-buffer -p`).
  ///
  /// Intended for multi-line text only; single-key / control-key paths
  /// use [sendKeys] directly.
  ///
  /// The payload is base64-encoded in transit so any shell-special
  /// characters in [text] do not need extra escaping. The receiving
  /// remote is expected to have a POSIX `base64` binary on PATH.
  ///
  /// The buffer is named with a microsecond timestamp plus a random hex
  /// suffix to avoid collisions when multiple paste operations run
  /// concurrently. `-d` deletes the buffer immediately after pasting.
  ///
  /// Practical upper bound: tested up to ~100 KB; very large pastes may
  /// exceed ARG_MAX (~256 KB on macOS, ~2 MB on Linux). True stdin-piping
  /// via dartssh2 would remove this limit but is deferred.
  ///
  /// Note: requires tmux >= 2.6 for `-p` (bracketed paste). Use
  /// [loadBufferAndPasteNoBracketed] as a fallback for older tmux.
  static String loadBufferAndPaste(String target, String text) {
    final encoded = base64.encode(utf8.encode(text));
    final rand = Random().nextInt(0xffffff).toRadixString(16).padLeft(6, '0');
    // bufName is safe: numeric + lowercase hex only — no escaping needed.
    final bufName = 'muxpod-${DateTime.now().microsecondsSinceEpoch}-$rand';
    return "printf '%s' '$encoded' | base64 -d "
        "| tmux load-buffer -b '$bufName' - "
        "&& tmux paste-buffer -d -p -b '$bufName' -t ${_escapeArg(target)}";
  }

  // inventory: TMUX-CMD-030
  /// Fallback variant of [loadBufferAndPaste] for tmux < 2.6, which does
  /// not support the `-p` (bracketed paste) flag on `paste-buffer`.
  ///
  /// Prefer [loadBufferAndPaste] when the remote tmux version is >= 2.6.
  static String loadBufferAndPasteNoBracketed(String target, String text) {
    final encoded = base64.encode(utf8.encode(text));
    final rand = Random().nextInt(0xffffff).toRadixString(16).padLeft(6, '0');
    // bufName is safe: numeric + lowercase hex only — no escaping needed.
    final bufName = 'muxpod-${DateTime.now().microsecondsSinceEpoch}-$rand';
    return "printf '%s' '$encoded' | base64 -d "
        "| tmux load-buffer -b '$bufName' - "
        "&& tmux paste-buffer -d -b '$bufName' -t ${_escapeArg(target)}";
  }

  // inventory: TMUX-CMD-031
  /// Ctrl+Cを送信
  static String sendInterrupt(String paneId) {
    return 'tmux send-keys -t ${_escapeArg(paneId)} C-c';
  }

  // inventory: TMUX-CMD-032
  /// エスケープキーを送信
  static String sendEscape(String paneId) {
    return 'tmux send-keys -t ${_escapeArg(paneId)} Escape';
  }

  // inventory: TMUX-CMD-033
  /// カーソル位置とペインサイズを取得
  static String getCursorPosition(String target) {
    return 'tmux display-message -p -t ${_escapeArg(target)} "#{cursor_x},#{cursor_y},#{pane_width},#{pane_height}"';
  }

  // inventory: TMUX-CMD-034
  /// ペインのモードを取得（copy-mode検出用）
  static String getPaneMode(String target) {
    return 'tmux display-message -p -t ${_escapeArg(target)} "#{pane_mode}"';
  }

  // inventory: TMUX-CMD-035
  /// copy-modeに入る
  static String enterCopyMode(String target) {
    return 'tmux copy-mode -t ${_escapeArg(target)}';
  }

  // inventory: TMUX-CMD-036
  /// copy-modeを終了（copy-mode中のみ有効、非copy-mode時は無害）
  static String cancelCopyMode(String target) {
    return 'tmux send-keys -t ${_escapeArg(target)} -X cancel';
  }

  // ===== ペインコンテンツ =====

  // inventory: TMUX-CMD-037
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

  // inventory: TMUX-CMD-038
  /// ペインの可視領域をキャプチャ
  static String capturePaneVisible(String paneId) {
    return capturePane(paneId, escapeSequences: true);
  }

  // inventory: TMUX-CMD-039
  /// ペインのスクロールバック全体をキャプチャ
  static String capturePaneAll(String paneId) {
    return capturePane(paneId, startLine: -32768, endLine: 32768);
  }

  // inventory: TMUX-CMD-040
  /// 指定セッションの履歴（スクロールバック）保持行数を設定する。
  /// グローバル(-g)ではなく対象セッションのみに適用し、ユーザーの
  /// tmuxサーバ全体の設定を書き換えない。tmuxの仕様上、既存ペインには
  /// 遡って適用されず、以後そのセッションに作成されるペインに効く。
  static String setHistoryLimit(int lines, {required String target}) {
    return 'tmux set-option -t ${_escapeArg(target)} history-limit $lines';
  }

  // ===== セッション/アタッチ =====

  // inventory: TMUX-CMD-041
  /// セッションにアタッチ
  static String attachSession(String sessionName) {
    return 'tmux attach-session -t ${_escapeArg(sessionName)}';
  }

  // inventory: TMUX-CMD-042
  /// セッションをデタッチ
  static String detachClient({String? sessionName}) {
    if (sessionName != null) {
      return 'tmux detach-client -s ${_escapeArg(sessionName)}';
    }
    return 'tmux detach-client';
  }

  // ===== サーバー =====

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

  // ===== レイアウト =====

  // inventory: TMUX-CMD-047
  /// 定義済みレイアウトを適用
  static String selectLayout(String target, TmuxLayout layout) {
    return 'tmux select-layout -t ${_escapeArg(target)} ${layout.name}';
  }

  // ===== ユーティリティ =====

  // inventory: TMUX-ESC-001
  /// 引数をエスケープ
  static String _escapeArg(String arg) {
    // 制御文字（0x00-0x1F / 0x7F）を含む場合は bash の ANSI-C quoting
    // （$'...'）で送る。ダブルクォート等の通常の引用符では、コマンドライン
    // 内の制御文字（Ctrl+A = 行頭移動、Ctrl+O = 履歴操作等）を対話シェルの
    // readline が解釈して失うため（herdr の _shellQuote と同様）。
    if (arg.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      final buffer = StringBuffer("\$");
      buffer.write("'");
      for (final rune in arg.runes) {
        if (rune < 0x20 || rune == 0x7f) {
          buffer.write('\\x${rune.toRadixString(16).padLeft(2, '0')}');
        } else if (rune == 0x5c) {
          // backslash
          buffer.write(r'\\');
        } else if (rune == 0x27) {
          // single quote
          buffer.write(r"\'");
        } else {
          buffer.writeCharCode(rune);
        }
      }
      buffer.write("'");
      return buffer.toString();
    }

    // シェルの特殊文字をエスケープ
    // 特殊文字: スペース、クォート、バックスラッシュ、変数展開、バッククォート、
    // グロブ（*?）、チルダ（~）、コメント（#）、その他
    if (arg.contains(
      RegExp(
        r'[\s"'
        "'"
        r'\\$`!{}\[\]<>|&;()*?~#]',
      ),
    )) {
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

  // inventory: TMUX-UTIL-001
  /// 複数のコマンドを連結
  static String chain(List<String> commands) {
    return commands.join(' && ');
  }

  // inventory: TMUX-UTIL-002
  /// コマンドをパイプで連結
  static String pipe(List<String> commands) {
    return commands.join(' | ');
  }
}

// inventory: TMUX-ENUM-001
/// ペイン分割方向
enum SplitDirection {
  /// 右に分割（左右に並べる） - tmux split-window -h
  horizontal,

  /// 下に分割（上下に並べる） - tmux split-window -v
  vertical,
}

// inventory: TMUX-ENUM-002
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
  // inventory: TMUX-EXT-001
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
