// P4: root が実装すべき port interface 群の実装（ui/root 領域・500 行制約用に
// `terminal_root_bindings.dart` から分離）。
//
// `TerminalScreenAdapter`（terminal_root_bindings.dart）が生成・注入する
// 協調オブジェクト（runtime / herdr / input / viewport 等）を
// [TerminalPortSource] 越しに読んで、root が実装すべきすべての port を提供する。
// 依存方向: root → ports ← session/herdr/view-input（一方向・循環なし）。
library;

import 'package:flutter/material.dart';

import '../../providers/ssh_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/tmux_provider.dart';
import '../../services/backend/domain/multiplexer_backend.dart';
import '../../services/backend/domain/pane_frame_reader.dart';
import '../../services/backend/domain/pane_history_policy.dart';
import '../../services/backend/domain/pane_read.dart';
import '../../services/backend/domain/pane_writer.dart';
import '../../services/herdr/herdr_adapter.dart';
import '../../services/herdr/herdr_pane_content_reader.dart';
import '../../services/ssh/ssh_client.dart';
import '../../services/tmux/pane_navigator.dart';
import '../../services/tmux/tmux_facade.dart';
import 'herdr/herdr_controller.dart' show HerdrController;
import 'herdr/herdr_types.dart'
    show ConcurrentSelectorLoader, HerdrSheetHost, HerdrTargetIdentity;
import 'input/terminal_input_coordinator.dart';
import 'input/terminal_input_mode.dart' show ScrollModeSource;
import 'input/terminal_input_ports.dart';
import 'input/terminal_viewport_port.dart';
import 'session/session_env.dart';
import 'session/session_mutations.dart' show TmuxSessionMutations;
import 'session/session_runtime.dart';
import '../../l10n/l10n_ext.dart';
import 'herdr_sheet_host.dart' show HerdrSheetHostImpl;
import 'terminal_screen_access.dart' show TerminalScreenAccess;
import 'widgets/ansi_terminal_model.dart' show TerminalMode;

/// port 実装が参照する根（`TerminalScreenAdapter` が実装）。
abstract interface class TerminalPortSource {
  TerminalScreenAccess get access;
  SessionEnv get env;
  SessionRuntimeController get runtime;
  HerdrController get herdr;
  TerminalInputCoordinator get input;
  TerminalViewportPort get viewport;
  TmuxFacade get tmux;
  TmuxSessionMutations get mutations;

  /// C9: pending 表示対象（root 保管・値生成は herdr API）。
  Object? get pendingTargetIdentity;
  set pendingTargetIdentity(Object? value);
  dynamic get pendingCaret;
  set pendingCaret(dynamic value);
}

