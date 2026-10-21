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
import '../../services/backend/domain/pane_frame_reader.dart'
    show PaneHyperlinks;
import '../../services/backend/domain/pane_writer.dart';
import '../../services/backend/domain/wheel_encoder.dart' show ScrollSendKind;
import '../../services/herdr/caret/herdr_caret_snapshot_reader.dart';
import '../../services/herdr/hyperlink/herdr_hyperlink_alignment.dart'
    show HerdrHyperlinkRange;
import '../../services/herdr/hyperlink/herdr_hyperlink_reader.dart';
import '../../services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart'
    show HerdrScrollbackLinkHelperRunner;
import '../../services/tmux/commands/layout.dart' show SplitDirection;
import '../../services/tmux/pane_navigator.dart' show SwipeDirection;
import '../../services/terminal/tmux_key_display.dart' show KeyOverlayPosition;
import '../../widgets/scroll_to_bottom_button.dart'
    show ScrollToBottomButtonState;
import '../settings/settings_screen.dart' show SettingsScreen;
import 'input/terminal_input_mode.dart' show ScrollModeSource;
import 'selector_launch.dart' show SelectorLaunchActions;
import 'selector_sheet.dart' show SelectorContext;
import 'terminal_reconnect_panel.dart' show TerminalReconnectPanel;
import 'terminal_screen_access_impl.dart' show TerminalScreenAccessImpl;
import 'terminal_menu.dart' show TerminalMenu;
import 'terminal_root_bindings.dart' show TerminalScreenAdapter;
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

  /// テスト用: 通常表示のハイパーリンク reader の注入（herdr OSC 8 ハイパー
  /// リンク実験機能）。[herdrCaretReader] と同じ経路（本番は null）。
  final HerdrHyperlinkReader? herdrHyperlinkReader;

  /// テスト用: スクロールモードのリンク読取の SSH 境界（helper runner）の
  /// 注入（herdr OSC 8 ハイパーリンク実験機能）。[herdrCaretReader]
  /// と同じ経路（本番は null）。[herdrCaretReader]/[herdrHyperlinkReader] は
  /// reader 本体を注入するが、これは SSH 境界だけを差し替え、reader 本体
  /// （`HerdrScrollbackLinkReader`）は本番と同じものが動く。
  final HerdrScrollbackLinkHelperRunner? herdrScrollbackLinkHelperRunner;

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
    this.herdrHyperlinkReader,
    this.herdrScrollbackLinkHelperRunner,
  });

  @override
  // inventory: LEGACY-0069
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

