import '../../../l10n/l10n_ext.dart';
import '../../../services/backend/domain/multiplexer_pane.dart';
import '../../../services/backend/domain/multiplexer_session.dart';
import '../../../services/backend/domain/multiplexer_window.dart';
import '../../../services/backend/domain/pane_writer.dart';
import '../../../services/herdr/herdr_errors.dart';
import '../../../services/herdr/herdr_models.dart';
import '../../../services/herdr/herdr_to_domain.dart';
import '../../../providers/ssh_provider.dart';
import 'herdr_messages.dart';
import 'herdr_types.dart';

/// herdr の非同期フロー（ポーリング例外・再解決・再接続・mutation 後同期）。
///
/// **H5/T18 単一経路**: mutation 成功後の同期は全て [syncAfterMutation] に
/// 集約する（呼び漏れ・不整合防止）。fetch は [fetchHerdrSessions] に集約
/// （T5: 取得とエラー分類は共有ヘルパー）。
class HerdrSyncFlow {
  HerdrSyncFlow(this._host);

  final HerdrHost _host;

  /// herdr スナップショット取得の共有ヘルパー（T5 / M-3）。
  /// server-down は [handleServerDown]、終端（isTerminal）は
  /// [_notifyHerdrTargetLost]、セレクタ系は SnackBar 表示に倒す。
  Future<List<MultiplexerSession>?> fetchHerdrSessions({
    bool force = false,
    required String eventLabel,
    required bool isTerminal,
  }) async {
    final cache = _host.snapshotCache;
    if (cache == null) {
      _host.recordSwitchEvent('$eventLabel: no snapshot cache');
      if (isTerminal) notifyHerdrTargetLost();
      return null;
    }

    final HerdrSnapshot snapshot;
    try {
      snapshot = await cache.get(force: force);
    } catch (e) {
      if (!_host.isMounted || _host.isDisposed) return null;
      if (isServerDownException(e)) {
        _host.recordSwitchEvent('server-down detected (${e.runtimeType})');
        await handleServerDown(e);
      } else if (isTerminal) {
        _host.recordSwitchEvent('$eventLabel: snapshot fetch error');
        notifyHerdrTargetLost();
      } else {
        _host.recordSwitchEvent(
          '$eventLabel: snapshot fetch error (${e.runtimeType})',
        );
        herdrShowError(
          // ignore: use_build_context_synchronously
          _host.context,
          _host.context.l10n.termFailedToLoadHerdrTree(e.toString()),
          retry: _host.resumePolling,
        );
      }
      return null;
    }
    return snapshot.toDomainSessions();
  }

  /// ポーリング例外の種別分岐（A2 / R1）。
  Future<void> handlePollError(Object e) async {
    if (isHerdrTargetNotFound(e)) {
      _host.recordSwitchEvent('target-not-found detected (${e.runtimeType})');
      await handleTargetNotFound();
    } else if (isServerDownException(e)) {
      _host.recordSwitchEvent('server-down detected (${e.runtimeType})');
      await handleServerDown(e);
    } else {
      _host.recordSwitchEvent('poll error (${e.runtimeType})');
      if (!_host.isDisposed) {
        final currentState = _host.ref.read(sshProvider);
        if (!currentState.isReconnecting) {
          _host.attemptReconnect();
        }
      }
    }
  }

  /// target-not-found からの再解決とエスカレーション（A2）。
  Future<void> handleTargetNotFound() async {
    final sessions = await fetchHerdrSessions(
      force: true,
      eventLabel: 're-resolve failed',
      isTerminal: true,
    );
    if (sessions == null || !_host.isMounted || _host.isDisposed) return;

    final currentPaneId = _host.paneId;
    final resolved = resolveTargetFromSessions(
      sessions,
      preferredPaneId: currentPaneId,
    );
    if (resolved == null) {
      _host.recordSwitchEvent('re-resolve failed: target missing');
      _host.setIndicatorData(null);
      notifyHerdrTargetLost();
      return;
    }

    _host.recordSwitchEvent('re-resolve succeeded -> ${resolved.paneId}');
    if (resolved.paneId != currentPaneId) {
      _host.switchTarget(
        resolved.paneId,
        workspaceId: resolved.workspaceId,
        tabId: resolved.tabId,
        tabLabel: resolved.tabLabel,
      );
    }
    _host.setIndicatorData(sessions);
  }