/// root が実装すべき port の単一実装（SessionEnv・協調オブジェクトへ注入）。
class TerminalScreenPorts
    implements
        SessionHost,
        PendingViewStore,
        TransferHost,
        SessionHerdrPort,
        SessionInputPort,
        SessionViewportPort,
        TerminalInputHost,
        TerminalPaneSendPort,
        TerminalInputCapabilities,
        TerminalScrollbackPort,
        TerminalTargetIdentityValidator,
        TerminalNavigationPort,
        HerdrSheetHost {
  TerminalScreenPorts(this.source);

  final TerminalPortSource source;
  TerminalScreenAccess get access => source.access;

  // ===================== SessionHost =====================

  @override
  bool get isMounted => access.isMounted;
  @override
  bool get isDisposed => access.isDisposed;
  @override
  void markNeedsBuild() => access.markNeedsBuild();
  @override
  void showCommErrorPanel({
    required String title,
    required String body,
    required String detail,
    required Future<void> Function() onRetry,
  }) => access.showCommErrorPanel(
    title: title,
    body: body,
    detail: detail,
    onRetry: onRetry,
  );
  @override
  void closeCommErrorPanel() => access.closeCommErrorPanel();
  @override
  void onConnectionRestored() => access.onConnectionRestored();
  @override
  void syncReconnectCountdown({
    required bool isReconnecting,
    required bool isWaitingForNetwork,
    DateTime? nextRetryAt,
  }) => access.syncReconnectCountdown(
    isReconnecting: isReconnecting,
    isWaitingForNetwork: isWaitingForNetwork,
    nextRetryAt: nextRetryAt,
  );
  @override
  BuildContext get context => access.context;
  @override
  String get connectionId => access.connectionId;
  @override
  String? get sessionName => access.sessionName;
  @override
  String? get sessionId => access.sessionId;
  @override
  int? get lastWindowIndex => access.lastWindowIndex;
  @override
  String? get lastPaneId => access.lastPaneId;
  @override
  String? get deepLinkWindowName => access.deepLinkWindowName;
  @override
  int? get deepLinkPaneIndex => access.deepLinkPaneIndex;
  @override
  Object? get injectedPaneContentReader => access.injectedPaneContentReader;
  @override
  Object? get herdrCacheClock => access.herdrCacheClock;
  @override
  Object? get herdrCaretReader => access.herdrCaretReader;
  @override
  Object? get bottomFollowEpsilon => 1.0;

  // ===================== PendingViewStore =====================

  @override
  Object? get pendingTargetIdentity => source.pendingTargetIdentity;
  @override
  set pendingTargetIdentity(Object? value) =>
      source.pendingTargetIdentity = value;
  @override
  dynamic get pendingCaret => source.pendingCaret;
  @override
  set pendingCaret(dynamic value) => source.pendingCaret = value;

  // ===================== TerminalInputHost =====================

  @override
  void showScrollToBottomButton() {
    if (access.isMounted) access.scrollToBottomKey.currentState?.show();
  }

  @override
  void notifyInputQueueFull() {
    if (!access.isMounted) return;
    ScaffoldMessenger.of(access.context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(access.context.l10n.termInputQueueFull)),
      );
  }

  @override
  void notifyMultilineNeedsConnection() {
    if (!access.isMounted) return;
    ScaffoldMessenger.of(access.context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(access.context.l10n.termMultilineNeedsConnection),
        ),
      );
  }

  @override
  void notifyHerdrInvalidKey() {
    if (!access.isMounted) return;
    ScaffoldMessenger.of(access.context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(access.context.l10n.termHerdrInvalidKey)),
      );
  }

  // ===================== TerminalPaneSendPort =====================

  @override
  PaneWriter? get paneWriter => source.runtime.paneWriter;
  @override
  String? get currentPaneId => source.runtime.targetSource?.currentPaneId;
  @override
  bool get isConnected =>
      access.ref.read(sshProvider.notifier).client?.isConnected ?? false;
  @override
  void boostPolling() => source.runtime.boostPolling();
  @override
  void recordHerdrSwitchEvent(String event) =>
      source.herdr.recordSwitchEvent(event);
  @override
  String? get currentTmuxTarget =>
      access.ref.read(tmuxProvider.notifier).currentTarget;
  @override
  Future<void> enterCopyMode(String target) async {
    final client = access.ref.read(sshProvider.notifier).client;
    if (client == null) return;
    await source.tmux.enterCopyModeNoWait(client.tmuxExecutor, target);
    source.runtime.boostPolling();
  }

  @override
  Future<void> exitCopyMode(String target) async {
    final client = access.ref.read(sshProvider.notifier).client;
    if (client == null) return;
    await source.tmux.cancelCopyModeNoWait(client.tmuxExecutor, target);
    source.runtime.boostPolling();
  }

  // ===================== TerminalInputCapabilities =====================

  @override
  bool get canSendText => source.runtime.canSendText;
  @override
  bool get canSendSpecialKey => source.runtime.canSendSpecialKey;
  @override
  bool get canFocusDirection => source.runtime.canFocusDirection;
  @override
  bool get canCopyMode => source.runtime.canCopyMode;
  @override
  bool get canPaste => source.runtime.canPaste;
  @override
  bool get canWheelSend => source.runtime.canWheelSend;

  // ===================== TerminalScrollbackPort =====================

  @override
  bool get canRead => source.runtime.paneReader != null && isConnected;
  @override
  String get displayedContent => source.runtime.viewNotifier.value.content;
  @override
  int get displayedPaneWidth => source.runtime.viewNotifier.value.paneWidth;
  @override
  int get displayedPaneHeight => source.runtime.viewNotifier.value.paneHeight;
  @override
  PaneCaret? get displayedCaret => source.runtime.viewNotifier.value.caret;
  @override
  int get scrollbackLimit => _resolveHistoryPolicy().scrollbackLimit;

  @override
  Object? captureTargetIdentity() => source.herdr.captureIdentity();

  @override
  Future<String?> readScrollbackContent() async {
    final sshClient = access.ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return null;
    final paneId = source.runtime.targetSource?.currentPaneId;
    final reader = source.runtime.paneReader;
    final frameReader = source.runtime.frameReader;
    if (paneId == null || reader == null) return null;
    try {
      final request = PaneReadRequest.scrollback(
        paneId: paneId,
        maxLines: _resolveHistoryPolicy().scrollbackLimit,
      );
      final snapshot = frameReader != null
          ? (await frameReader.read(PaneFrameRequest(request))).toSnapshot()
          : await reader.readPane(request);
      return snapshot.content;
    } catch (_) {
      return null;
    }
  }

  @override
  void setDisplayedContent(String content) {
    source.runtime.viewNotifier.value = source.runtime.viewNotifier.value
        .copyWith(content: content);
  }

  PaneHistoryPolicy _resolveHistoryPolicy() =>
      PaneHistoryPolicyResolver.forBackend(
        source.runtime.backendKind,
        configuredScrollbackLines: access.ref
            .read(settingsProvider)
            .scrollbackLines,
      );

  // ===================== TerminalTargetIdentityValidator =====================

  @override
  bool isCurrent(Object? identity) =>
      source.herdr.isCurrentIdentity(identity as HerdrTargetIdentity?);

  // ===================== SessionHerdrPort =====================

  @override
  bool isCurrentTargetIdentity(Object? identity) =>
      source.herdr.isCurrentIdentity(identity as HerdrTargetIdentity?);
  @override
  Future<bool> reResolveAfterReconnect() =>
      source.herdr.reResolveAfterReconnect();
  @override
  Future<void> refreshPaneIndicatorFromCache() =>
      source.herdr.refreshPaneIndicatorFromCache();
  @override
  Future<void> handlePollError(Object error) =>
      source.herdr.handlePollError(error);
  @override
  void recordSwitchEvent(String event) => source.herdr.recordSwitchEvent(event);
  @override
  Future<void> handleHerdrMutationError(
    Object error, {
    String? operationLabel,
  }) => source.herdr.handleMutationError(
    error,
    operationLabel: operationLabel ?? 'mutation',
  );
  @override
  Future<void> syncAfterHerdrMutation({String? eventLabel}) =>
      source.herdr.syncAfterMutation(eventLabel: eventLabel ?? 'mutation sync');
  @override
  Object? get snapshotCache => source.herdr.snapshotCache;
  @override
  dynamic get displayNotifier => source.herdr.displayNotifier;
  @override
  dynamic get paneIndicatorNotifier => source.herdr.indicatorNotifier;
  @override
  void rebuildReaders() {
    final client = access.ref.read(sshProvider.notifier).client;
    if (client == null) return;
    final adapter = HerdrAdapter(client);
    source.runtime.paneReader = HerdrPaneContentReader(adapter);
    source.runtime.frameReader = source.herdr.rebuildAfterClient(client);
  }

  @override
  void rebuildInjectedReaderCache(Object client) =>
      source.herdr.createCacheForInjectedReader(client as SshClient);

  @override
  Future<void> setupSession(Object client) =>
      source.herdr.setupSession(client as SshClient);

  // ===================== SessionInputPort =====================

  @override
  void resetTerminalMode() => source.input.resetTerminalMode();
  @override
  Future<void> flushInputQueue() => source.input.flushInputQueue();
  @override
  void captureSelectUpdate({
    required String content,
    dynamic caret,
    Object? targetIdentity,
  }) => source.input.captureSelectUpdate(
    content: content,
    caret: caret,
    targetIdentity: targetIdentity,
  );
  @override
  dynamic takeBufferedUpdate() => source.input.takeBufferedUpdate();
  @override
  void handleTmuxCopyModeDetected() => source.input.handleTmuxCopyModeDetected(
    fromScrollSend: source.input.mode == TerminalMode.scrollSend,
  );
  @override
  void handleTmuxCopyModeEnded() => source.input.handleTmuxCopyModeEnded();
  @override
  void scrollToCaret() => source.input.scrollToCaret();
  @override
  void followToBottom() => source.viewport.followToBottom();
  @override
  void selectPaneReset() => source.input.resetTerminalMode();
  @override
  bool get shouldFollowBottom => source.input.shouldFollowBottom;
  @override
  bool get isSelectManualActive =>
      source.input.mode == TerminalMode.select &&
      source.input.scrollModeSource == ScrollModeSource.manual;
  @override
  void observePaneMode(String paneMode) =>
      source.input.observePaneMode(paneMode);
  @override
  bool get isScrollModeSourceNone =>
      source.input.scrollModeSource == ScrollModeSource.none;
  @override
  bool get isNormalMode => source.input.mode == TerminalMode.normal;
  @override
  bool get isUserScrollDragging => source.input.isUserScrollDragging;
  @override
  bool get isCopyModeActive =>
      source.input.mode == TerminalMode.select &&
      source.input.scrollModeSource == ScrollModeSource.tmux;
  @override
  bool get isScrollSendActive => source.input.mode == TerminalMode.scrollSend;

  // ===================== SessionViewportPort =====================

  @override
  void resetZoom() => source.input.resetZoom();

  // ===================== TerminalNavigationPort =====================

  @override
  bool get isHerdr =>
      source.runtime.backendKind == MultiplexerBackendKind.herdr;

  @override
  Future<void> selectAdjacentPane(
    SwipeDirection direction, {
    required bool invert,
  }) async {
    final tmuxState = access.ref.read(tmuxProvider);
    final window = tmuxState.activeWindow;
    final activePane = tmuxState.activePane;
    if (window == null || activePane == null) return;
    final actual = invert ? direction.inverted : direction;
    final target = PaneNavigator.findAdjacentPane(
      panes: window.panes,
      current: activePane,
      direction: actual,
    );
    if (target != null) await source.mutations.selectPane(target.id);
  }

  @override
  Map<SwipeDirection, bool>? navigableDirections({required bool invert}) {
    if (isHerdr) return source.herdr.navigableDirections;
    final tmuxState = access.ref.read(tmuxProvider);
    final window = tmuxState.activeWindow;
    final activePane = tmuxState.activePane;
    if (window == null || activePane == null) return null;
    final raw = PaneNavigator.getNavigableDirections(
      panes: window.panes,
      current: activePane,
    );
    if (!invert) return raw;
    return {
      for (final dir in SwipeDirection.values) dir: raw[dir.inverted] ?? false,
    };
  }

  @override
  Future<void> focusPaneDirection(SwipeDirection direction) =>
      source.herdr.focusPaneDirection(direction);

  // ===================== HerdrSheetHost =====================

  late final HerdrSheetHost _sheetHost = HerdrSheetHostImpl(
    () => access.context,
  );

  @override
  Future<void> show({
    required String title,
    required IconData icon,
    bool topExpected = false,
    required ConcurrentSelectorLoader load,
  }) {
    return _sheetHost.show(
      title: title,
      icon: icon,
      topExpected: topExpected,
      load: load,
    );
  }
}