/// root State（仲裁 §2 の限定スコープ）: keys / subscription / ライフサイクル /
/// dispose P0-P9 統括 / テストフック forwarding / build 合成のみ。
class _TerminalScreenState extends ConsumerState<TerminalScreen>
    with WidgetsBindingObserver {
  // ---- 鍵・root 所有の表示状態 ----
  final _ansiTextViewKey = GlobalKey<AnsiTextViewState>();
  final _scrollToBottomKey = GlobalKey<ScrollToBottomButtonState>();
  final _terminalScrollController = ScrollController();
  bool _isDisposed = false;

  /// #125 切断UX（通信エラーパネル・再接続詳細パネル）の状態所有者。
  late final TerminalReconnectPanel _reconnectUi = TerminalReconnectPanel(
    markNeedsBuild: () => setState(() {}),
    contextOf: () => context,
    isDisposed: () => !mounted || _isDisposed,
  );

  /// adapter へ渡すアクセサ（root から切り出し・値のみ）。
  late final TerminalScreenAccessImpl _access = TerminalScreenAccessImpl(
    ref: ref,
    connectionId: widget.connectionId,
    sessionNameOf: () => widget.sessionName,
    sessionIdOf: () => widget.sessionId,
    lastWindowIndexOf: () => widget.lastWindowIndex,
    lastPaneIdOf: () => widget.lastPaneId,
    deepLinkWindowNameOf: () => widget.deepLinkWindowName,
    deepLinkPaneIndexOf: () => widget.deepLinkPaneIndex,
    initialPaneIdOf: () => widget.initialPaneId,
    injectedPaneContentReaderOf: () => widget.paneContentReader,
    herdrCacheClockOf: () => widget.herdrCacheClock,
    herdrCaretReaderOf: () => widget.herdrCaretReader,
    herdrHyperlinkReaderOf: () => widget.herdrHyperlinkReader,
    herdrScrollbackLinkHelperRunnerOf: () =>
        widget.herdrScrollbackLinkHelperRunner,
    contextOf: () => context,
    isMountedFn: () => mounted,
    isDisposedFn: () => _isDisposed,
    markNeedsBuildFn: () => setState(() {}),
    ansiTextViewKey: _ansiTextViewKey,
    scrollToBottomKey: _scrollToBottomKey,
    reconnectUi: _reconnectUi,
  );

  /// 合成アダプタ（port 実装 + 協調オブジェクト生成・破棄統括）。
  late TerminalScreenAdapter _adapter;

  // ===================== ライフサイクル =====================

  @override
  void initState() {
    super.initState();
    _isDisposed = false;
    WidgetsBinding.instance.addObserver(this);
    _adapter = TerminalScreenAdapter(_access);
    _adapter.initialize();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _adapter.runtime.isInBackground =
        lifecycle != null && lifecycle != AppLifecycleState.resumed;
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
        _adapter.lifecycle.pausePolling();
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
    _reconnectUi.dispose();
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

  /// 選択モード中にバッファされた hyperlinks（herdr OSC 8 ハイパーリンク
  /// 実験機能）。[bufferedContentForTesting] と同型。
  @visibleForTesting
  PaneHyperlinks? bufferedHyperlinksForTesting() =>
      _adapter.input.bufferedHyperlinksForTesting();

  /// 現在の表示に反映済みの hyperlinks（herdr OSC 8 ハイパーリンク実験機能）。
  /// poll → pendingHyperlinks → view 反映の結果を直接検証する。
  @visibleForTesting
  PaneHyperlinks? currentHyperlinksForTesting() =>
      _adapter.runtime.viewNotifier.value.hyperlinks;

  /// 表示 view（viewNotifier）の更新回数を検証するための購読フック（herdr
  /// OSC 8 ハイパーリンク実験機能: 「本文も hyperlinks も
  /// 変わらない poll では更新を予約しない」の検証用）。戻り値は解除用
  /// コールバック。
  @visibleForTesting
  VoidCallback watchViewForTesting(VoidCallback listener) {
    _adapter.runtime.viewNotifier.addListener(listener);
    return () => _adapter.runtime.viewNotifier.removeListener(listener);
  }

  /// スクロールモードのリンクキャッシュの内容（herdr OSC 8 ハイパーリンク
  /// 実験機能）。fake runner の結果が overlay 用のキャッシュへ
  /// 反映されたこと（またはendSession/cancelPendingで空になったこと）を
  /// 検証する。
  @visibleForTesting
  Map<int, List<HerdrHyperlinkRange>> scrollbackLinksForTesting() =>
      _adapter.herdr.scrollbackLinkCache?.linksByBodyLine ?? const {};

  /// `HerdrScrollbackLinkReader.bodyLinesFor` に実際に渡っている値
  /// （herdr OSC 8 ハイパーリンク実験機能）。
  /// `terminal_root_bindings.dart` の `bodyLinesFor: () =>
  /// viewport.bodyLineTexts() ?? const []` と同じ式を直接呼び、空配列の
  /// まま通ってしまう偽の GREEN でないこと（実際の本文が渡っていること）を
  /// 検証する。
  @visibleForTesting
  List<String> scrollbackLinkBodyLinesForTesting() =>
      _adapter.input.viewport.bodyLineTexts() ?? const [];

  /// select モードでのスクロール確定（[TerminalScrollFollowController]
  /// の `onScrollNotification` の軸ガードを通すだけの合成
  /// `ScrollEndNotification`）を模擬する（herdr OSC 8 ハイパーリンク実験
  /// 機能）。実際のドラッグ操作なしに `onViewportSettled` を発火させ、
  /// スクロールモードのリンク読取を検証する
  /// （`terminal_scroll_follow_controller_test.dart` の
  /// `syntheticVerticalScrollEnd` と同じ手法）。
  @visibleForTesting
  void notifyViewportSettledForTesting(BuildContext context) {
    _adapter.input.scrollFollow.onScrollNotification(
      ScrollEndNotification(
        context: context,
        metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          pixels: 500,
          viewportDimension: 400,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1.0,
        ),
      ),
    );
  }

  /// 実際のスクロール位置を変える（herdr OSC 8 ハイパーリンク実験機能）。
  /// [notifyViewportSettledForTesting] が読む
  /// `viewport.visibleLineRange()` はこの合成通知の metrics ではなく実際の
  /// スクロール位置から計算される
  /// （`TerminalScrollFollowController._notifyViewportSettled`）ため、
  /// 「往復済みの窓を再度要求して `ScrollbackLinkCache.hasFetched` に
  /// 弾かれ、配線の有無に関わらず往復 0 回になる」偽の GREEN を避けるには、
  /// [notifyViewportSettledForTesting] の前に実際の位置を変える必要がある。
  @visibleForTesting
  void jumpToLineFromTopForTesting(int lineIndex) =>
      _adapter.input.viewport.jumpToLineFromTop(lineIndex);

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
      scrollbackLinkCache: _adapter.herdr.scrollbackLinkCache,
      currentScrollbackSnapshotIdentity:
          _adapter.input.scrollFollow.currentSnapshotIdentity,
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
      headerLink: _reconnectUi.headerLink,
      reconnectIndicatorKey: _reconnectUi.indicatorKey,
      reconnectCountdown: _reconnectUi.countdown.remaining,
      reconnectPanelVisible: _reconnectUi.panelVisible,
      reconnectArrowRight: _reconnectUi.arrowRight,
      onToggleReconnectPanel: _reconnectUi.togglePanel,
      commErrorPanelTitle: _reconnectUi.title,
      commErrorPanelBody: _reconnectUi.body,
      commErrorPanelDetail: _reconnectUi.detail,
      commErrorPanelExpanded: _reconnectUi.expanded,
      onToggleCommErrorExpanded: _reconnectUi.toggleExpanded,
      onRetryCommError: _reconnectUi.retry,
      onCloseCommError: _reconnectUi.close,
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
