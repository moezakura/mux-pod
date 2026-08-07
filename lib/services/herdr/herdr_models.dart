// inventory: HERDR-MODELS-000
/// herdr DTO（read-only 表示用）。
///
/// ID 形式: workspace=`wN` / tab=`wN:tN` / pane=`wN:tN:pN`（G4 実測）。
/// 本 milestone は read-only 接続のみ公開し、mutation コマンドは実装しない
/// （G6 合意#3 に基づく公開範囲）。
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

  const HerdrSnapshot({
    this.protocol = 0,
    this.version = '',
    this.focusedWorkspaceId,
    this.focusedTabId,
    this.focusedPaneId,
    this.workspaces = const [],
    this.tabs = const [],
    this.panes = const [],
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
