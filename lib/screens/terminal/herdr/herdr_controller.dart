import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart';
import '../../../services/backend/domain/multiplexer_backend.dart';
import '../../../services/backend/domain/multiplexer_session.dart';
import '../../../services/backend/domain/multiplexer_window.dart';
import '../../../services/backend/domain/pane_frame_reader.dart';
import '../../../services/backend/domain/pane_writer.dart';
import '../../../services/herdr/caret/herdr_caret_snapshot_reader.dart';
import '../../../services/herdr/herdr_adapter.dart';
import '../../../services/herdr/herdr_models.dart';
import '../../../services/herdr/herdr_resize_bridge.dart';
import '../../../services/herdr/herdr_snapshot_cache.dart';
import '../../../services/ssh/ssh_client.dart';
import '../../../services/tmux/pane_navigator.dart';
import 'herdr_caret.dart';
import 'herdr_crud.dart';
import 'herdr_env.dart';
import 'herdr_internal.dart';
import 'herdr_navigation.dart';
import 'herdr_resize.dart';
import 'herdr_selectors.dart';
import 'herdr_selectors_commit.dart';
import 'herdr_setup.dart';
import 'herdr_sync.dart';
import 'herdr_types.dart';

class HerdrController implements HerdrHost {
  @override
  bool get hasInjectedPaneContentReader => env.hasInjectedPaneContentReader();
  HerdrController(this.env);

  final HerdrEnv env;

  /// caret composer 用ホスト（コールバックで本コントローラの state を接続）。
  late final HerdrCaretHost _caretHost = HerdrCaretHostImpl(
    ref: env.ref,
    isMounted: env.isMounted,
    isDisposed: env.isDisposed,
    backendKind: env.backendKind,
    frameAdapter: () => frameAdapter,
    snapshotCache: () => _snapshotCache,
    injectedReader: env.injectedCaretReader,
    caretReader: () => caretReader,
    setCaretReader: (v) => caretReader = v,
    caretStatus: () => caretStatus,
    setCaretStatus: (v) => caretStatus = v,
    onFrameReader: env.setFrameReader,
    onClearViewCaret: env.clearViewCaret,
  );

  late final HerdrSetupFlow _setup = HerdrSetupFlow(this);
  late final HerdrSyncFlow _sync = HerdrSyncFlow(this);
  late final HerdrSelectorCommitter _commit = HerdrSelectorCommitter(
    this,
    _sync,
    actions,
  );
  late final HerdrSelectorPresenter _presenter = HerdrSelectorPresenter(
    this,
    _commit,
  );
  late final HerdrResizeFlow resize = HerdrResizeFlow(this, _sync);
  late final HerdrCrudFlow crud = HerdrCrudFlow(this);
  late final HerdrCaretComposer caret = HerdrCaretComposer(_caretHost);

  late final HerdrDialogActions actions = HerdrDialogActionsImpl(
    resize,
    crud,
    env,
  );

  // ---- 所有 state ----
  @override
  final ValueNotifier<HerdrDisplayData?> displayNotifier =
      ValueNotifier<HerdrDisplayData?>(null);
  @override
  final ValueNotifier<HerdrPaneIndicatorData?> indicatorNotifier =
      ValueNotifier<HerdrPaneIndicatorData?>(null);

  HerdrTargetSource? _targetSource;
  HerdrSnapshotCache? _snapshotCache;
  HerdrAdapter? frameAdapter;
  HerdrCaretSnapshotReader? caretReader;
  HerdrStatus? caretStatus;
  @override
  HerdrResizeBridge? resizeBridge;

  static const int _switchEventBufferSize = 64;
  final List<String> _switchEvents = <String>[];

  // =====================================================================
  // HerdrHost 実装（flows への提供）
  // =====================================================================

  @override
  WidgetRef get ref => env.ref;

  @override
  BuildContext get context => env.contextProvider();

  @override
  bool get isMounted => env.isMounted();

  @override
  bool get isDisposed => env.isDisposed();