  /// 再接続後のターゲット再解決（T9a）。継続可能なら true。
  Future<bool> reResolveAfterReconnect() async {
    final sessions = await fetchHerdrSessions(
      force: true,
      eventLabel: 're-resolve failed after reconnect',
      isTerminal: true,
    );
    if (sessions == null || !_host.isMounted || _host.isDisposed) return false;

    final currentPaneId = _host.paneId;
    final resolved = resolveTargetFromSessions(
      sessions,
      preferredPaneId: currentPaneId,
    );
    if (resolved == null) {
      _host.recordSwitchEvent(
        're-resolve failed after reconnect: target missing',
      );
      _host.setIndicatorData(null);
      notifyHerdrTargetLost();
      return false;
    }

    _host.recordSwitchEvent('re-resolve after reconnect -> ${resolved.paneId}');
    if (resolved.paneId != currentPaneId) {
      _host.switchTarget(
        resolved.paneId,
        workspaceId: resolved.workspaceId,
        tabId: resolved.tabId,
        tabLabel: resolved.tabLabel,
      );
    }
    _host.setIndicatorData(sessions);
    return true;
  }

  /// **H5/T18 単一経路**: mutation 成功後のツリー同期。
  Future<bool> syncAfterMutation({
    String eventLabel = 'mutation sync',
    HerdrSyncTargetPolicy policy = HerdrSyncTargetPolicy.preserveCurrent,
  }) async {
    final sessions = await fetchHerdrSessions(
      force: true,
      eventLabel: eventLabel,
      isTerminal: true,
    );
    if (sessions == null || !_host.isMounted || _host.isDisposed) return false;

    final currentPaneId = _host.paneId;
    var resolved = switch (policy) {
      HerdrSyncTargetPolicy.preserveCurrent => resolveTargetFromSessions(
        sessions,
        preferredPaneId: currentPaneId,
      ),
      HerdrSyncTargetPolicy.followBackendFocus =>
        resolveFocusedPaneFromSessions(sessions),
    };
    resolved ??= resolveTargetFromSessions(
      sessions,
      preferredPaneId: currentPaneId,
    );
    if (resolved == null) {
      _host.recordSwitchEvent('$eventLabel: no target remains');
      notifyHerdrTargetLost();
      return false;
    }

    if (resolved.paneId != currentPaneId) {
      _host.recordSwitchEvent('$eventLabel -> ${resolved.paneId}');
      _host.switchTarget(
        resolved.paneId,
        workspaceId: resolved.workspaceId,
        tabId: resolved.tabId,
        tabLabel: resolved.tabLabel,
      );
    }

    _host.setIndicatorData(sessions);
    _host.boostPolling();
    return true;
  }

