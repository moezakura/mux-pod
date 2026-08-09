// inventory: HERDR-MODELS-000
/// herdr DTO（表示 + mutation 応答用）。
///
/// ID 形式: workspace=`wN` / tab=`wN:tN` / pane=`wN:tN:pN`（G4 実測）。
/// mutation 対応（send-text / send-keys / focus / split / close / zoom /
/// resize / rename / tab・workspace CRUD 等）は実装・公開済み
/// （G6 合意#3 改訂: herdr read-only → 全 mutation 解禁・Q-01 の 1 回
/// リリース）。read-only 記述は廃止。
library;

// inventory: HERDR-MODELS-STATUS-001
/// `herdr status --json` の結果。
class HerdrStatus {
  /// CLI（client）のバージョン。
  final String? clientVersion;

  /// CLI（client）の protocol 番号。
  final int clientProtocol;

  /// サーバのバージョン。
  final String? serverVersion;

  /// サーバの protocol 番号。
  final int serverProtocol;

  /// サーバの状態文字列（"running" 等）。
  final String? serverStatus;

  /// サーバが稼働中かどうか。
  final bool running;

  /// client/server が互換かどうか。
  final bool compatible;

  /// サーバの socket パス。
  final String? socket;

  const HerdrStatus({
    this.clientVersion,
    this.clientProtocol = 0,
    this.serverVersion,
    this.serverProtocol = 0,
    this.serverStatus,
    this.running = false,
    this.compatible = false,
    this.socket,
  });
}

// inventory: HERDR-MODELS-WS-001
/// herdr workspace（tmux session 相当）。
class HerdrWorkspace {
  /// workspace ID（例: "w1"）。
  final String id;

  /// 表示ラベル（例: "lab-ws1"）。
  final String label;

  /// 1 始まりの番号。
  final int number;

  /// フォーカス中かどうか。
  final bool focused;

  /// agent 状態（"unknown" 等）。
  final String agentStatus;

  /// 配下の pane 数。
  final int paneCount;

  /// 配下の tab 数。
  final int tabCount;

  /// アクティブな tab ID（例: "w1:t1"）。
  final String? activeTabId;

  const HerdrWorkspace({
    required this.id,
    required this.label,
    this.number = 0,
    this.focused = false,
    this.agentStatus = 'unknown',
    this.paneCount = 0,
    this.tabCount = 0,
    this.activeTabId,
  });
}

// inventory: HERDR-MODELS-TAB-001
/// herdr tab（tmux window 相当）。
class HerdrTab {
  /// tab ID（例: "w1:t1"）。
  final String id;

  /// 属する workspace ID（例: "w1"）。
  final String workspaceId;

  /// 表示ラベル（snapshot では番号の文字列 "1" 等）。
  final String? label;

  /// 1 始まりの番号。
  final int number;

  /// フォーカス中かどうか。
  final bool focused;

  /// agent 状態（"unknown" 等）。
  final String agentStatus;

  /// 配下の pane 数。
  final int paneCount;

  const HerdrTab({
    required this.id,
    required this.workspaceId,
    this.label,
    this.number = 0,
    this.focused = false,
    this.agentStatus = 'unknown',
    this.paneCount = 0,
  });
}

// inventory: HERDR-MODELS-PANE-001
/// herdr pane（tmux pane 相当）。
class HerdrPane {
  /// pane ID（例: "w1:p1"）。
  final String id;

  /// 属する workspace ID（例: "w1"）。
  final String workspaceId;

  /// 属する tab ID（例: "w1:t1"）。
  final String tabId;

  /// フォーカス中かどうか。
  final bool focused;

  /// agent 状態（"unknown" 等）。
  final String agentStatus;

  /// プロセスのカレントディレクトリ。
  final String? cwd;

  /// フォアグラウンドプロセスのカレントディレクトリ。
  final String? foregroundCwd;

  /// 内容のリビジョン（layout 用。内容変更では増えないため競合検出には使えない）。
  final int revision;

  /// 内部ターミナル ID。
  final String? terminalId;

  const HerdrPane({
    required this.id,
    required this.workspaceId,
    required this.tabId,
    this.focused = false,
    this.agentStatus = 'unknown',
    this.cwd,
    this.foregroundCwd,
    this.revision = 0,
    this.terminalId,
  });
}

// inventory: HERDR-MODELS-RECT-001
/// 矩形（絶対座標）。
///
/// layout の `area` / pane の `rect` / split の `rect` に共通。座標・サイズは
/// 文字セル単位（T0 実測⑥）。
class HerdrRect {
  /// 左端 X（0 始まり）。
  final int x;

  /// 上端 Y（0 始まり）。
  final int y;

  /// 幅（文字セル数）。
  final int width;

  /// 高さ（文字セル数）。
  final int height;

  const HerdrRect({
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
  });
}

// inventory: HERDR-MODELS-LAYOUT-PANE-001
/// layout 内の pane エントリ。
class HerdrLayoutPane {
  /// pane ID（例: "w1:p1"）。
  final String paneId;