  @override
  MultiplexerBackendKind get backendKind => env.backendKind();

  @override
  bool can(PaneCapabilities required) => env.can(required);

  @override
  PaneWriter? get paneWriter => env.paneWriter();

  @override
  String? get paneId => _targetSource?.currentPaneId;

  @override
  HerdrSnapshotCache? get snapshotCache => _snapshotCache;

  @override
  HerdrDisplayData? get display => displayNotifier.value;

  @override
  void setTargetPaneId(String paneId) {
    final source = _targetSource ??= HerdrTargetSource(paneId);
    source.setPaneId(paneId);
    env.setTargetSource(source);
  }

  @override
  void recordSwitchEvent(String event) {
    final entry = '[HerdrSwitch] $event';
    if (_switchEvents.length >= _switchEventBufferSize) {
      _switchEvents.removeAt(0);
    }
    _switchEvents.add(entry);
    debugPrint(entry);
  }

  @override
  HerdrTargetIdentity? captureIdentity() {
    final cache = _snapshotCache;
    if (cache == null) return null;
    return (
      cache: cache,
      epoch: cache.epoch,
      paneId: _targetSource?.currentPaneId,
    );
  }

  @override
  bool isCurrentIdentity(HerdrTargetIdentity? identity) {
    if (identity == null) return true;
    final cache = _snapshotCache;
    return identical(cache, identity.cache) &&
        cache != null &&
        cache.epoch == identity.epoch &&
        _targetSource?.currentPaneId == identity.paneId;
  }

  // HerdrHost.displayNotifier / indicatorNotifier は同名 public フィールドで満たす。

  @override
  HerdrSheetHost? get sheetHost => env.sheetHost;

  @override
  Future<String?> Function(HerdrLabelDialogArgs) get showLabelInputDialog =>
      env.showLabelInputDialog;

  @override
  String? get sessionId => env.sessionId();

  @override
  String? get workspaceLabel => env.workspaceLabel();

  @override
  String? get initialPaneId => env.initialPaneId();

  @override
  String? get lastPaneId => env.lastPaneId();

  @override
  void clearTmuxProvider() => env.clearTmuxProvider();

  @override
  void recreateReaders() => env.recreateReaders();

  @override
  void resetTerminalMode() => env.resetTerminalMode();

  @override
  void resetView() => env.resetView();

  @override
  void boostPolling() => env.boostPolling();

  @override
  void startPolling() => env.startPolling();

  @override
  void suspendPolling() => env.suspendPolling();

  @override
  void resumePolling() => env.resumePolling();

  @override
  void attemptReconnect() => env.attemptReconnect();

  @override
  bool get isResizing => env.isResizing();

  @override
  void setResizing(bool value) => env.setResizing(value);

  @override
  void cancelPollTimer() => env.cancelPollTimer();

  @override
  Future<List<MultiplexerSession>?> fetchHerdrSessions({
    required bool force,
    required String eventLabel,
    required bool isTerminal,
  }) => _sync.fetchHerdrSessions(
    force: force,
    eventLabel: eventLabel,
    isTerminal: isTerminal,
  );

  @override
  void switchTarget(
    String paneId, {
    String? workspaceLabel,
    String? workspaceId,
    String? tabId,
    String? tabLabel,
  }) => _switchTarget(
    paneId,
    workspaceLabel: workspaceLabel,
    workspaceId: workspaceId,
    tabId: tabId,
    tabLabel: tabLabel,
  );

  @override
  Future<bool> syncAfterMutation({
    String eventLabel = 'mutation sync',
    HerdrSyncTargetPolicy policy = HerdrSyncTargetPolicy.preserveCurrent,
  }) => _sync.syncAfterMutation(eventLabel: eventLabel, policy: policy);

