import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../services/backend/domain/multiplexer_backend.dart';
import '../../../services/backend/domain/multiplexer_session.dart';
import '../../../services/backend/domain/multiplexer_window.dart';
import '../../../services/backend/domain/pane_writer.dart';
import 'herdr_selectors_commit.dart';
import 'herdr_sync.dart';
import 'herdr_types.dart';

/// herdr の workspace/tab/pane セレクタのシート内容構築（C3 自領域）。
///
/// データソースは [HerdrSyncFlow.fetchHerdrSessions] の共通ヘルパー。表示・
/// 閉じ（`_closeSelectorThen` 200ms・`mux-sel-*` Key・文言）は
/// [HerdrSheetHost]（ui 実装）へ委譲し、選択は [HerdrSelectorCommitter] が
/// [HerdrHost.switchTarget]（切替コミット単一入口）で確定する。
class HerdrSelectorPresenter {
  HerdrSelectorPresenter(this._host, this._commit);

  final HerdrHost _host;
  final HerdrSelectorCommitter _commit;

  /// workspace セレクタ（Select Session 相当・選択即閉じ・T10 / A6 / T4）。
  ///
  /// Resize 導線（ユーザー指示）: ターミナル全体の絶対サイズ変更
  /// （[_resizeTerminal] 相当）をヘッダーに提供する。
  void showWorkspaceSelector() {
    if (!_host.isMounted || _host.isDisposed) return;
    if (_host.backendKind != MultiplexerBackendKind.herdr) return;
    _host.sheetHost?.show(
      title: _host.context.l10n.termSelectSession,
      icon: Icons.folder,
      load: () async {
        final l10n = _host.context.l10n;
        final sessions = await _host.fetchHerdrSessions(
          force: false,
          eventLabel: 'selector snapshot',
          isTerminal: false,
        );
        if (sessions == null) throw StateError('Failed to load herdr tree');
        final canResize = _host.can(const PaneCapabilities(resize: true));
        return HerdrSheetContent(
          headerActions: [
            if (canResize)
              HerdrSheetHeaderAction(
                icon: Icons.open_in_full,
                tooltip: l10n.termResizeTerminal,
                onPressed: () => _closeThen(_commit.showResizeTerminal),
              ),
          ],
          tiles: [
            for (final session in sessions)
              HerdrSheetTile(
                key: ValueKey('mux-sel-session-${session.name}'),
                session: session,
                isActive: _isCurrentSession(session),
                onTap: () {
                  Navigator.pop(_host.context);
                  _commit.selectWorkspace(sessions, session);
                },
              ),
          ],
        );
      },
    );
  }

  /// tab セレクタ（Select Window 相当・選択即閉じ・T10 / A6 / T4）。
  void showTabSelector() {
    if (!_host.isMounted || _host.isDisposed) return;
    if (_host.backendKind != MultiplexerBackendKind.herdr) return;
    _host.sheetHost?.show(
      title: _host.context.l10n.termSelectWindow,
      icon: Icons.tab,
      load: () async {
        final l10n = _host.context.l10n;
        final sessions = await _host.fetchHerdrSessions(
          force: false,
          eventLabel: 'selector snapshot',
          isTerminal: false,
        );
        if (sessions == null) throw StateError('Failed to load herdr tree');

        final workspace = _commit.findWorkspace(sessions);
        if (workspace == null) throw StateError('No workspace found');

        final canTabCrud = _host.can(const PaneCapabilities(tabCrud: true));
        final canRename = _host.can(const PaneCapabilities(rename: true));
        return HerdrSheetContent(
          headerActions: [
            if (canTabCrud && workspace.id != null)
              HerdrSheetHeaderAction(
                icon: Icons.add,
                tooltip: l10n.termNewTab,
                onPressed: () =>
                    _closeThen(() => _commit.showCreateTabDialog(workspace)),
              ),
          ],
          tiles: [
            for (final window in workspace.windows)
              HerdrSheetTile(
                key: ValueKey('mux-sel-window-${window.id ?? window.index}'),
                window: window,
                isActive: _isCurrentWindow(window),
                onTap: () {
                  Navigator.pop(_host.context);
                  _commit.selectTab(sessions, workspace, window);
                },
                onRename: canRename && window.id != null
                    ? () => _closeThen(
                        () => _commit.showRenameTabDialog(workspace, window),
                      )
                    : null,
                onClose: canTabCrud && window.id != null
                    ? () => _closeThen(
                        () => _commit.confirmAndCloseTab(
                          workspace: workspace,
                          tab: window,
                          isLastTab: workspace.windows.length == 1,
                        ),
                      )
                    : null,
              ),
          ],
        );
      },
    );
  }

