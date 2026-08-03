// inventory: TMUX-MODELS-000
/// tmux DTO / target types
library;

// inventory: TMUX-MODELS-HELPER-001
/// ANSI エスケープシーケンスを削除（DTO 内部用）
String _stripAnsiCodes(String text) {
  return text.replaceAll(RegExp(r'\x1b\[[0-9;]*[a-zA-Z]'), '');
}


// ===== データモデル =====


// inventory: TMUX-FLAG-001
/// ウィンドウフラグ
enum TmuxWindowFlag {
  current,  // * - 現在のウィンドウ
  last,     // - - 最後にアクティブだったウィンドウ
  activity, // # - アクティビティ検出
  bell,     // ! - ベル検出
  silence,  // ~ - 無音検出
  marked,   // M - マーク
  zoomed,   // Z - ズーム
}

// inventory: TMUX-DTO-001
/// tmuxセッション
class TmuxSession {
  // inventory: TMUX-DTO-002
  final String name;
  // inventory: TMUX-DTO-003
  final String? id;
  // inventory: TMUX-DTO-004
  final DateTime? created;
  // inventory: TMUX-DTO-005
  final bool attached;
  // inventory: TMUX-DTO-006
  final int windowCount;
  // inventory: TMUX-DTO-007
  final List<TmuxWindow> windows;

  const TmuxSession({
    required this.name,
    this.id,
    this.created,
    this.attached = false,
    this.windowCount = 0,
    this.windows = const [],
  });

  // inventory: TMUX-DTO-008
  TmuxSession copyWith({
    String? name,
    String? id,
    DateTime? created,
    bool? attached,
    int? windowCount,
    List<TmuxWindow>? windows,
  }) {
    return TmuxSession(
      name: name ?? this.name,
      id: id ?? this.id,
      created: created ?? this.created,
      attached: attached ?? this.attached,
      windowCount: windowCount ?? this.windowCount,
      windows: windows ?? this.windows,
    );
  }

  // inventory: TMUX-DTO-009
  /// セッションのターゲット文字列を取得
  String get target => name;

  @override
  String toString() => 'TmuxSession($name, windows: $windowCount, attached: $attached)';


  // inventory: TMUX-DTO-010
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TmuxSession && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

// inventory: TMUX-DTO-011
/// tmuxウィンドウ
class TmuxWindow {
  // inventory: TMUX-DTO-012
  final int index;
  // inventory: TMUX-DTO-013
  final String? id;
  // inventory: TMUX-DTO-014
  final String name;
  // inventory: TMUX-DTO-015
  final bool active;
  // inventory: TMUX-DTO-016
  final int paneCount;
  // inventory: TMUX-DTO-017
  final Set<TmuxWindowFlag> flags;
  // inventory: TMUX-DTO-018
  final List<TmuxPane> panes;


  TmuxWindow({
    required this.index,
    this.id,
    required this.name,
    this.active = false,
    this.paneCount = 1,
    this.flags = const {},
    List<TmuxPane>? panes,
  }) : panes = panes ?? [];

  // inventory: TMUX-DTO-022
  TmuxWindow copyWith({
    int? index,
    String? id,
    String? name,
    bool? active,
    int? paneCount,
    Set<TmuxWindowFlag>? flags,
    List<TmuxPane>? panes,
  }) {
    return TmuxWindow(
      index: index ?? this.index,
      id: id ?? this.id,
      name: name ?? this.name,
      active: active ?? this.active,
      paneCount: paneCount ?? this.paneCount,
      flags: flags ?? this.flags,
      panes: panes ?? this.panes,
    );
  }

  // inventory: TMUX-DTO-019
  /// ウィンドウのターゲット文字列を取得
  String target(String sessionName) => '$sessionName:$index';

  // inventory: TMUX-DTO-020
  /// 現在のウィンドウかどうか
  bool get isCurrent => flags.contains(TmuxWindowFlag.current);

  // inventory: TMUX-DTO-021
  /// ズームされているかどうか
  bool get isZoomed => flags.contains(TmuxWindowFlag.zoomed);

  @override
  String toString() => 'TmuxWindow($index: $name, panes: $paneCount, active: $active)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TmuxWindow && runtimeType == other.runtimeType && index == other.index && id == other.id;

  @override
  int get hashCode => Object.hash(index, id);
}

// inventory: TMUX-DTO-023
/// tmuxペイン
class TmuxPane {
  // inventory: TMUX-DTO-024
  final int index;
  // inventory: TMUX-DTO-025
  final String id;
  // inventory: TMUX-DTO-026
  final bool active;
  // inventory: TMUX-DTO-027
  final String? currentCommand;
  // inventory: TMUX-DTO-028
  final String? title;
  // inventory: TMUX-GEOM-001
  final int width;
  // inventory: TMUX-GEOM-002
  final int height;
  // inventory: TMUX-GEOM-003
  final int left;
  // inventory: TMUX-GEOM-004
  final int top;
  // inventory: TMUX-CURSOR-001
  final int cursorX;
  // inventory: TMUX-CURSOR-002
  final int cursorY;
  // inventory: TMUX-CWD-001
  final String? currentPath;

