// P4: terminal_screen.dart（シム + root State・仲裁 §2 の限定スコープ）。
//
// 公開 API の再 export（1 経路・仲裁 §7）と、root State の「鍵・ライフサイクル・
// dispose P0-P9 統括・テストフック転送・build 合成」のみを保持する。状態・機械
// ロジックは session（SessionRuntimeController ほか）/ herdr（HerdrController）/
// view-input（TerminalInputCoordinator）が所有し、[TerminalScreenAdapter]
// （terminal_root_bindings.dart）が port 実装と協調オブジェクト生成を担う。
//
// import パスは不変（24 test + 4 lib 呼出元）。`test/` は一切変更しない。
// ignore_for_file: invalid_use_of_visible_for_testing_member
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// 公開 API の再 export（シムから 1 経路のみ・他設計で再定義禁止）。
export 'download_snackbar_display.dart'
    show DownloadSnackBarDisplay, downloadSnackBarDisplay;
export 'herdr/herdr_types.dart' show HerdrSyncTargetPolicy;
export 'input/terminal_input_mode.dart' show ScrollModeSource;
export 'input_dialog_content.dart' show buildInputDialogContentForTesting;

import 'herdr/herdr_types.dart' show HerdrSyncTargetPolicy;

import '../../providers/settings_provider.dart';
import '../../providers/ssh_provider.dart';
import '../../providers/tmux_provider.dart';
import '../../services/backend/domain/pane_content_reader.dart';
import '../../services/backend/domain/pane_writer.dart';
import '../../services/backend/domain/wheel_encoder.dart' show ScrollSendKind;
import '../../services/herdr/caret/herdr_caret_snapshot_reader.dart';
import '../../services/tmux/commands/layout.dart' show SplitDirection;
import '../../services/tmux/pane_navigator.dart' show SwipeDirection;
import '../../services/terminal/tmux_key_display.dart' show KeyOverlayPosition;
import '../../widgets/scroll_to_bottom_button.dart'
    show ScrollToBottomButtonState;
import '../settings/settings_screen.dart' show SettingsScreen;
import 'input/terminal_input_mode.dart' show ScrollModeSource;
import 'selector_launch.dart' show SelectorLaunchActions;
import 'selector_sheet.dart' show SelectorContext;
import 'widgets/reconnect_countdown.dart' show ReconnectCountdown;
import 'terminal_menu.dart' show TerminalMenu;
import 'terminal_root_bindings.dart'
    show TerminalScreenAccess, TerminalScreenAdapter;
import 'terminal_view_shell.dart' show TerminalViewShell;
import 'widgets/ansi_text_view.dart' show AnsiTextViewState;

/// ターミナル画面（公開 API・コンストラクタは HEAD と同一）。
class TerminalScreen extends ConsumerStatefulWidget {
  // inventory: LEGACY-0063
  final String connectionId;
  // inventory: LEGACY-0064
  final String? sessionName;

  // inventory: TERM-SCREEN-007
  /// セッション ID（tmux: "$0" / herdr: "w3"）。
  final String? sessionId;

  // inventory: LEGACY-0065
  final int? lastWindowIndex;
  // inventory: LEGACY-0066
  final String? lastPaneId;
  // inventory: LEGACY-0067
  final String? deepLinkWindowName;
  // inventory: LEGACY-0068
  final int? deepLinkPaneIndex;

  // inventory: TERM-SCREEN-004
  final PaneContentReader? paneContentReader;

  // inventory: TERM-SCREEN-006
  final String? initialPaneId;

  /// テスト用: herdr snapshot cache の時刻源。
  final DateTime Function()? herdrCacheClock;

  /// テスト用: herdr caret snapshot reader の注入。
  final HerdrCaretSnapshotReader? herdrCaretReader;

  const TerminalScreen({
    super.key,
    required this.connectionId,
    this.sessionName,
    this.sessionId,
    this.lastWindowIndex,
    this.lastPaneId,
    this.deepLinkWindowName,
    this.deepLinkPaneIndex,
    this.paneContentReader,
    this.initialPaneId,
    this.herdrCacheClock,
    this.herdrCaretReader,
  });

