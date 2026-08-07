// inventory: TMUX-PARSER-ADAPTER-000
/// tmux コマンド出力パーサー（アダプター）
library;

import 'tmux_models.dart';

// inventory: TMUX-PARSER-000
/// tmuxコマンド出力パーサー
///
/// tmuxコマンドの出力をパースしてオブジェクトに変換する。
/// フォーマット文字列に対応したパーサーを提供。
class TmuxParser {
  // inventory: TMUX-PARSER-001
  /// デフォルトのフィールド区切り文字（US: 0x1f）。
  static const String defaultFieldDelimiter = '\x1f';

  /// デフォルトのレコード区切り文字（RS: 0x1e）。
  static const String defaultRecordDelimiter = '\x1e';

  /// 旧区切り文字（後方互換）。
  @Deprecated('Use defaultFieldDelimiter')
  static const String defaultDelimiter = defaultFieldDelimiter;

  // ===== セッション =====

  // inventory: TMUX-PARSER-002
  /// セッション一覧をパース
  ///
  /// 対応フォーマット: `#{session_name}\t#{session_created}\t#{session_attached}\t#{session_windows}\t#{session_id}`
  static List<TmuxSession> parseSessions(
    String output, {
    String fieldDelimiter = defaultFieldDelimiter,
    String recordDelimiter = defaultRecordDelimiter,
  }) {
    if (!isServerRunning(output)) {
      return [];
    }
    output = normalizeDelimiters(output);

    final sessions = <TmuxSession>[];

    for (final record in output.split(recordDelimiter)) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) continue;

