// inventory: HERDR-RESOLVER-000
/// herdr スナップショットから表示対象 pane ID を解決する純粋関数。
///
/// 決定層（決定 = どの pane を表示するか）を画面ロジックから分離し、
/// 単体テスト可能にする。throw しない同期純関数。
/// 優先順は既存 `_resolveHerdrPaneId`（terminal_screen.dart）から移設した。
library;

import 'herdr_models.dart';

// inventory: HERDR-RESOLVER-001
/// スナップショット + 要求 → 表示対象 pane ID の解決。
///
/// 優先順:
/// 1. [paneIds] の先頭から順に、スナップショットに存在する最初の pane ID
/// 2. workspace の決定:
///    - [workspaceId] が指定されていて存在すればそれを採用
///    - 無ければ [workspaceLabel]（label 一致 → id 一致）で採用
///    - それも無ければ先頭 workspace
/// 3. tab の決定（workspace 配下）:
///    - [tabId] が指定されていて存在すればそれを採用
///    - 無ければ workspace のフォーカス tab → 先頭 tab
/// 4. 対象 tab 内: フォーカス pane → 先頭 pane
/// 5. workspace 内フォールバック: フォーカス pane → 先頭 pane
/// 6. 全体フォールバック: snapshot.focusedPaneId → 先頭 pane
/// 7. すべて空なら null
class HerdrTargetResolver {
  HerdrTargetResolver._();

  /// [snapshot] から表示対象の pane ID を解決する（無ければ null）。
  static String? resolve(
    HerdrSnapshot snapshot, {
    Iterable<String> paneIds = const [],
    String? workspaceId,
    String? tabId,
    String? workspaceLabel,
  }) {
    // 1. 直接 pane 指定（initialPaneId / lastPaneId 相当・順序優先）
    for (final id in paneIds) {
      if (_containsPane(snapshot, id)) return id;
    }

    final workspaces = snapshot.workspaces;
    if (workspaces.isEmpty) return null;

    // 2. workspace 決定
    final HerdrWorkspace? workspace;
    if (workspaceId != null) {
      workspace = workspaces
          .where((w) => w.id == workspaceId)
          .firstOrNull;
    } else if (workspaceLabel != null && workspaceLabel.isNotEmpty) {
      // label 一致 → id 一致（既存は label が空なら id を name として比較）
      workspace =
          workspaces.where((w) => w.label == workspaceLabel).firstOrNull ??
              workspaces.where((w) => w.id == workspaceLabel).firstOrNull;
    } else {
      workspace = null;
    }
    final targetWorkspace = workspace ?? workspaces.firstOrNull;
    if (targetWorkspace == null) return null;

    // 3. tab 決定
    final tabs = snapshot.tabsFor(targetWorkspace);
    final HerdrTab? targetTab;
    if (tabId != null) {
      targetTab = tabs.where((t) => t.id == tabId).firstOrNull;
    } else {
      targetTab = tabs.where((t) => t.focused).firstOrNull ?? tabs.firstOrNull;
    }

    // 4. 対象 tab 内の pane
    if (targetTab != null) {
      final panes = snapshot.panesFor(targetTab);
      final focused = panes.where((p) => p.focused).firstOrNull;
      if (focused != null) return focused.id;
      if (panes.isNotEmpty) return panes.first.id;
    }

    // 5. workspace 内フォールバック（tab 解決不能・tab 内が空のとき）
    final workspacePanes =
        snapshot.panes.where((p) => p.workspaceId == targetWorkspace.id);
    final workspaceFocused = workspacePanes.where((p) => p.focused).firstOrNull;
    if (workspaceFocused != null) return workspaceFocused.id;
    final firstWorkspacePane = workspacePanes.firstOrNull;
    if (firstWorkspacePane != null) return firstWorkspacePane.id;

    // 6. 全体フォールバック
    if (snapshot.focusedPaneId != null &&
        _containsPane(snapshot, snapshot.focusedPaneId!)) {
      return snapshot.focusedPaneId;
    }
    return snapshot.panes.isEmpty ? null : snapshot.panes.first.id;
  }

  static bool _containsPane(HerdrSnapshot snapshot, String paneId) =>
      snapshot.panes.any((p) => p.id == paneId);
}