  @override
  // inventory: LEGACY-0069
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

/// root State（仲裁 §2 の限定スコープ）: keys / subscription / ライフサイクル /
/// dispose P0-P9 統括 / テストフック forwarding / build 合成のみ。
class _TerminalScreenState extends ConsumerState<TerminalScreen>
    with WidgetsBindingObserver
    implements TerminalScreenAccess {
  // ---- 鍵・root 所有の表示状態 ----
  final _ansiTextViewKey = GlobalKey<AnsiTextViewState>();
  final _scrollToBottomKey = GlobalKey<ScrollToBottomButtonState>();
  final _terminalScrollController = ScrollController();
  bool _isDisposed = false;

  // ---- #125 切断UX（root 所有）----
  //
  // 切断/再接続失敗の通知抑制フラグ。初回の切断検知で 1 回だけ表示し、
  // 真の再接続成功（isConnected）まで再表示しない。
  bool _disconnectToastShown = false;

  /// 自動再接続待機中のカウントダウン（残り秒・null = 非表示）。
  final _reconnectCountdown = ReconnectCountdown();

  /// 再接続中パネル（カウントダウン表示タップで開く詳細パネル）。
  bool _reconnectPanelVisible = false;
  final _reconnectIndicatorKey = GlobalKey();
  double _reconnectArrowRight = 100;
  final _headerLink = LayerLink();
  Timer? _reconnectPanelHideTimer;

  /// 通信エラーパネル（切断検知・初期接続エラーで画面下部に表示）。
  String? _commErrorPanelTitle;
  String? _commErrorPanelBody;
  String? _commErrorPanelDetail;
  bool _commErrorPanelExpanded = false;
  Future<void> Function()? _commErrorPanelOnRetry;

  /// 合成アダプタ（port 実装 + 協調オブジェクト生成・破棄統括）。
  late TerminalScreenAdapter _adapter;

  // ===================== TerminalScreenAccess =====================
  @override
  bool get isMounted => mounted;
  @override
  bool get isDisposed => _isDisposed;
  @override
  void markNeedsBuild() => setState(() {});
  @override
  String get connectionId => widget.connectionId;
  @override
  String? get sessionName => widget.sessionName;
  @override
  String? get sessionId => widget.sessionId;
  @override
  int? get lastWindowIndex => widget.lastWindowIndex;
  @override
  String? get lastPaneId => widget.lastPaneId;
  @override
  String? get deepLinkWindowName => widget.deepLinkWindowName;
  @override
  int? get deepLinkPaneIndex => widget.deepLinkPaneIndex;
  @override
  String? get initialPaneId => widget.initialPaneId;
  @override
  PaneContentReader? get injectedPaneContentReader => widget.paneContentReader;
  @override
  DateTime Function()? get herdrCacheClock => widget.herdrCacheClock;
  @override
  HerdrCaretSnapshotReader? get herdrCaretReader => widget.herdrCaretReader;
  @override
  GlobalKey<AnsiTextViewState> get ansiTextViewKey => _ansiTextViewKey;
  @override
  GlobalKey<ScrollToBottomButtonState> get scrollToBottomKey =>
      _scrollToBottomKey;

  // ===================== #125 切断UX =====================

  @override
  void showCommErrorPanel({
    required String title,
    required String body,
    required String detail,
    required Future<void> Function() onRetry,
  }) {
    if (!mounted || _isDisposed) return;

    // 初回表示以降、真の再接続成功（isConnected 遷移）まで再表示しない。
    if (_disconnectToastShown) {
      // 表示中は最新の失敗を反映する。閉じたパネルは再表示しない。
      if (_commErrorPanelBody != null) {
        setState(() {
          _commErrorPanelTitle = title;
          _commErrorPanelBody = body;
          _commErrorPanelDetail = detail;
          _commErrorPanelOnRetry = onRetry;
        });
      }
      return;
    }
    _disconnectToastShown = true;

    setState(() {
      _commErrorPanelTitle = title;
      _commErrorPanelBody = body;
      _commErrorPanelDetail = detail;
      _commErrorPanelExpanded = false;
      _commErrorPanelOnRetry = onRetry;
    });
  }

  @override
  void closeCommErrorPanel() {
    if (!mounted) return;
    setState(() {
      _commErrorPanelBody = null;
      _commErrorPanelDetail = null;
      _commErrorPanelExpanded = false;
    });
  }

  @override
  void onConnectionRestored() {
    // 抑止フラグを解除し（次回切断で再度 1 回表示する）、表示中の
    // 通信エラーパネルは役目を終えたため自動で閉じる。
    _disconnectToastShown = false;
    closeCommErrorPanel();
  }

  @override
  void syncReconnectCountdown({
    required bool isReconnecting,
    required bool isWaitingForNetwork,
    DateTime? nextRetryAt,
  }) {
    if (!isReconnecting) {
      _reconnectPanelHideTimer?.cancel();
      if (_reconnectPanelVisible) {
        setState(() => _reconnectPanelVisible = false);
      }
    }
    _reconnectCountdown.sync(
      isReconnecting: isReconnecting,
      isWaitingForNetwork: isWaitingForNetwork,
      nextRetryAt: nextRetryAt,
    );
  }

  /// 再接続詳細パネルの開閉トグル。開いたまま 10 秒で自動的に閉じる。
  void _toggleReconnectPanel() {
    final box =
        _reconnectIndicatorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      final center = box.localToGlobal(Offset(box.size.width / 2, 0));
      _reconnectArrowRight =
          (MediaQuery.sizeOf(context).width - 16 - center.dx - 7)
              .clamp(12, 238)
              .toDouble();
    }
    setState(() {
      _reconnectPanelVisible = !_reconnectPanelVisible;
      _reconnectPanelHideTimer?.cancel();
      if (_reconnectPanelVisible) {
        _reconnectPanelHideTimer = Timer(const Duration(seconds: 10), () {
          if (mounted && _reconnectPanelVisible) {
            setState(() => _reconnectPanelVisible = false);
          }
        });
      }
    });
  }