  /// pane セレクタ（Select Pane 相当・選択即閉じ・T10 / A6 / T4）。
  void showPaneSelector() {
    if (!_host.isMounted || _host.isDisposed) return;
    if (_host.backendKind != MultiplexerBackendKind.herdr) return;
    _host.sheetHost?.show(
      title: _host.context.l10n.termSelectPane,
      icon: Icons.terminal,
      topExpected: true,
      load: () async {
        final l10n = _host.context.l10n;
        final sessions = await _host.fetchHerdrSessions(
          force: false,
          eventLabel: 'selector snapshot',
          isTerminal: false,
        );
        if (sessions == null) throw StateError('Failed to load herdr tree');

        final display = _host.display;
        final workspace = _commit.findWorkspace(sessions);
        final window = _commit.findWindow(sessions, display);
        if (workspace == null || window == null) {
          throw StateError('No workspace/tab found');
        }

        final canResize = _host.can(const PaneCapabilities(resize: true));
        final canClose = _host.can(const PaneCapabilities(close: true));
        final canSplit = _host.can(const PaneCapabilities(split: true));
        return HerdrSheetContent(
          headerActions: [
            if (canResize)
              HerdrSheetHeaderAction(
                icon: Icons.open_in_full,
                tooltip: l10n.termResizePane,
                onPressed: () => _closeThen(
                  () => _commit.showResizePaneChooser(sessions, window),
                ),
              ),
          ],
          top: HerdrSheetTopData(
            window: window,
            activePaneId: _host.paneId,
            onSelectPane: (paneId) {
              Navigator.pop(_host.context);
              _commit.selectOrSplitPane(sessions, paneId);
            },
            onSplitPane: canSplit
                ? (paneId, direction) {
                    // HEAD 同等: シートを即座に閉じて split を即時発行する
                    // （_closeThen の 200ms 待ちは行わない・Q-02）。
                    Navigator.pop(_host.context);
                    _commit.splitPaneAt(paneId, direction);
                  }
                : null,
          ),
          tiles: [
            for (final pane in window.panes)
              HerdrSheetTile(
                key: ValueKey('mux-sel-pane-${pane.id}'),
                pane: pane,
                title: herdrPaneLabel(pane, l10n),
                isActive: pane.id == _host.paneId,
                onTap: () {
                  Navigator.pop(_host.context);
                  _commit.selectPane(sessions, workspace, pane);
                },
                onLongPress: canClose
                    ? () => _closeThen(
                        () => _commit.confirmAndKillPane(
                          paneId: pane.id,
                          paneTitle: herdrPaneLabel(pane, l10n),
                          isLastPane: window.panes.length == 1,
                          isLastTab: workspace.windows.length == 1,
                        ),
                      )
                    : null,
                onResize: canResize
                    ? () => _closeThen(
                        () => _commit.showResizePaneChooser(sessions, window),
                      )
                    : null,
                onClose: canClose
                    ? () => _closeThen(
                        () => _commit.confirmAndKillPane(
                          paneId: pane.id,
                          paneTitle: herdrPaneLabel(pane, l10n),
                          isLastPane: window.panes.length == 1,
                          isLastTab: workspace.windows.length == 1,
                        ),
                      )
                    : null,
              ),
          ],
        );
      },
    );
  }

  /// シートを閉じてから mutation アクションを起動する（HEAD `_closeSelectorThen`
  /// と同一の「pop → 200ms 待ち → 起動」順を維持する。ダイアログ表示前にシート
  /// の dismiss アニメーションを開始させる）。
  void _closeThen(VoidCallback action) {
    Navigator.pop(_host.context);
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (_host.isMounted && !_host.isDisposed) action();
    });
  }

  /// 現在表示中 workspace / tab / pane の id（H-1 ハイライト判定用）。
  String? get contextSessionId => _host.display?.workspaceId;
  String? get contextSessionLabel => _host.display?.workspaceLabel;
  String? get contextTabId => _host.display?.tabId;

  /// H-1: セッションのハイライト（HEAD `_isCurrentSession` と同一）。
  ///
  /// 一義的な基準は現在の session ID との一致。sessionId 不明時のみ
  /// 名前一致（旧挙動）へフォールバックする。pane ID の所属判定も行う。
  bool _isCurrentSession(MultiplexerSession session) {
    final currentSessionId = contextSessionId;
    final sessionId = session.id;
    if (currentSessionId != null && currentSessionId.isNotEmpty) {
      if (sessionId != null && sessionId == currentSessionId) return true;
      final paneId = _host.paneId;
      if (paneId != null &&
          sessionId != null &&
          paneId.startsWith('$sessionId:')) {
        return true;
      }
      return false;
    }
    if (session.name == contextSessionLabel) return true;
    final paneId = _host.paneId;
    return sessionId != null &&
        paneId != null &&
        paneId.startsWith('$sessionId:');
  }

  /// H-1: ウィンドウのハイライト（HEAD `_isCurrentWindow` と同一）。
  ///
  /// [contextTabId] が判明している場合は ID 一致のみで判定する。
  bool _isCurrentWindow(MultiplexerWindow window) {
    final currentWindowId = contextTabId;
    if (currentWindowId != null && currentWindowId.isNotEmpty) {
      return window.id == currentWindowId;
    }
    return window.id == currentWindowId;
  }
}