  @override
  void setIndicatorData(List<MultiplexerSession>? sessions) {
    if (isDisposed) return;
    if (backendKind != MultiplexerBackendKind.herdr) return;
    if (sessions == null) {
      indicatorNotifier.value = null;
      return;
    }
    final display = displayNotifier.value;
    final workspace = _sync.findWorkspace(sessions, display);
    final window = _sync.findWindow(workspace, display);
    if (window == null) {
      indicatorNotifier.value = null;
      return;
    }
    indicatorNotifier.value = HerdrPaneIndicatorData(
      panes: window.panes,
      activePaneId: _targetSource?.currentPaneId,
    );
  }

  @override
  Future<void> handleMutationError(
    Object e, {
    required String operationLabel,
  }) => _sync.handleMutationError(e, operationLabel: operationLabel);

  @override
  PaneFrameReader? rebuildAfterClient(SshClient client) =>
      _rebuildHerdrEngine(client);

  // =====================================================================
  // root / session への公開 API（設計 §4.3）
  // =====================================================================

  Future<void> setupSession(SshClient client) => _setup.setupSession(client);

  Future<bool> reResolveAfterReconnect() => _sync.reResolveAfterReconnect();

  Future<void> handlePollError(Object e) => _sync.handlePollError(e);

  Future<void> refreshPaneIndicatorFromCache() =>
      _commit.refreshIndicatorFromCache();

  void showWorkspaceSelector() => _presenter.showWorkspaceSelector();

  void showTabSelector() => _presenter.showTabSelector();

  void showPaneSelector() => _presenter.showPaneSelector();

  void showResizePaneChooser(
    List<MultiplexerSession> sessions,
    MultiplexerWindow window,
  ) => resize.showResizePaneChooser(sessions, window);

  Future<void> focusPaneDirection(SwipeDirection direction) async {
    final writer = env.paneWriter();
    final beforePane = _targetSource?.currentPaneId;
    if (writer == null || beforePane == null) return;

    final directionName = switch (direction) {
      SwipeDirection.up => 'up',
      SwipeDirection.down => 'down',
      SwipeDirection.left => 'left',
      SwipeDirection.right => 'right',
    };

    env.cancelPollTimer();
    try {
      await writer.focusPaneDirection(beforePane, directionName);
      if (!isMounted || isDisposed) return;
      await _sync.syncAfterMutation(
        eventLabel: 'focus sync',
        policy: HerdrSyncTargetPolicy.followBackendFocus,
      );
    } on PaneOperationNoopException catch (e) {
      await _sync.handleMutationError(e, operationLabel: 'focus');
    } catch (e) {
      await _sync.handleMutationError(e, operationLabel: 'focus');
    } finally {
      if (isMounted && !isDisposed) env.startPolling();
    }
  }

  Map<SwipeDirection, bool>? get navigableDirections {
    if (!can(const PaneCapabilities(focus: true))) return null;
    final dirs = herdrNavigableDirections(
      paneId: _targetSource?.currentPaneId,
      snapshot: _snapshotCache?.cachedSnapshot,
    );
    if (dirs == null) return null;
    final settings = env.ref.read(settingsProvider);
    if (settings.invertPaneNavigation) {
      return {
        for (final dir in SwipeDirection.values)
          dir: dirs[dir.inverted] ?? false,
      };
    }
    return dirs;
  }

  // =====================================================================
  // テストフック（root State がフォワード）
  // =====================================================================
  @visibleForTesting
  void switchTargetForTesting(String paneId) => _switchTarget(paneId);
  @visibleForTesting
  Future<bool> syncAfterMutationForTesting({
    String eventLabel = 'test mutation sync',
    HerdrSyncTargetPolicy policy = HerdrSyncTargetPolicy.preserveCurrent,
  }) => _sync.syncAfterMutation(eventLabel: eventLabel, policy: policy);
  @visibleForTesting
  Future<void> focusPaneDirectionForTesting(SwipeDirection direction) =>
      focusPaneDirection(direction);

  @visibleForTesting
  Future<void> renamePaneForTesting(String paneId, String label) =>
      crud.renamePane(paneId, label);