  void _toggleCommErrorExpanded() {
    setState(() => _commErrorPanelExpanded = !_commErrorPanelExpanded);
  }

  void _retryCommError() {
    _commErrorPanelOnRetry?.call();
  }

  // ===================== ライフサイクル =====================

  @override
  void initState() {
    super.initState();
    _isDisposed = false;
    WidgetsBinding.instance.addObserver(this);
    _adapter = TerminalScreenAdapter(this);
    _adapter.initialize();
    // follow-scroll の listener 登録（P9 で detach・HEAD initState L809 相当）。
    _adapter.input.scrollFollow.attach(_terminalScrollController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _adapter.lifecycle.initPostFrame();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _adapter.lifecycle.resumePolling();
        break;
      case AppLifecycleState.inactive:
        // 一時的な非アクティブ（通知シェード等）: 600ms 猶予後に復元を予約。
        _adapter.lifecycle.pausePolling();
        _adapter.resize.scheduleBackgroundRestore();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 明確なバックグラウンド化: 猶予を待たず即時復元（TERM-RESIZE-002）。
        _adapter.lifecycle.pausePolling();
        _adapter.resize.onBackgroundNow();
        break;
      case AppLifecycleState.detached:
        _adapter.resize.onBackgroundNow();
        break;
    }
  }

  @override
  void didChangeMetrics() {
    // autoResize の debounce・再フィットは session 側（SessionResizeFlow）に一元化。
    _adapter.resize.onMetricsChanged();
  }

