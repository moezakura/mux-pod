import '../../../services/herdr/herdr_commands.dart';
import '../../../services/herdr/herdr_models.dart';
import '../../../services/herdr/herdr_target_resolver.dart';
import '../../../services/ssh/ssh_client.dart';
import 'herdr_types.dart';

/// セッション確立・初回解決（B 群の実装）。
///
/// controller からのみ呼ばれる。直接の state 書き込みは host 経由で行う。
class HerdrSetupFlow {
  HerdrSetupFlow(this._host);

  final HerdrHost _host;

  /// herdr のセッションを設定する。
  ///
  /// 表示対象 pane を解決し、ライブポーリングを開始する。mutation 系の tmux
  /// セットアップは一切行わない。stale tmuxProvider 対策（T9・R3）として
  /// 冒頭で tmuxProvider をクリアする。
  Future<void> setupSession(SshClient client) async {
    _host.clearTmuxProvider();
    // 再接続時 stale 防止（MED-4）: indicator データを null に戻してから再解決。
    _host.indicatorNotifier.value = null;
    _host.recreateReaders();

    // 表示対象 pane を解決（直接指定 or スナップショットから）。
    final directId = _host.initialPaneId ?? _host.lastPaneId;
    final resolvedTarget = directId == null ? await resolvePaneId() : null;
    final resolvedId = resolvedTarget?.paneId ?? directId;
    if (resolvedId == null) {
      _host.recordSwitchEvent(
        'initial resolve failed: no pane found '
        '(sessionId=${_host.sessionId ?? '<null>'}, '
        'label=${_host.workspaceLabel ?? '<null>'}, directId=$directId)',
      );
      throw Exception('No herdr pane found for this workspace');
    }

    _host.setTargetPaneId(resolvedId);

    _host.displayNotifier.value = HerdrDisplayData(
      workspaceLabel: _host.workspaceLabel,
      workspaceId: resolvedTarget?.workspaceId ?? resolvedId.split(':').first,
      tabId: resolvedTarget?.tabId ?? herdrTabIdFromPaneId(resolvedId),
      tabLabel: resolvedTarget?.tabLabel,
      paneId: resolvedId,
    );

    final indicatorSessions = await _host.fetchHerdrSessions(
      force: false,
      eventLabel: 'initial indicator',
      isTerminal: false,
    );
    _host.setIndicatorData(indicatorSessions);

    // ライブ表示を開始（view clear + 初回スクロールフラグ false は host）。
    _host.resetView();
    _host.startPolling();
  }

  /// herdr スナップショットから表示対象の pane を解決する。
  Future<HerdrResolvedTarget?> resolvePaneId() async {
    final cache = _host.snapshotCache;
    if (cache == null) {
      _host.recordSwitchEvent(
        'initial resolve failed: no snapshot cache '
        '(backendKind=${_host.backendKind}, '
        'hasPaneContentReader=${_host.hasInjectedPaneContentReader})',
      );
      return null;
    }
    final HerdrSnapshot snapshot;
    try {
      snapshot = await cache.get(force: true);
    } on HerdrCommandException catch (e) {
      _host.recordSwitchEvent(
        'initial resolve failed: snapshot fetch error '
        '(type=${e.runtimeType}, errorCode=${e.errorCode ?? '<null>'}, '
        'exitCode=${e.exitCode}, message=${e.message})',
      );
      return null;
    } on HerdrTargetNotFoundException catch (e) {
      _host.recordSwitchEvent(
        'initial resolve failed: target not found in snapshot '
        '(type=${e.runtimeType}, kind=${e.kind}, '
        'errorCode=${e.errorCode ?? '<null>'}, '
        'exitCode=${e.exitCode}, message=${e.message})',
      );
      return null;
    } catch (e) {
      _host.recordSwitchEvent(
        'initial resolve failed: unexpected error '
        '(type=${e.runtimeType}, error=$e)',
      );
      rethrow;
    }

    return resolvePaneIdFromSnapshot(snapshot);
  }

  /// [snapshot] から表示対象 pane を解決する（初回解決・再解決で共通）。
  HerdrResolvedTarget? resolvePaneIdFromSnapshot(
    HerdrSnapshot snapshot, {
    String? preferredPaneId,
  }) {
    final requestedId = _host.sessionId;
    final workspaceId =
        (requestedId != null &&
            requestedId.isNotEmpty &&
            snapshot.workspaces.any((w) => w.id == requestedId))
        ? requestedId
        : null;
    final paneId = HerdrTargetResolver.resolve(
      snapshot,
      paneIds: [
        if (preferredPaneId != null) preferredPaneId,
        if (_host.initialPaneId != null) _host.initialPaneId!,
        if (_host.lastPaneId != null) _host.lastPaneId!,
      ],
      workspaceId: workspaceId,
      workspaceLabel: _host.workspaceLabel,
    );
    if (paneId == null) {
      _host.recordSwitchEvent(
        'resolve failed: no pane in snapshot '
        '(workspaces=${snapshot.workspaces.length}, '
        'panes=${snapshot.panes.length}, '
        'sessionId=${_host.sessionId ?? '<null>'}, '
        'label=${_host.workspaceLabel ?? '<null>'}, '
        'requestedWorkspaceId=${workspaceId ?? '<null>'})',
      );
      return null;
    }
    final pane = snapshot.panes.where((p) => p.id == paneId).firstOrNull;
    final tab = pane?.tabId == null
        ? null
        : snapshot.tabs.where((t) => t.id == pane!.tabId).firstOrNull;
    return HerdrResolvedTarget(
      paneId: paneId,
      workspaceId: pane?.workspaceId,
      tabId: pane?.tabId,
      tabLabel: tab?.label,
    );
  }
}