  /// 共通 domain ツリーから表示対象 pane を再解決する（T5）。
  HerdrResolvedTarget? resolveTargetFromSessions(
    List<MultiplexerSession> sessions, {
    String? preferredPaneId,
  }) {
    for (final id in [preferredPaneId, _host.initialPaneId, _host.lastPaneId]) {
      if (id == null) continue;
      final pane = findPane(sessions, id);
      if (pane != null) return resolvedTargetOf(sessions, pane);
    }

    MultiplexerSession? workspace;
    final requestedId = _host.sessionId;
    if (requestedId != null && requestedId.isNotEmpty) {
      for (final session in sessions) {
        if (session.id == requestedId) {
          workspace = session;
          break;
        }
      }
    }
    if (workspace == null) {
      final label = _host.workspaceLabel;
      if (label != null && label.isNotEmpty) {
        for (final session in sessions) {
          if (session.name == label || session.id == label) {
            workspace = session;
            break;
          }
        }
      }
    }
    workspace ??= sessions.firstOrNull;
    if (workspace == null) return null;

    final focusedTab = workspace.windows.where((w) => w.active).firstOrNull;
    final tab = focusedTab ?? workspace.windows.firstOrNull;
    if (tab != null) {
      final focusedPane = tab.panes.where((p) => p.active).firstOrNull;
      if (focusedPane != null) {
        return resolvedTargetOf(sessions, focusedPane);
      }
      if (tab.panes.isNotEmpty) {
        return resolvedTargetOf(sessions, tab.panes.first);
      }
    }

    final workspacePanes = [for (final w in workspace.windows) ...w.panes];
    final workspaceFocused = workspacePanes.where((p) => p.active).firstOrNull;
    if (workspaceFocused != null) {
      return resolvedTargetOf(sessions, workspaceFocused);
    }
    if (workspacePanes.isNotEmpty) {
      return resolvedTargetOf(sessions, workspacePanes.first);
    }

    final allPanes = [
      for (final s in sessions)
        for (final w in s.windows) ...w.panes,
    ];
    final globalFocused = allPanes.where((p) => p.active).firstOrNull;
    if (globalFocused != null) {
      return resolvedTargetOf(sessions, globalFocused);
    }
    if (allPanes.isNotEmpty) {
      return resolvedTargetOf(sessions, allPanes.first);
    }
    return null;
  }

  /// [sessions] から [paneId] に一致する [MultiplexerPane] を引き当てる。
  MultiplexerPane? findPane(List<MultiplexerSession> sessions, String paneId) {
    for (final session in sessions) {
      for (final window in session.windows) {
        for (final pane in window.panes) {
          if (pane.id == paneId) return pane;
        }
      }
    }
    return null;
  }

  /// [pane] の属する workspace / tab の実値を [HerdrResolvedTarget] として返す。
  HerdrResolvedTarget resolvedTargetOf(
    List<MultiplexerSession> sessions,
    MultiplexerPane pane,
  ) {
    for (final session in sessions) {
      for (final window in session.windows) {
        if (window.panes.any((p) => p.id == pane.id)) {
          return HerdrResolvedTarget(
            paneId: pane.id,
            workspaceId: session.id ?? pane.id.split(':').first,
            tabId: window.id ?? herdrTabIdFromPaneId(pane.id),
            tabLabel: window.name,
          );
        }
      }
    }
    return HerdrResolvedTarget(
      paneId: pane.id,
      workspaceId: pane.id.split(':').first,
      tabId: herdrTabIdFromPaneId(pane.id),
    );
  }

  /// [followBackendFocus] 用のターゲット解決（focused 情報欠落時は null）。
  HerdrResolvedTarget? resolveFocusedPaneFromSessions(
    List<MultiplexerSession> sessions,
  ) {
    final workspace = findWorkspace(sessions, _host.display);
    if (workspace == null) return null;
    final focusedTab = workspace.windows.where((w) => w.active).firstOrNull;
    final focusedPane = focusedTab?.panes.where((p) => p.active).firstOrNull;
    if (focusedPane == null) return null;
    return resolveWorkspaceTarget(sessions, workspace);
  }

  /// [workspace] の表示対象 pane を解決する。
  HerdrResolvedTarget? resolveWorkspaceTarget(
    List<MultiplexerSession> sessions,
    MultiplexerSession workspace,
  ) {
    final focusedTab = workspace.windows.where((w) => w.active).firstOrNull;
    final tab = focusedTab ?? workspace.windows.firstOrNull;
    if (tab != null) {
      final focusedPane = tab.panes.where((p) => p.active).firstOrNull;
      if (focusedPane != null) {
        return resolvedTargetOf(sessions, focusedPane);
      }
      if (tab.panes.isNotEmpty) {
        return resolvedTargetOf(sessions, tab.panes.first);
      }
    }
    final workspacePanes = [for (final w in workspace.windows) ...w.panes];
    final workspaceFocused = workspacePanes.where((p) => p.active).firstOrNull;
    if (workspaceFocused != null) {
      return resolvedTargetOf(sessions, workspaceFocused);
    }
    if (workspacePanes.isNotEmpty) {
      return resolvedTargetOf(sessions, workspacePanes.first);
    }
    return null;
  }