  @override
  void deactivate() {
    // ref.read は deactivate までは安全（dispose では elements から外れている）。
    final sshNotifier = ref.read(sshProvider.notifier);
    sshNotifier.onReconnectSuccess = null;
    sshNotifier.onDisconnectDetected = null;

    // popUntil 等で _disconnect() を経由せずに pop された場合も SSH を切断する。
    // 切断前にリサイズしたウィンドウを自動サイズへ戻す（best-effort・HEAD 同等）。
    final restore = _adapter.runtime.restoreResizedWindows;
    if (restore != null) {
      unawaited(
        restore().then((_) {
          if (sshNotifier.checkConnection()) {
            sshNotifier.disconnect();
          }
        }),
      );
    }
    super.deactivate();
  }

  @override
  void dispose() {
    // P0
    _isDisposed = true;
    // P1 herdr bridge reset（先頭・単独フェーズ）
    _adapter.disposeP1Bridge();
    // P2 removeObserver / Wakelock 解除
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    // P3 ProviderSubscription（root 4 + transfer 2）
    _adapter.disposeP3Subscriptions();
    // P4 poll / tree タイマー
    _adapter.disposeP4Pollers();
    // P5 scrollSend / keyOverlay タイマー（view-input + root 表示用）
    _adapter.disposeP5InputTimers();
    // P6 autoResize / background
    _adapter.disposeP6ResizeTimers();
    // P7 herdr cache / identity / resolved target の null 化
    _adapter.disposeP7Caches();
    // P8 notifier 群（view → herdrDisplay → herdrPaneIndicator → latency）
    _adapter.disposeP8Notifiers();
    // #125: 再接続詳細パネルのタイマーとカウントダウン
    _reconnectPanelHideTimer?.cancel();
    _reconnectCountdown.dispose();
    // P9 ScrollController（listener 解除 → dispose）
    _adapter.disposeP9Detach();
    _terminalScrollController.dispose();
    super.dispose();
  }

  // ===================== テストフック forwarding =====================
  @visibleForTesting
  void overrideScrollSendKindForTesting(ScrollSendKind? kind) =>
      _adapter.input.overrideScrollSendKindForTesting(kind);

  @visibleForTesting
  ScrollModeSource scrollModeSourceForTesting() =>
      _adapter.input.scrollModeSourceForTesting();

  @visibleForTesting
  bool hasBufferedUpdateForTesting() =>
      _adapter.input.hasBufferedUpdateForTesting();

  @visibleForTesting
  String bufferedContentForTesting() =>
      _adapter.input.bufferedContentForTesting();

  @visibleForTesting
  bool canForTesting(PaneCapabilities required) =>
      _adapter.runtime.can(required);

  @visibleForTesting
  PaneCapabilities paneCapabilitiesForTesting() =>
      _adapter.runtime.paneWriter?.capabilities ?? const PaneCapabilities();

  @visibleForTesting
  void switchHerdrTargetForTesting(String paneId) =>
      _adapter.herdr.switchTargetForTesting(paneId);

  @visibleForTesting
  Future<bool> syncAfterHerdrMutationForTesting({
    String eventLabel = 'test mutation sync',
    HerdrSyncTargetPolicy policy = HerdrSyncTargetPolicy.preserveCurrent,
  }) => _adapter.herdr.syncAfterMutationForTesting(
    eventLabel: eventLabel,
    policy: policy,
  );

  @visibleForTesting
  Future<void> splitPaneForTesting(String paneId, SplitDirection direction) =>
      _adapter.mutations.splitPane(paneId, direction);

  @visibleForTesting
  Future<void> renameHerdrPaneForTesting(String paneId, String label) =>
      _adapter.herdr.renamePaneForTesting(paneId, label);

  @visibleForTesting
  Future<void> zoomHerdrPaneForTesting(String paneId) =>
      _adapter.herdr.zoomPaneForTesting(paneId);

  @visibleForTesting
  Future<void> createHerdrTabForTesting(
    String workspaceId, {
    String? label,
    bool? focus,
  }) => _adapter.herdr.createTabForTesting(
    workspaceId,
    label: label,
    focus: focus,
  );