  const TmuxPane({
    required this.index,
    required this.id,
    this.active = false,
    this.currentCommand,
    this.title,
    this.width = 80,
    this.height = 24,
    this.left = 0,
    this.top = 0,
    this.cursorX = 0,
    this.cursorY = 0,
    this.currentPath,
  });

  // inventory: TMUX-DTO-031
  TmuxPane copyWith({
    int? index,
    String? id,
    bool? active,
    String? currentCommand,
    String? title,
    int? width,
    int? height,
    int? left,
    int? top,
    int? cursorX,
    int? cursorY,
    String? currentPath,
  }) {
    return TmuxPane(
      index: index ?? this.index,
      id: id ?? this.id,
      active: active ?? this.active,
      currentCommand: currentCommand ?? this.currentCommand,
      title: title ?? this.title,
      width: width ?? this.width,
      height: height ?? this.height,
      left: left ?? this.left,
      top: top ?? this.top,
      cursorX: cursorX ?? this.cursorX,
      cursorY: cursorY ?? this.cursorY,
      currentPath: currentPath ?? this.currentPath,
    );
  }

  // inventory: TMUX-DTO-029
  /// ペインのターゲット文字列を取得
  String get target => id;


  // inventory: TMUX-DTO-030
  /// サイズを "80x24" 形式で取得
  String get sizeString => '${width}x$height';

  @override
  String toString() => 'TmuxPane($index: $id, ${width}x$height, active: $active)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TmuxPane && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// inventory: TMUX-DTO-032
/// ペインコンテンツ
class TmuxPaneContent {
  // inventory: TMUX-DTO-033
  final List<String> lines;
  // inventory: TMUX-DTO-034
  final int width;
  // inventory: TMUX-DTO-035
  final int height;
  // inventory: TMUX-DTO-036
  final bool hasAnsiColors;

  const TmuxPaneContent({
    required this.lines,
    required this.width,
    required this.height,
    this.hasAnsiColors = false,
  });

  // inventory: TMUX-DTO-037
  /// プレーンテキストを取得
  String get plainText {
    if (!hasAnsiColors) {
      return lines.join('\n');
    }
    return lines.map(_stripAnsiCodes).join('\n');
  }

  // inventory: TMUX-DTO-038
  /// 生のテキストを取得（ANSIコード含む）
  String get rawText => lines.join('\n');

  // inventory: TMUX-DTO-039
  /// 空かどうか
  bool get isEmpty => lines.isEmpty || lines.every((line) => line.trim().isEmpty);

  @override
  // inventory: TMUX-DTO-040
  String toString() => 'TmuxPaneContent(${width}x$height, ${lines.length} lines)';
}

// inventory: TMUX-DTO-050
/// pollPane 結果用スナップショット
class TmuxPaneSnapshot {
  // inventory: TMUX-DTO-051
  final TmuxPaneContent content;
  // inventory: TMUX-DTO-052
  final int cursorX;
  // inventory: TMUX-DTO-053
  final int cursorY;
  // inventory: TMUX-DTO-054
  final int paneWidth;
  // inventory: TMUX-DTO-055
  final int paneHeight;
  // inventory: TMUX-DTO-056
  final String paneMode;

  const TmuxPaneSnapshot({
    required this.content,
    required this.cursorX,
    required this.cursorY,
    required this.paneWidth,
    required this.paneHeight,
    required this.paneMode,
  });

  // inventory: TMUX-DTO-057
  @override
  String toString() =>
      'TmuxPaneSnapshot(${paneWidth}x$paneHeight, cursor=$cursorX,$cursorY, mode=$paneMode)';
}

// ===== 後方互換性のためのエイリアス =====

// inventory: TMUX-TYPE-001
@Deprecated("Use TmuxSession instead")
/// @deprecated Use [TmuxSession] instead
typedef TmuxSessionInfo = TmuxSession;

// inventory: TMUX-TYPE-002
@Deprecated("Use TmuxWindow instead")
/// @deprecated Use [TmuxWindow] instead
typedef TmuxWindowInfo = TmuxWindow;

// inventory: TMUX-TYPE-003
@Deprecated("Use TmuxPane instead")
/// @deprecated Use [TmuxPane] instead
typedef TmuxPaneInfo = TmuxPane;
