import '../../../services/backend/domain/multiplexer_pane.dart';
import '../../../services/backend/domain/multiplexer_backend.dart';
import '../../../services/backend/domain/multiplexer_session.dart';
import '../../../services/backend/domain/multiplexer_window.dart';
import '../../../services/herdr/herdr_to_domain.dart';
import '../../../services/tmux/commands/layout.dart';
import 'herdr_sync.dart';
import 'herdr_types.dart';

/// セレクタの選択コミットと indicator 更新（C3/C4 の commit 側）。
///
/// すべて [HerdrHost.switchTarget]（切替コミット単一入口・T6）で確定し、
/// 表示最終確定後（switch コミット後）に [HerdrHost.setIndicatorData] を呼ぶ
/// （CRITICAL-1: switch 前に呼ぶと旧値で stale になる）。
class HerdrSelectorCommitter {
  HerdrSelectorCommitter(this._host, this._sync, this._actions);

  final HerdrHost _host;
  final HerdrSyncFlow _sync;
  final HerdrDialogActions _actions;

  /// workspace 選択（Select Session 相当）。
  void selectWorkspace(
    List<MultiplexerSession> sessions,
    MultiplexerSession workspace,
  ) {
    final target = _sync.resolveWorkspaceTarget(sessions, workspace);
    if (target == null) return;
    _host.switchTarget(
      target.paneId,
      workspaceLabel: workspace.name,
      workspaceId: target.workspaceId,
      tabId: target.tabId,
      tabLabel: target.tabLabel,
    );
    _host.setIndicatorData(sessions);
  }

  /// tab 選択（Select Window 相当）: その tab のフォーカス pane へ切替える。
  void selectTab(
    List<MultiplexerSession> sessions,
    MultiplexerSession workspace,
    MultiplexerWindow tab,
  ) {
    final pane =
        tab.panes.where((p) => p.active).firstOrNull ?? tab.panes.firstOrNull;
    if (pane == null) return;
    final target = _sync.resolvedTargetOf(sessions, pane);
    _host.switchTarget(
      target.paneId,
      workspaceLabel: workspace.name,
      workspaceId: target.workspaceId,
      tabId: target.tabId,
      tabLabel: target.tabLabel,
    );
    _host.setIndicatorData(sessions);
  }

  /// pane 選択（Select Pane 相当）。
  void selectPane(
    List<MultiplexerSession> sessions,
    MultiplexerSession workspace,
    MultiplexerPane pane,
  ) {
    final target = _sync.resolvedTargetOf(sessions, pane);
    _host.switchTarget(
      target.paneId,
      workspaceLabel: workspace.name,
      workspaceId: target.workspaceId,
      tabId: target.tabId,
      tabLabel: target.tabLabel,
    );
    _host.setIndicatorData(sessions);
  }

  /// プレビュー内タップ: 引当できる pane なら選択（T10）。
  void selectOrSplitPane(List<MultiplexerSession> sessions, String paneId) {
    final pane = _sync.findPane(sessions, paneId);
    if (pane == null) return;
    final workspace = _sync.findWorkspace(sessions, _host.display);
    if (workspace == null) return;
    selectPane(sessions, workspace, pane);
  }

  /// 表示中の workspace / tab 引き当て（T4）。
  MultiplexerSession? findWorkspace(List<MultiplexerSession> sessions) =>
      _sync.findWorkspace(sessions, _host.display);

  MultiplexerWindow? findWindow(
    List<MultiplexerSession> sessions,
    HerdrDisplayData? display,
  ) => _sync.findWindow(findWorkspace(sessions), display);

  // ---- ダイアログ起動（resize・crud フローへの委譲） ----

  void showResizePaneChooser(
    List<MultiplexerSession> sessions,
    MultiplexerWindow window,
  ) => _actions.showResizePaneChooser(sessions, window);

  void showResizeTerminal() => _actions.showResizeTerminal();

  void showCreateTabDialog(MultiplexerSession workspace) =>
      _actions.showCreateTabDialog(workspace);

  void showRenameTabDialog(
    MultiplexerSession workspace,
    MultiplexerWindow tab,
  ) => _actions.showRenameTabDialog(workspace, tab);

  void confirmAndCloseTab({
    required MultiplexerSession workspace,
    required MultiplexerWindow tab,
    required bool isLastTab,
  }) => _actions.confirmCloseTab(
    workspace: workspace,
    tab: tab,
    isLastTab: isLastTab,
  );

  void confirmAndKillPane({
    required String paneId,
    required String paneTitle,
    required bool isLastPane,
    required bool isLastTab,
  }) => _actions.confirmKillPane(
    paneId: paneId,
    paneTitle: paneTitle,
    isLastPane: isLastPane,
    isLastTab: isLastTab,
  );

  void splitPaneAt(String paneId, SplitDirection direction) =>
      _actions.splitPane(paneId, direction);

  // ---- indicator（CRITICAL-1・🤝#3: 新規タイマーなし） ----

  /// ポーリング駆動の pane indicator 再設定。
  /// 取得失敗は静かにスキップ。await 中に切替・再解決が起きた場合は破棄。
  Future<void> refreshIndicatorFromCache() async {
    if (_host.backendKind != MultiplexerBackendKind.herdr) return;
    final cache = _host.snapshotCache;
    if (cache == null) return;
    final identity = _host.captureIdentity();
    try {
      final snapshot = await cache.get();
      if (_host.isDisposed) return;
      if (!_host.isCurrentIdentity(identity)) return;
      _host.setIndicatorData(snapshot.toDomainSessions());
    } catch (_) {
      // 取得失敗は既存 poll エラー処理に委ねる（ここでは SnackBar 等を出さない）。
    }
  }
}