  /// 表示中の workspace 引き当て（セレクタ・followBackendFocus 用・T4）。
  MultiplexerSession? findWorkspace(
    List<MultiplexerSession> sessions,
    HerdrDisplayData? display,
  ) {
    final id = display?.workspaceId;
    final label = display?.workspaceLabel;
    for (final session in sessions) {
      if (id != null && session.id == id) return session;
      if (label != null && session.name == label) return session;
    }
    return null;
  }

  /// 表示中の tab 引き当て（T4）。
  MultiplexerWindow? findWindow(
    MultiplexerSession? session,
    HerdrDisplayData? display,
  ) {
    final tabId = display?.tabId;
    if (session == null || tabId == null) return null;
    for (final window in session.windows) {
      if (window.id == tabId) return window;
    }
    return null;
  }

  /// server-down からのエスカレーション（A2 / R1）。
  Future<void> handleServerDown(Object e) async {
    _host.setIndicatorData(null);
    _host.suspendPolling();
    _host.snapshotCache?.invalidate();
    if (_host.isMounted && !_host.isDisposed) {
      herdrShowError(
        _host.context,
        _host.context.l10n.termHerdrServerNotResponding(e.toString()),
        retry: _host.resumePolling,
      );
    }
  }

  /// 終端エラー（再解決でも対象不在）を通知する。再接続はしない（A2 / R1）。
  void notifyHerdrTargetLost() {
    if (!_host.isMounted || _host.isDisposed) return;
    _host.setIndicatorData(null);
    _host.suspendPolling();
    herdrShowError(
      _host.context,
      _host.context.l10n.termHerdrTargetPaneNotFound,
      retry: _host.resumePolling,
    );
  }

  /// herdr mutation の失敗を分類して通知・後続処理を行う（T19 / S4）。
  Future<void> handleMutationError(
    Object e, {
    required String operationLabel,
  }) async {
    if (!_host.isMounted || _host.isDisposed) return;
    switch (const HerdrMutationErrorClassifier().classify(e)) {
      case HerdrMutationClass.targetNotFound:
        _host.recordSwitchEvent(
          'mutation $operationLabel: target-not-found (${e.runtimeType})',
        );
        herdrShowTargetNotFound(_host.context);
        await syncAfterMutation(eventLabel: '$operationLabel re-sync');
      case HerdrMutationClass.invalidKey:
        _host.recordSwitchEvent(
          'mutation $operationLabel: invalid_key (${e.runtimeType})',
        );
        herdrShowInvalidKey(_host.context);
      case HerdrMutationClass.noop:
        final noop = e as PaneOperationNoopException;
        _host.recordSwitchEvent(
          'mutation $operationLabel: no-op '
          '(reason: ${noop.reason ?? '<null>'})',
        );
        herdrShowNoop(_host.context, noop);
      case HerdrMutationClass.serverDown:
        _host.recordSwitchEvent(
          'mutation $operationLabel: server-down (${e.runtimeType})',
        );
        await handleServerDown(e);
      case HerdrMutationClass.sshDisconnected:
      case HerdrMutationClass.other:
        _host.recordSwitchEvent(
          'mutation $operationLabel: error (${e.runtimeType})',
        );
        // #125: 接続断系も含め一律エラー通知へ一本化する（再接続は Path B の
        // ポーリング検知へ集約し、ここでは試みない）。
        herdrShowMutation(
          _host.context,
          _host.context.l10n.termOperationFailed(operationLabel, e.toString()),
        );
    }
  }
}