  @visibleForTesting
  Future<void> renameHerdrTabForTesting(String tabId, String label) =>
      _adapter.herdr.renameTabForTesting(tabId, label);

  @visibleForTesting
  Future<void> closeHerdrTabForTesting(String tabId) =>
      _adapter.herdr.closeTabForTesting(tabId);

  @visibleForTesting
  Future<void> focusHerdrPaneDirectionForTesting(SwipeDirection direction) =>
      _adapter.herdr.focusPaneDirectionForTesting(direction);

  @visibleForTesting
  List<String> herdrSwitchEventsForTesting() =>
      _adapter.herdr.switchEventsForTesting();

  @visibleForTesting
  Future<void> loadHistoryForScrollForTesting({
    bool preservePosition = false,
  }) => _adapter.input.loadHistoryForScrollForTesting(
    preservePosition: preservePosition,
  );

  @visibleForTesting
  void sendSpecialKeyForTesting(String tmuxKey) =>
      _adapter.input.sendSpecialKeyForTesting(tmuxKey);

  // ===================== build（合成のみ） =====================

  KeyOverlayPosition get _keyOverlayPosition {
    return switch (ref.read(settingsProvider).keyOverlayPosition) {
      'center' => KeyOverlayPosition.center,
      'belowHeader' => KeyOverlayPosition.belowHeader,
      _ => KeyOverlayPosition.aboveKeyboard,
    };
  }