      final session = parseSessionLine(trimmed, delimiter: fieldDelimiter);
      if (session != null) {
        sessions.add(session);
      }
    }

    return sessions;
  }


  // inventory: TMUX-PARSER-003
  /// 単一のセッション行をパース
  static TmuxSession? parseSessionLine(
    String line, {
    String delimiter = defaultFieldDelimiter,
  }) {
    final parts = line.split(delimiter);
    // 区切り文字が含まれない行はtmux出力ではない（シェルエラー等）
    if (parts.length < 2) return null;

    final name = parts[0];
    if (name.isEmpty) return null;

    return TmuxSession(
      name: name,
      id: parts.length > 4 ? parts[4] : null,
      created: parts.length > 1 ? _parseTimestamp(parts[1]) : null,
      attached: parts.length > 2 ? parts[2] == '1' : false,
      windowCount: parts.length > 3 ? int.tryParse(parts[3]) ?? 0 : 0,
    );
  }

  // inventory: TMUX-PARSER-004
  /// 簡易フォーマットでセッションをパース
  ///
  /// フォーマット: `#{session_name}:#{session_windows}:#{session_attached}`
  static List<TmuxSession> parseSessionsSimple(String output) {
    if (!isServerRunning(output)) return [];

    final sessions = <TmuxSession>[];

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(':');
      if (parts.length >= 3) {
        sessions.add(TmuxSession(
          name: parts[0],
          windowCount: int.tryParse(parts[1]) ?? 0,
          attached: parts[2] == '1',
        ));
      }
    }

    return sessions;
  }

  // ===== ウィンドウ =====


  // inventory: TMUX-PARSER-005
  /// ウィンドウ一覧をパース
  ///
  /// 対応フォーマット: `#{window_index}\t#{window_id}\t#{window_name}\t#{window_active}\t#{window_panes}\t#{window_flags}`
  static List<TmuxWindow> parseWindows(
    String output, {
    String fieldDelimiter = defaultFieldDelimiter,
    String recordDelimiter = defaultRecordDelimiter,
  }) {
    output = normalizeDelimiters(output);
    final windows = <TmuxWindow>[];

    for (final record in output.split(recordDelimiter)) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) continue;

      final window = parseWindowLine(trimmed, delimiter: fieldDelimiter);
      if (window != null) {
        windows.add(window);
      }
    }


    return windows;
  }

  // inventory: TMUX-PARSER-006
  /// 単一のウィンドウ行をパース
  static TmuxWindow? parseWindowLine(
    String line, {
    String delimiter = defaultFieldDelimiter,
  }) {
    final parts = line.split(delimiter);
    if (parts.isEmpty) return null;

    final index = int.tryParse(parts[0]);
    if (index == null) return null;

    return TmuxWindow(
      index: index,
      id: parts.length > 1 ? parts[1] : null,
      name: parts.length > 2 ? parts[2] : 'window-$index',
      active: parts.length > 3 ? parts[3] == '1' : false,
      paneCount: parts.length > 4 ? int.tryParse(parts[4]) ?? 1 : 1,
      flags: parts.length > 5 ? _parseWindowFlags(parts[5]) : const {},
    );
  }

  // inventory: TMUX-PARSER-007
  /// 簡易フォーマットでウィンドウをパース
  ///
  /// フォーマット: `#{window_index}:#{window_name}:#{window_active}:#{window_panes}`
  static List<TmuxWindow> parseWindowsSimple(String output) {
    final windows = <TmuxWindow>[];

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(':');
      if (parts.length >= 4) {
        windows.add(TmuxWindow(
          index: int.tryParse(parts[0]) ?? 0,
          name: parts[1],
          active: parts[2] == '1',
          paneCount: int.tryParse(parts[3]) ?? 1,
        ));
      }
    }

    return windows;
  }

  // ===== ペイン =====

  // inventory: TMUX-PARSER-008
  /// ペイン一覧をパース
  ///
  /// 対応フォーマット: `#{pane_index}\t#{pane_id}\t#{pane_active}\t#{pane_current_command}\t#{pane_title}\t#{pane_width}\t#{pane_height}\t#{cursor_x}\t#{cursor_y}`
  static List<TmuxPane> parsePanes(
    String output, {
    String fieldDelimiter = defaultFieldDelimiter,
    String recordDelimiter = defaultRecordDelimiter,
  }) {
    output = normalizeDelimiters(output);
    final panes = <TmuxPane>[];

    for (final record in output.split(recordDelimiter)) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) continue;

      final pane = parsePaneLine(trimmed, delimiter: fieldDelimiter);
      if (pane != null) {
        panes.add(pane);
      }
    }

    return panes;
  }

  // inventory: TMUX-PARSER-009
  /// 単一のペイン行をパース
  static TmuxPane? parsePaneLine(
    String line, {
    String delimiter = defaultFieldDelimiter,
  }) {
    final parts = line.split(delimiter);
    if (parts.length < 2) return null;

    final index = int.tryParse(parts[0]);
    if (index == null) return null;

    final id = parts[1];
    if (id.isEmpty) return null;

    return TmuxPane(
      index: index,
      id: id,
      active: parts.length > 2 ? parts[2] == '1' : false,
      currentCommand: parts.length > 3 ? parts[3] : null,
      title: parts.length > 4 ? parts[4] : null,
      width: parts.length > 5 ? int.tryParse(parts[5]) ?? 80 : 80,
      height: parts.length > 6 ? int.tryParse(parts[6]) ?? 24 : 24,
      cursorX: parts.length > 7 ? int.tryParse(parts[7]) ?? 0 : 0,
      cursorY: parts.length > 8 ? int.tryParse(parts[8]) ?? 0 : 0,
    );
  }

  // inventory: TMUX-PARSER-010
  /// 簡易フォーマットでペインをパース
  ///
  /// フォーマット: `#{pane_index}:#{pane_id}:#{pane_active}:#{pane_width}x#{pane_height}`
  static List<TmuxPane> parsePanesSimple(String output) {
    final panes = <TmuxPane>[];

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(':');
      if (parts.length >= 4) {
        final size = _parseSize(parts[3]);
        panes.add(TmuxPane(
          index: int.tryParse(parts[0]) ?? 0,
          id: parts[1],
          active: parts[2] == '1',
          width: size.width,
          height: size.height,
        ));
      }
    }

    return panes;
  }

  // ===== ペインコンテンツ =====

  // inventory: TMUX-PARSER-011
  /// capture-pane出力をパース（ANSIエスケープ付き）
  static TmuxPaneContent parsePaneContent(
    String output, {
    int? width,
    int? height,
    bool stripTrailingEmptyLines = true,
  }) {
    final lines = output.split('\n');

    if (stripTrailingEmptyLines) {
      while (lines.isNotEmpty && lines.last.trim().isEmpty) {
        lines.removeLast();
      }
    }

    return TmuxPaneContent(
      lines: lines,
      width: width ?? _guessWidth(lines),
      height: lines.length,
      hasAnsiColors: output.contains('\x1b['),
    );
  }

  // inventory: TMUX-PARSER-012
  /// capture-pane出力からプレーンテキストを抽出
  static String stripAnsiCodes(String text) {
    // ANSIエスケープシーケンスを削除
    return text.replaceAll(RegExp(r'\x1b\[[0-9;]*[a-zA-Z]'), '');
  }

  // ===== 完全なセッションツリー =====

  // inventory: TMUX-PARSER-013
  /// セッションツリー全体をパース
  ///
  /// `tmux list-panes -a -F "..."`の出力から完全なツリーを構築
  static List<TmuxSession> parseFullTree(
    String output, {
    String fieldDelimiter = defaultFieldDelimiter,
    String recordDelimiter = defaultRecordDelimiter,
  }) {
    if (!isServerRunning(output)) {
      return [];
    }
    output = normalizeDelimiters(output);

    final sessionsMap = <String, TmuxSession>{};
    final windowsMap = <String, Map<int, TmuxWindow>>{};

    for (final record in output.split(recordDelimiter)) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(fieldDelimiter);
      if (parts.length < 10) continue;

      // フォーマット: session_name, session_id, window_index, window_id, window_name, window_active,
      //              pane_index, pane_id, pane_active, pane_width, pane_height, pane_left, pane_top,
      //              pane_title, pane_current_command, cursor_x, cursor_y
      final sessionName = parts[0];
      final sessionId = parts[1];
      final windowIndex = int.tryParse(parts[2]) ?? 0;
      final windowId = parts[3];
      final windowName = parts[4];
      final windowActive = parts[5] == '1';
      final paneIndex = int.tryParse(parts[6]) ?? 0;
      final paneId = parts[7];
      final paneActive = parts[8] == '1';
      final paneWidth = int.tryParse(parts[9]) ?? 80;
      final paneHeight = parts.length > 10 ? int.tryParse(parts[10]) ?? 24 : 24;
      final paneLeft = parts.length > 11 ? int.tryParse(parts[11]) ?? 0 : 0;
      final paneTop = parts.length > 12 ? int.tryParse(parts[12]) ?? 0 : 0;
      final paneTitle = parts.length > 13 && parts[13].isNotEmpty ? parts[13] : null;
      final paneCurrentCommand = parts.length > 14 && parts[14].isNotEmpty ? parts[14] : null;
      final cursorX = parts.length > 15 ? int.tryParse(parts[15]) ?? 0 : 0;
      final cursorY = parts.length > 16 ? int.tryParse(parts[16]) ?? 0 : 0;
      final paneCurrentPath = parts.length > 17 && parts[17].isNotEmpty ? parts[17] : null;

      // セッションを取得または作成
      sessionsMap.putIfAbsent(
        sessionName,
        () => TmuxSession(name: sessionName, id: sessionId),
      );

      final windowFlags = parts.length > 18 ? _parseWindowFlags(parts[18]) : const <TmuxWindowFlag>{};

      // ウィンドウマップを取得または作成
      windowsMap.putIfAbsent(sessionName, () => {});
      final windows = windowsMap[sessionName]!;

      // ウィンドウを取得または作成
      windows.putIfAbsent(
        windowIndex,
        () => TmuxWindow(
          index: windowIndex,
          id: windowId,
          name: windowName,
          active: windowActive,
          flags: windowFlags,
        ),
      );

      // ペインを追加
      windows[windowIndex]!.panes.add(TmuxPane(
        index: paneIndex,
        id: paneId,
        active: paneActive,
        width: paneWidth,
        height: paneHeight,
        left: paneLeft,
        top: paneTop,
        title: paneTitle,
        currentCommand: paneCurrentCommand,
        cursorX: cursorX,
        cursorY: cursorY,
        currentPath: paneCurrentPath,
      ));
    }

    // ツリーを構築
    final sessions = <TmuxSession>[];
    for (final entry in sessionsMap.entries) {
      final session = entry.value;
      final windows = windowsMap[entry.key]?.values.toList() ?? [];
      windows.sort((a, b) => a.index.compareTo(b.index));

      // ウィンドウの paneCount は追加されたペイン数に合わせる
      final windowsWithPaneCount = windows
          .map((w) => w.copyWith(paneCount: w.panes.length))
          .toList();

      sessions.add(session.copyWith(
        windows: windowsWithPaneCount,
        windowCount: windowsWithPaneCount.length,
      ));
    }

    return sessions;
  }

  // ===== ユーティリティ =====

  // inventory: TMUX-PARSER-014
  /// Unixタイムスタンプをパース
  static DateTime? _parseTimestamp(String value) {
    final seconds = int.tryParse(value);
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  // inventory: TMUX-PARSER-015
  /// サイズ文字列をパース（例: "80x24"）
  static ({int width, int height}) _parseSize(String value) {
    final parts = value.split('x');
    return (
      width: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 80 : 80,
      height: parts.length > 1 ? int.tryParse(parts[1]) ?? 24 : 24,
    );
  }


  // inventory: TMUX-PARSER-016
  /// ウィンドウフラグをパース
  static Set<TmuxWindowFlag> _parseWindowFlags(String flags) {
    final result = <TmuxWindowFlag>{};
    if (flags.contains('*')) result.add(TmuxWindowFlag.current);
    if (flags.contains('-')) result.add(TmuxWindowFlag.last);
    if (flags.contains('#')) result.add(TmuxWindowFlag.activity);
    if (flags.contains('!')) result.add(TmuxWindowFlag.bell);
    if (flags.contains('~')) result.add(TmuxWindowFlag.silence);
    if (flags.contains('M')) result.add(TmuxWindowFlag.marked);
    if (flags.contains('Z')) result.add(TmuxWindowFlag.zoomed);
    return result;
  }

  // inventory: TMUX-PARSER-017
  /// 行から幅を推測
  static int _guessWidth(List<String> lines) {
    if (lines.isEmpty) return 80;
    int maxWidth = 0;
    for (final line in lines) {
      final stripped = stripAnsiCodes(line);
      if (stripped.length > maxWidth) {
        maxWidth = stripped.length;
      }
    }
    return maxWidth > 0 ? maxWidth : 80;
  }

  // inventory: TMUX-PARSER-018
  /// tmuxが実行中かチェック（サーバー起動確認）
  static bool isServerRunning(String output) {
    final lower = output.toLowerCase();
    return !lower.contains('no server running') &&
        !lower.contains('error connecting') &&
        !lower.contains('failed to connect') &&
        !lower.contains('command not found') &&
        !lower.contains('no such file or directory') &&
        !lower.contains('permission denied');
  }

  // inventory: TMUX-PARSER-020
  /// tmux の `-F` 出力で、制御文字がリテラル表記に化けた場合に制御文字へ戻す。
  ///
  /// tmux は `-F` フォーマット内の制御文字（0x1f / 0x1e）を、SSH シェル経由で
  /// `\037` / `\036`（8 進数表記）や `\x1f` / `\x1e`（16 進数表記）のリテラル
  /// 文字列として出力することがある。このヘルパーで各リテラル表記を元の
  /// 制御文字に正規化してから分割できるようにする。
  ///
  /// tmux のセッション名・ウィンドウ名は ASCII 制御文字を受け付けないため、
  /// リテラル表記が名前の中に現れて誤変換される実害はない。
  static String normalizeDelimiters(String output) {
    return output
        .replaceAll(r'\x1f', defaultFieldDelimiter)
        .replaceAll(r'\x1e', defaultRecordDelimiter)
        .replaceAll(r'\037', defaultFieldDelimiter)
        .replaceAll(r'\036', defaultRecordDelimiter);
  }

  // inventory: TMUX-PARSER-021
  /// エラーメッセージを抽出
  static String? extractError(String output) {
    final lower = output.toLowerCase();
    if (lower.contains('no server running')) {
      return 'tmux server is not running';
    }
    if (lower.contains('session not found')) {
      return 'Session not found';
    }
    if (lower.contains('window not found')) {
      return 'Window not found';
    }
    if (lower.contains('pane not found') || lower.contains("can't find pane")) {
      return 'Pane not found';
    }
    if (lower.contains('error')) {
      // 最初のエラー行を返す
      for (final line in output.split('\n')) {
        if (line.toLowerCase().contains('error')) {
          return line.trim();
        }
      }
    }
    return null;
  }
}

