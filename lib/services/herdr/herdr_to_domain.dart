import '../backend/domain/multiplexer_pane.dart';
import '../backend/domain/multiplexer_session.dart';
import '../backend/domain/multiplexer_window.dart';
import 'herdr_models.dart';

/// [HerdrSnapshot] を共通 domain の [MultiplexerSession] 一覧に変換する。
///
/// 互換マッピング:
/// - workspace → session（name=label（空なら id）, id=workspace_id,
///   windowCount=tab_count, attached=focused, windows=tabs）
/// - tab → window（index=number, id=tab_id, name=label（null なら id）,
///   active=focused, paneCount=pane_count, panes）
/// - pane → pane（index=pane_id から数値抽出（不能ならリスト順）,
///   id=pane_id, active=focused, currentPath=cwd ?? foreground_cwd）
///
/// 既存の herdr モデルは変更しない（変換はこの拡張側で吸収する）。
extension HerdrSnapshotDomainMapping on HerdrSnapshot {
  List<MultiplexerSession> toDomainSessions() {
    return workspaces.map((workspace) {
      final tabs = tabsFor(workspace);
      return MultiplexerSession(
        name: workspace.label.isEmpty ? workspace.id : workspace.label,
        id: workspace.id,
        windowCount: workspace.tabCount,
        attached: workspace.focused,
        windows: tabs.map((tab) {
          final panes = panesFor(tab);
          return MultiplexerWindow(
            index: tab.number,
            id: tab.id,
            name: tab.label ?? tab.id,
            active: tab.focused,
            paneCount: tab.paneCount,
            panes: panes
                .map(
                  (pane) => MultiplexerPane(
                    index: _paneIndexFromId(pane.id, panes.indexOf(pane)),
                    id: pane.id,
                    active: pane.focused,
                    currentPath: pane.cwd ?? pane.foregroundCwd,
                  ),
                )
                .toList(),
          );
        }).toList(),
      );
    }).toList();
  }
}

/// pane ID（例: "w1:p1" / "w1:t1:p2"）の末尾セグメントから数値を抽出する。
///
/// 数値を抽出できない場合は [fallback]（リスト順）を返す。
int _paneIndexFromId(String paneId, int fallback) {
  final last = paneId.split(':').last;
  final digits = last.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? fallback : (int.tryParse(digits) ?? fallback);
}