  @override
  Widget build(BuildContext context) {
    final input = _adapter.input;
    final runtime = _adapter.runtime;
    return TerminalViewShell(
      viewNotifier: runtime.viewNotifier,
      herdrDisplayNotifier: _adapter.herdr.displayNotifier,
      herdrPaneIndicatorNotifier: _adapter.herdr.indicatorNotifier,
      latencyNotifier: runtime.latencyNotifier,
      sshState: (runtime.sshState as SshState?) ?? const SshState(),
      isConnecting: runtime.isConnecting,
      connectionError: runtime.connectionError,
      queuedCount: input.queuedCount,
      backendKind: runtime.backendKind,
      sessionName: widget.sessionName,
      canSendText: runtime.canSendText,
      canSendSpecialKey: runtime.canSendSpecialKey,
      canFocusDirection: runtime.canFocusDirection,
      directInputEnabled: runtime.directInputEnabled,
      mode: input.mode,
      zoomScale: input.zoomScale,
      isZoomed: input.isZoomed,
      effectiveZoom: input.effectiveZoom,
      onExitToNormalMode: input.exitToNormalMode,
      terminalScrollController: _terminalScrollController,
      ansiTextViewKey: _ansiTextViewKey,
      scrollToBottomKey: _scrollToBottomKey,
      keyOverlayState: input.keyOverlayState,
      keyOverlayPosition: _keyOverlayPosition,
      onKeyInput: input.keyInputCallbackFor(),
      onScrollSendKeyInput: input.keyInputCallbackFor(),
      onKeyPressed: input.sendKeyWithOverlay,
      onSpecialKeyPressed: input.sendSpecialKeyWithOverlay,
      onZoomChanged: (scale) => setState(() => input.setZoomScale(scale)),
      onTerminalTap: () => _adapter.ports.showScrollToBottomButton(),
      onArrowSwipe: input.onArrowSwipe,
      onScrollSendTicks: input.onScrollSendTicks,
      onTwoFingerSwipe: input.onTwoFingerSwipe,
      navigableDirections: input.navigableDirections,
      isBottomLock: input.isBottomLock,
      onBottomTap: input.scrollToBottomFollowing,
      onBottomLongPress: input.lockBottom,
      onScrollNotification: input.scrollFollow.onScrollNotification,
      tmuxActions: SelectorLaunchActions(
        contextOf: () {
          final tmux = ref.read(tmuxProvider);
          return SelectorContext(
            sessionName: tmux.activeSessionName,
            sessionId: tmux.activeSession?.id,
            windowIndex: tmux.activeWindowIndex,
            windowId: tmux.activeWindow?.id,
            paneId: tmux.activePaneId,
          );
        },
        onSelectSession: _adapter.mutations.selectSession,
        onSelectWindow: _adapter.mutations.selectWindow,
        onSelectPane: _adapter.mutations.selectPane,
        onSplitPane: (paneId, direction) =>
            _adapter.mutations.splitPane(paneId, direction),
        onResizePane: (pane) => _adapter.resize.handleResizePane(pane),
        onResizeWindow: (window) => _adapter.resize.handleResizeWindow(window),
        onConfirmKillWindow: _adapter.teardown.confirmAndKillWindow,
        onConfirmKillPane: _adapter.teardown.confirmAndKillPane,
        onRenameWindow: (session, window) =>
            _adapter.teardown.showRenameWindowDialog(session, window),
        onCreateWindow: (session) =>
            _adapter.mutations.showCreateWindowDialog(session),
        canTabCrud: runtime.can(const PaneCapabilities(tabCrud: true)),
        canResize: runtime.can(const PaneCapabilities(resize: true)),
        canRename: runtime.can(const PaneCapabilities(rename: true)),
        canClose: runtime.can(const PaneCapabilities(close: true)),
        canSplitPane: runtime.canSplitPane,
        isSafe: () => mounted && !_isDisposed,
        onSheetClosed: () => _adapter.ports.showScrollToBottomButton(),
      ),
      onHerdrWorkspaceTap: _adapter.herdr.showWorkspaceSelector,
      onHerdrTabTap: _adapter.herdr.showTabSelector,
      onHerdrPaneTap: _adapter.herdr.showPaneSelector,
      onHerdrPaneIndicatorTap: _adapter.herdr.showPaneSelector,
      onMenuOpen: () => TerminalMenu.show(
        context: context,
        mode: input.mode,
        isZoomed: input.isZoomed,
        effectiveZoom: input.effectiveZoom,
        onExitToNormalMode: input.exitToNormalMode,
        onEnterScrollSendMode: input.enterScrollSendMode,
        onEnterSelectMode: input.enterSelectMode,
        onResetZoom: () {
          ref.read(settingsProvider.notifier).setZoomFactor(1.0);
          _adapter.ports.resetZoom();
          setState(() => input.setZoomScale(1.0));
        },
        onOpenSettings: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
        onDisconnect: () =>
            _adapter.connection.showDisconnectConfirmation(context),
        onSheetClosed: () => _adapter.ports.showScrollToBottomButton(),
      ),
      onFileBrowser: () => _adapter.transfer.handleFileBrowser(),
      onRetryNow: () => ref.read(sshProvider.notifier).reconnectNow(),
      headerLink: _headerLink,
      reconnectIndicatorKey: _reconnectIndicatorKey,
      reconnectCountdown: _reconnectCountdown.remaining,
      reconnectPanelVisible: _reconnectPanelVisible,
      reconnectArrowRight: _reconnectArrowRight,
      onToggleReconnectPanel: _toggleReconnectPanel,
      commErrorPanelTitle: _commErrorPanelTitle,
      commErrorPanelBody: _commErrorPanelBody,
      commErrorPanelDetail: _commErrorPanelDetail,
      commErrorPanelExpanded: _commErrorPanelExpanded,
      onToggleCommErrorExpanded: _toggleCommErrorExpanded,
      onRetryCommError: _retryCommError,
      onCloseCommError: closeCommErrorPanel,
      onClearQueue: input.clearInputQueue,
      onInputDialog: () => input.showInputDialog(context),
      onToggleDirectInput: () =>
          ref.read(settingsProvider.notifier).toggleDirectInput(),
      onImagePickRequested: () => _adapter.transfer.handleImageTransfer(),
      onCustomButtonEdit: (button) => input.editCustomButton(button, context),
      onManageCustomKeys: () => input.openCustomKeysScreen(context),
    );
  }
}