  /// フォーカス中かどうか。
  final bool focused;

  /// 表示領域（絶対座標）。
  final HerdrRect rect;

  const HerdrLayoutPane({
    required this.paneId,
    this.focused = false,
    this.rect = const HerdrRect(),
  });
}

// inventory: HERDR-MODELS-LAYOUT-SPLIT-001
/// layout 内の split ノード。
class HerdrLayoutSplit {
  /// 分割方向（`'right'` / `'down'`）。
  final String direction;

  /// split ID（例: "split_0_root" / "split_1_0"）。
  final String id;

  /// 分割比（0.0-1.0。浮動小数のまま保持）。
  final double ratio;

  /// 分割領域（絶対座標）。
  final HerdrRect rect;

  const HerdrLayoutSplit({
    required this.direction,
    required this.id,
    this.ratio = 0,
    this.rect = const HerdrRect(),
  });
}

// inventory: HERDR-MODELS-LAYOUT-001
/// タブ単位のレイアウト。
///
/// `herdr api snapshot` の `layouts[]` と、resize/zoom/focus/edges の mutation
/// 応答内 `layout` に共通で現れる（T0 実測⑥）。zoom on 時は `zoomed` が true に
/// なるが pane の `rect` 自体は非 zoom 時の値のまま（T0 実測 6-b）。
class HerdrLayout {
  /// タブ全体の表示領域。
  final HerdrRect area;

  /// 当該タブのフォーカス pane ID。
  final String? focusedPaneId;

  /// pane 一覧（各 pane の絶対座標 rect）。
  final List<HerdrLayoutPane> panes;

  /// split ツリー。
  final List<HerdrLayoutSplit> splits;

  /// 属する tab ID（例: "w1:t1"）。
  final String? tabId;

  /// 属する workspace ID（例: "w1"）。
  final String? workspaceId;

  /// zoom 状態。
  final bool zoomed;

  const HerdrLayout({
    this.area = const HerdrRect(),
    this.focusedPaneId,
    this.panes = const [],
    this.splits = const [],
    this.tabId,
    this.workspaceId,
    this.zoomed = false,
  });

  // inventory: HERDR-MODELS-LAYOUT-002
  /// [paneId] の表示領域（無ければ null）。
  HerdrRect? rectFor(String paneId) {
    for (final pane in panes) {
      if (pane.paneId == paneId) return pane.rect;
    }
    return null;
  }
}

// inventory: HERDR-MODELS-SNAPSHOT-001
/// `herdr api snapshot` の結果（全階層）。
class HerdrSnapshot {
  /// protocol 番号（17 がサポート対象）。
  final int protocol;

  /// herdr のバージョン（例: "0.7.5"）。
  final String version;

  /// フォーカス中の workspace ID。
  final String? focusedWorkspaceId;

  /// フォーカス中の tab ID。
  final String? focusedTabId;

  /// フォーカス中の pane ID。
  final String? focusedPaneId;

  /// workspace 一覧。
  final List<HerdrWorkspace> workspaces;

  /// tab 一覧。
  final List<HerdrTab> tabs;

  /// pane 一覧。
  final List<HerdrPane> panes;

  /// tab 単位のレイアウト一覧。
  final List<HerdrLayout> layouts;

  const HerdrSnapshot({
    this.protocol = 0,
    this.version = '',
    this.focusedWorkspaceId,
    this.focusedTabId,
    this.focusedPaneId,
    this.workspaces = const [],
    this.tabs = const [],
    this.panes = const [],
    this.layouts = const [],
  });

  // inventory: HERDR-MODELS-SNAPSHOT-002
  /// [workspace] に属する tab を返す。
  List<HerdrTab> tabsFor(HerdrWorkspace workspace) =>
      tabs.where((t) => t.workspaceId == workspace.id).toList();

  // inventory: HERDR-MODELS-SNAPSHOT-003
  /// [tab] に属する pane を返す。
  List<HerdrPane> panesFor(HerdrTab tab) =>
      panes.where((p) => p.tabId == tab.id).toList();
}

// inventory: HERDR-MODELS-PANE-CONTENT-001
/// `herdr pane read` の結果。
///
/// 出力はプレーンテキスト（`--source visible|recent`）または ANSI エスケープ
/// 付き（`--raw`）のいずれも、行分割と生文字列の両方を保持する。
class HerdrPaneContent {
  /// 行ごとの内容（末尾の改行は除去済み）。
  final List<String> lines;

  /// 生のテキスト（ANSI エスケープを含む場合あり）。
  final String rawText;

  /// ANSI エスケープを含むかどうか。
  final bool hasAnsi;

  const HerdrPaneContent({
    required this.lines,
    required this.rawText,
    this.hasAnsi = false,
  });

  /// 空かどうか。
  bool get isEmpty => lines.isEmpty || lines.every((line) => line.trim().isEmpty);

  @override
  String toString() =>
      'HerdrPaneContent(${lines.length} lines, ansi: $hasAnsi)';
}