  @visibleForTesting
  Future<void> zoomPaneForTesting(String paneId) => crud.zoomPane(paneId);

  @visibleForTesting
  Future<void> createTabForTesting(
    String workspaceId, {
    String? label,
    bool? focus,
  }) => crud.createTab(workspaceId, label: label, focus: focus);

  @visibleForTesting
  Future<void> renameTabForTesting(String tabId, String label) =>
      crud.renameTab(tabId, label);

  @visibleForTesting
  Future<void> closeTabForTesting(String tabId) => crud.closeTab(tabId: tabId);

  @visibleForTesting
  List<String> switchEventsForTesting() => List.unmodifiable(_switchEvents);

  // =====================================================================
  // 内部実装
  // =====================================================================

  void _switchTarget(
    String paneId, {
    String? workspaceLabel,
    String? workspaceId,
    String? tabId,
    String? tabLabel,
  }) {
    if (!isMounted || isDisposed) return;
    final source = _targetSource;
    if (source is! HerdrTargetSource) return;

    final effectiveWorkspaceId = workspaceId ?? paneId.split(':').first;
    final effectiveTabId = tabId ?? herdrTabIdFromPaneId(paneId);
    final effectiveTabLabel = tabLabel ?? effectiveTabId;

    final current = displayNotifier.value;
    if (current != null &&
        current.paneId == paneId &&
        current.workspaceId == effectiveWorkspaceId &&
        current.tabId == effectiveTabId) {
      return;
    }

    source.setPaneId(paneId);
    env.resetView();
    env.resetTerminalMode();

    displayNotifier.value = HerdrDisplayData(
      workspaceLabel: workspaceLabel ?? env.workspaceLabel(),
      workspaceId: effectiveWorkspaceId,
      tabId: effectiveTabId,
      tabLabel: effectiveTabLabel,
      paneId: paneId,
    );

    recordSwitchEvent('switch target -> $paneId');
    env.boostPolling();
  }

  PaneFrameReader? _rebuildHerdrEngine(SshClient client) {
    final adapter = HerdrAdapter(client);
    _snapshotCache = HerdrSnapshotCache(() => adapter, clock: env.clock);
    frameAdapter = adapter;
    caretReader = caret.resolveInjected();
    final frameReader = caret.buildFrameReader();
    if (env.injectedCaretReader() == null) {
      unawaited(caret.setupProduction(client));
    }
    resizeBridge = HerdrResizeBridge(
      client: client,
      cache: _snapshotCache!,
      executablePath: caret.executablePath(client),
      tabIdProvider: () => displayNotifier.value?.tabId,
    );
    return frameReader;
  }

  /// テスト注入 content reader 経路の cache 生成（caret/bridge なし）。
  void createCacheForInjectedReader(SshClient client) {
    final adapter = HerdrAdapter(client);
    _snapshotCache = HerdrSnapshotCache(() => adapter, clock: env.clock);
    frameAdapter = null;
    caretReader = null;
    caretStatus = null;
  }

  /// herdr 表示対象 pane を確定したときにソースを差し替える（setup 用）。
  void installTargetSource(HerdrTargetSource source) {
    _targetSource = source;
    env.setTargetSource(source);
  }

  // =====================================================================
  // dispose（arbitration §4: P1 / P7 / P8 の 3 分割）
  // =====================================================================

  /// P1: bridge reset（先頭・単独フェーズ）。
  void disposeBridge() {
    unawaited(resizeBridge?.reset());
    resizeBridge = null;
  }

  /// P7: cache / reader / リングバッファの null 化。
  void disposeCaches() {
    _snapshotCache = null;
    frameAdapter = null;
    caretReader = null;
    caretStatus = null;
    _switchEvents.clear();
  }

  /// P8: notifier 群の dispose（display → indicator の順・root が統括）。
  void disposeNotifiers() {
    displayNotifier.dispose();
    indicatorNotifier.dispose();
  }
}

/// caret composer 用ホスト。コントローラ生成順の都合上 late 適用する。
