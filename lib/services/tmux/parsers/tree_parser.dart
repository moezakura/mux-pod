// inventory: TMUX-TREE-PARSER-000
/// tmux セッションツリー全体の構築
///
/// このパーサは行パーサ（[TmuxSessionParser.parseLine] 等）とは独立に
/// record を直接解釈する（19フィールド）。行パーサとの統合は挙動変更に
/// なるため行わない（将来課題）。
library;

import '../tmux_delimiters.dart';
import '../tmux_models.dart';
import 'output_validator.dart';
import 'window_parser.dart';

/// tmux セッションツリー全体の構築。
class TmuxTreeParser {
  // inventory: TMUX-PARSER-013
  /// セッションツリー全体をパース
  ///
  /// `tmux list-panes -a -F "..."`の出力から完全なツリーを構築
  static List<TmuxSession> parse(
    String output, {
    TmuxDelimiters delimiters = TmuxOutputValidator.defaultDelimiters,
  }) {
    if (!TmuxOutputValidator.isServerRunning(output)) {
      return [];
    }
    output = TmuxOutputValidator.normalizeDelimiters(output, delimiters);

    final sessionsMap = <String, TmuxSession>{};
    final windowsMap = <String, Map<int, TmuxWindow>>{};

    for (final record in output.split(delimiters.record)) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(delimiters.field);
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
      final paneTitle = parts.length > 13 && parts[13].isNotEmpty
          ? parts[13]
          : null;
      final paneCurrentCommand = parts.length > 14 && parts[14].isNotEmpty
          ? parts[14]
          : null;
      final cursorX = parts.length > 15 ? int.tryParse(parts[15]) ?? 0 : 0;
      final cursorY = parts.length > 16 ? int.tryParse(parts[16]) ?? 0 : 0;
      final paneCurrentPath = parts.length > 17 && parts[17].isNotEmpty
          ? parts[17]
          : null;

      // セッションを取得または作成
      sessionsMap.putIfAbsent(
        sessionName,
        () => TmuxSession(name: sessionName, id: sessionId),
      );

      final windowFlags = parts.length > 18
          ? TmuxWindowParser.parseFlags(parts[18])
          : const <TmuxWindowFlag>{};

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
      windows[windowIndex]!.panes.add(
        TmuxPane(
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
        ),
      );
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

      sessions.add(
        session.copyWith(
          windows: windowsWithPaneCount,
          windowCount: windowsWithPaneCount.length,
        ),
      );
    }

    return sessions;
  }
}
