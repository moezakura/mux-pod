/// tmuxコマンド出力情報
class TmuxSessionInfo {
  final String name;
  final DateTime created;
  final bool attached;
  final int windowCount;

  const TmuxSessionInfo({
    required this.name,
    required this.created,
    required this.attached,
    required this.windowCount,
  });
}

class TmuxWindowInfo {
  final int index;
  final String name;
  final bool active;
  final int paneCount;

  const TmuxWindowInfo({
    required this.index,
    required this.name,
    required this.active,
    required this.paneCount,
  });
}

class TmuxPaneInfo {
  final int index;
  final String id;
  final bool active;
  final String currentCommand;
  final String title;
  final int width;
  final int height;
  final int cursorX;
  final int cursorY;

  const TmuxPaneInfo({
    required this.index,
    required this.id,
    required this.active,
    required this.currentCommand,
    required this.title,
    required this.width,
    required this.height,
    required this.cursorX,
    required this.cursorY,
  });
}

/// tmuxコマンド出力パーサー
class TmuxParser {
  /// セッション出力をパース
  /// Format: name\tcreated\tattached\twindows
  List<TmuxSessionInfo> parseSessions(String output) {
    final lines = output.trim().split('\n');
    final sessions = <TmuxSessionInfo>[];

    for (final line in lines) {
      if (line.isEmpty) continue;

      final parts = line.split('\t');
      if (parts.length < 4) continue;

      try {
        sessions.add(TmuxSessionInfo(
          name: parts[0],
          created: DateTime.fromMillisecondsSinceEpoch(
            int.parse(parts[1]) * 1000,
          ),
          attached: parts[2] == '1',
          windowCount: int.parse(parts[3]),
        ));
      } catch (_) {
        // パースエラーは無視
      }
    }

    return sessions;
  }

  /// ウィンドウ出力をパース
  /// Format: index\tname\tactive\tpanes
  List<TmuxWindowInfo> parseWindows(String output) {
    final lines = output.trim().split('\n');
    final windows = <TmuxWindowInfo>[];

    for (final line in lines) {
      if (line.isEmpty) continue;

      final parts = line.split('\t');
      if (parts.length < 4) continue;

      try {
        windows.add(TmuxWindowInfo(
          index: int.parse(parts[0]),
          name: parts[1],
          active: parts[2] == '1',
          paneCount: int.parse(parts[3]),
        ));
      } catch (_) {
        // パースエラーは無視
      }
    }

    return windows;
  }

  /// ペイン出力をパース
  /// Format: index\tid\tactive\tcmd\ttitle\twidth\theight\tcursorX\tcursorY
  List<TmuxPaneInfo> parsePanes(String output) {
    final lines = output.trim().split('\n');
    final panes = <TmuxPaneInfo>[];

    for (final line in lines) {
      if (line.isEmpty) continue;

      final parts = line.split('\t');
      if (parts.length < 9) continue;

      try {
        panes.add(TmuxPaneInfo(
          index: int.parse(parts[0]),
          id: parts[1],
          active: parts[2] == '1',
          currentCommand: parts[3],
          title: parts[4],
          width: int.parse(parts[5]),
          height: int.parse(parts[6]),
          cursorX: int.parse(parts[7]),
          cursorY: int.parse(parts[8]),
        ));
      } catch (_) {
        // パースエラーは無視
      }
    }

    return panes;
  }
}
