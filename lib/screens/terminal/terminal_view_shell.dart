import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/image_transfer_provider.dart';
import '../../providers/ssh_provider.dart';
import '../../providers/tmux_provider.dart';
import '../../services/backend/domain/multiplexer_backend.dart';
import '../../services/custom_keys/custom_key_button.dart';
import '../../services/terminal/tmux_key_display.dart';
import '../../services/tmux/pane_navigator.dart';
import '../../theme/design_colors.dart';
import '../../widgets/key_overlay_widget.dart';
import '../../widgets/scroll_to_bottom_button.dart';
import '../../l10n/l10n_ext.dart';
import 'herdr/herdr_types.dart';
import 'selector_launch.dart';
import 'session/session_models.dart';
import 'terminal_breadcrumb.dart';
import 'terminal_overlays.dart';
import 'terminal_reconnect_overlays.dart';
import 'terminal_shell_areas.dart';
import 'widgets/disconnect_bar.dart';
import 'widgets/ansi_text_view.dart';

/// ターミナル画面の表示ツリー合成ウィジェット。
///
/// root State は「状態・ライフサイクル・コールバック結線」のみを担い、表示
/// ツリー本体（ブレッドクラム・ターミナル表示・ペインインジケータ・スクロール
/// ボタン・キーオーバーレイ・画像進捗・特殊キーバー・overlay 群）は本ウィジェット
/// が構築する。データ（notifier）とコールバックはすべて root から props で注入され、
/// プロバイダ watch はツリー内の Consumer に閉じる（親 build を再実行しない・BUG-3
/// 安定性の維持）。
class TerminalViewShell extends ConsumerWidget {
  // ---- 表示データ（root 所有の notifier / 状態）----
  final ValueListenable<TerminalViewData> viewNotifier;
  final ValueListenable<HerdrDisplayData?> herdrDisplayNotifier;
  final ValueListenable<HerdrPaneIndicatorData?> herdrPaneIndicatorNotifier;
  final ValueListenable<int> latencyNotifier;
  final SshState sshState;
  final bool isConnecting;
  final String? connectionError;
  final int queuedCount;
  final MultiplexerBackendKind backendKind;
  final String? sessionName;

  // ---- 能力（root の `_can*` から入力）----
  final bool canSendText;
  final bool canSendSpecialKey;
  final bool canFocusDirection;
  final bool directInputEnabled;

  // ---- モード・ズーム ----
  final TerminalMode mode;
  final double zoomScale;
  final bool isZoomed;
  final double effectiveZoom;
  final VoidCallback onExitToNormalMode;

  // ---- コントローラ類（root 生成・所有）----
  final ScrollController terminalScrollController;
  final GlobalKey<AnsiTextViewState> ansiTextViewKey;
  final GlobalKey<ScrollToBottomButtonState> scrollToBottomKey;
  final KeyOverlayState keyOverlayState;
  final KeyOverlayPosition keyOverlayPosition;

  // ---- ターミナル表示のコールバック ----
  final void Function(KeyInputEvent)? onKeyInput;
  final void Function(KeyInputEvent)? onScrollSendKeyInput;
  final void Function(String key) onKeyPressed;
  final void Function(String tmuxKey) onSpecialKeyPressed;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onTerminalTap;
  final void Function(String direction)? onArrowSwipe;
  final void Function(int ticks)? onScrollSendTicks;
  final void Function(SwipeDirection)? onTwoFingerSwipe;
  final Map<SwipeDirection, bool>? navigableDirections;
  final bool isBottomLock;
  final VoidCallback onBottomTap;
  final VoidCallback onBottomLongPress;

  /// スクロール通知のフォロー制御（view-input の follow controller）。
  /// null なら本シェル内の最小ハンドラ（scrollSend 時のイベント消費）を使う。
  final bool Function(ScrollNotification)? onScrollNotification;

  // ---- ブレッドクラム selectors / メニュー ----
  final SelectorLaunchActions tmuxActions;
  final VoidCallback? onHerdrWorkspaceTap;
  final VoidCallback? onHerdrTabTap;
  final VoidCallback? onHerdrPaneTap;
  final VoidCallback? onHerdrPaneIndicatorTap;
  final VoidCallback onMenuOpen;
  final VoidCallback? onFileBrowser;

  // ---- 接続エラー / 再接続 ----
  final VoidCallback onRetryNow;
  final VoidCallback onClearQueue;

  // ---- #125 切断UX（root 所有状態の注入）----
  final LayerLink headerLink;
  final GlobalKey reconnectIndicatorKey;
  final ValueListenable<int?> reconnectCountdown;
  final bool reconnectPanelVisible;
  final double reconnectArrowRight;
  final VoidCallback onToggleReconnectPanel;
  final String? commErrorPanelTitle;
  final String? commErrorPanelBody;
  final String? commErrorPanelDetail;
  final bool commErrorPanelExpanded;
  final VoidCallback onToggleCommErrorExpanded;
  final VoidCallback onRetryCommError;
  final VoidCallback onCloseCommError;

  // ---- 特殊キーバー ----
  final VoidCallback? onInputDialog;
  final VoidCallback onToggleDirectInput;
  final VoidCallback? onImagePickRequested;
  final void Function(CustomKeyButton)? onCustomButtonEdit;
  final VoidCallback? onManageCustomKeys;

  const TerminalViewShell({
    super.key,
    required this.viewNotifier,
    required this.herdrDisplayNotifier,
    required this.herdrPaneIndicatorNotifier,
    required this.latencyNotifier,
    required this.sshState,
    required this.isConnecting,
    this.connectionError,
    required this.queuedCount,
    required this.backendKind,
    this.sessionName,
    required this.canSendText,
    required this.canSendSpecialKey,
    required this.canFocusDirection,
    required this.directInputEnabled,
    required this.mode,
    required this.zoomScale,
    required this.isZoomed,
    required this.effectiveZoom,
    required this.onExitToNormalMode,
    required this.terminalScrollController,
    required this.ansiTextViewKey,
    required this.scrollToBottomKey,
    required this.keyOverlayState,
    required this.keyOverlayPosition,
    this.onKeyInput,
    this.onScrollSendKeyInput,
    required this.onKeyPressed,
    required this.onSpecialKeyPressed,
    required this.onZoomChanged,
    required this.onTerminalTap,
    this.onArrowSwipe,
    this.onScrollSendTicks,
    this.onTwoFingerSwipe,
    this.navigableDirections,
    required this.isBottomLock,
    required this.onBottomTap,
    required this.onBottomLongPress,
    this.onScrollNotification,
    required this.tmuxActions,
    this.onHerdrWorkspaceTap,
    this.onHerdrTabTap,
    this.onHerdrPaneTap,
    this.onHerdrPaneIndicatorTap,
    required this.onMenuOpen,
    this.onFileBrowser,
    required this.onRetryNow,
    required this.headerLink,
    required this.reconnectIndicatorKey,
    required this.reconnectCountdown,
    required this.reconnectPanelVisible,
    required this.reconnectArrowRight,
    required this.onToggleReconnectPanel,
    this.commErrorPanelTitle,
    this.commErrorPanelBody,
    this.commErrorPanelDetail,
    required this.commErrorPanelExpanded,
    required this.onToggleCommErrorExpanded,
    required this.onRetryCommError,
    required this.onCloseCommError,
    required this.onClearQueue,
    this.onInputDialog,
    required this.onToggleDirectInput,
    this.onImagePickRequested,
    this.onCustomButtonEdit,
    this.onManageCustomKeys,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ローカル状態を使用（ref.watchは使わない）
    // 注意: tmuxProviderは各Consumer内でref.watchして取得する
    // これにより親build()がポーリングで呼ばれず、BottomSheetが安定する
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              CompositedTransformTarget(
                link: headerLink,
                child: _buildBreadcrumbRow(context, ref),
              ),
              // 切断/再接続/エラー状態をヘッダー直下の赤バーで示す
              // （タップ不可・状態表示専用）。
              if (sshState.isReconnecting ||
                  sshState.isDisconnected ||
                  sshState.hasError)
                const DisconnectBar(),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    border: Border.all(
                      // H2: scrollSend 中もモード枠線を表示（normal 以外すべて）
                      color: mode != TerminalMode.normal
                          ? DesignColors.warning
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: Stack(
                    children: [
                      _buildTerminalArea(context, ref),
                      TerminalPaneIndicatorArea(
                        backendKind: backendKind,
                        herdrPaneIndicatorNotifier: herdrPaneIndicatorNotifier,
                        onHerdrPaneIndicatorTap: onHerdrPaneIndicatorTap,
                        tmuxActions: tmuxActions,
                      ),
                      // スクロールボタン: ターミナルエリア右下
                      Positioned(
                        bottom: 8,
                        right: 16,
                        child: ScrollToBottomButton(
                          key: scrollToBottomKey,
                          locked: isBottomLock,
                          onPressed: onBottomTap,
                          onLongPress: onBottomLongPress,
                        ),
                      ),
                      // キーオーバーレイ
                      KeyOverlayWidget(
                        overlayState: keyOverlayState,
                        position: keyOverlayPosition,
                      ),
                      // 通信エラーパネル（下からスライドしてフェードイン）。
                      TerminalCommErrorOverlay(
                        title: commErrorPanelTitle,
                        body: commErrorPanelBody,
                        detail: commErrorPanelDetail,
                        expanded: commErrorPanelExpanded,
                        onToggleExpanded: onToggleCommErrorExpanded,
                        onRetry: onRetryCommError,
                        onClose: onCloseCommError,
                      ),
                    ],
                  ),
                ),
              ),
              // 画像アップロード進捗バー
              Consumer(
                builder: (context, ref, _) {
                  final transfer = ref.watch(imageTransferProvider);
                  final isActive =
                      transfer.phase == ImageTransferPhase.uploading ||
                      transfer.phase == ImageTransferPhase.converting;
                  if (!isActive) return const SizedBox.shrink();
                  return LinearProgressIndicator(
                    value: transfer.uploadProgress > 0
                        ? transfer.uploadProgress
                        : null,
                    minHeight: 3,
                    backgroundColor: Colors.transparent,
                  );
                },
              ),
              // 特殊キー入力バー（`_canSendSpecialKey` が false のときは
              // 未接続バナーを表示し mutation 導線を隠す）
              if (!canSendSpecialKey)
                DisconnectedBanner(isDark: isDark)
              else
                TerminalSpecialKeysArea(
                  onKeyPressed: onKeyPressed,
                  onSpecialKeyPressed: onSpecialKeyPressed,
                  onInputDialog: onInputDialog,
                  directInputEnabled: directInputEnabled,
                  onToggleDirectInput: onToggleDirectInput,
                  onImagePickRequested: onImagePickRequested,
                  onCustomButtonEdit: onCustomButtonEdit,
                  onManageCustomKeys: onManageCustomKeys,
                ),
            ],
          ),
          // ローディングオーバーレイ
          if (isConnecting)
            Container(
              color: isDark ? Colors.black54 : Colors.white70,
              child: const Center(child: CircularProgressIndicator()),
            ),
          // 再接続詳細パネル（ヘッダーの ReconnectingIndicator タップで開閉）。
          TerminalReconnectDetailOverlay(
            headerLink: headerLink,
            visible: reconnectPanelVisible,
            isReconnecting: sshState.isReconnecting,
            countdown: reconnectCountdown,
            attempt: sshState.reconnectAttempt,
            arrowRight: reconnectArrowRight,
          ),
        ],
      ),
    );
  }

  /// ブレッドクラム行（backend 分岐）。
  Widget _buildBreadcrumbRow(BuildContext context, WidgetRef ref) {
    // inventory: TERM-DIALOG-003
    if (backendKind == MultiplexerBackendKind.herdr) {
      return ValueListenableBuilder<HerdrDisplayData?>(
        valueListenable: herdrDisplayNotifier,
        builder: (context, display, _) {
          return TerminalBreadcrumbHeader(
            data: _buildHerdrBreadcrumb(context, display),
            mode: mode,
            onExitToNormalMode: onExitToNormalMode,
            isZoomed: isZoomed,
            effectiveZoom: effectiveZoom,
            latencyNotifier: latencyNotifier,
            sshState: sshState,
            queuedCount: queuedCount,
            onRetryNow: onRetryNow,
            reconnectCountdown: reconnectCountdown,
            reconnectIndicatorKey: reconnectIndicatorKey,
            onToggleReconnectPanel: onToggleReconnectPanel,
            canSendSpecialKey: canSendSpecialKey,
            onFileBrowser: onFileBrowser,
            onMenuOpen: onMenuOpen,
          );
        },
      );
    }
    return Consumer(
      builder: (context, ref, _) {
        final tmuxState = ref.watch(tmuxProvider);
        return TerminalBreadcrumbHeader(
          data: buildTmuxBreadcrumb(
            tmuxState: tmuxState,
            isDisconnected: !canSendSpecialKey,
            fallbackSessionName: sessionName ?? '',
            l10n: context.l10n,
            onSessionTap: () =>
                showSessionSelectorTap(context, tmuxActions, tmuxState),
            onWindowTap: () => showWindowSelectorTap(
              context,
              tmuxActions,
              tmuxState,
              showResizeWindowChooser: () =>
                  showResizeWindowChooserTap(context, tmuxActions, tmuxState),
            ),
            onPaneTap: () => showPaneSelectorTap(
              context,
              tmuxActions,
              tmuxState,
              showResizePaneChooser: () =>
                  showResizePaneChooserTap(context, tmuxActions, tmuxState),
            ),
          ),
          mode: mode,
          onExitToNormalMode: onExitToNormalMode,
          isZoomed: isZoomed,
          effectiveZoom: effectiveZoom,
          latencyNotifier: latencyNotifier,
          sshState: sshState,
          queuedCount: queuedCount,
          onRetryNow: onRetryNow,
          reconnectCountdown: reconnectCountdown,
          reconnectIndicatorKey: reconnectIndicatorKey,
          onToggleReconnectPanel: onToggleReconnectPanel,
          canSendSpecialKey: canSendSpecialKey,
          onFileBrowser: onFileBrowser,
          onMenuOpen: onMenuOpen,
        );
      },
    );
  }

  BreadcrumbData _buildHerdrBreadcrumb(
    BuildContext context,
    HerdrDisplayData? display,
  ) {
    return buildHerdrBreadcrumb(
      workspaceLabel: display?.workspaceLabel,
      tabId: display?.tabId,
      tabLabel: display?.tabLabel,
      paneId: display?.paneId,
      fallbackSessionName: sessionName ?? '',
      l10n: context.l10n,
      onSessionTap: onHerdrWorkspaceTap ?? () {},
      onWindowTap: onHerdrTabTap ?? () {},
      onPaneTap: onHerdrPaneTap ?? () {},
    );
  }

  /// ターミナル表示: ValueListenableBuilder + Consumer。
  ///
  /// ポーリング更新は ValueNotifier 経由でこのサブツリーのみリビルドする。
  Widget _buildTerminalArea(BuildContext context, WidgetRef ref) {
    return RepaintBoundary(
      child: ValueListenableBuilder<TerminalViewData>(
        valueListenable: viewNotifier,
        builder: (context, viewData, _) {
          return Consumer(
            builder: (context, ref, _) {
              final cursor = ref.watch(
                tmuxProvider.select(
                  (s) => (
                    x: s.activePane?.cursorX ?? 0,
                    y: s.activePane?.cursorY ?? 0,
                  ),
                ),
              );
              return NotificationListener<ScrollNotification>(
                // inventory: TERM-SCROLL-002
                onNotification:
                    onScrollNotification ?? _onTerminalScrollNotification,
                child: AnsiTextView(
                  key: ansiTextViewKey,
                  text: viewData.content,
                  paneWidth: viewData.paneWidth,
                  paneHeight: viewData.paneHeight,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.9),
                  // 操作能力（`_can`）に応じてキー入力・スワイプ操作を無効化
                  // inventory: TERM-INPUT-001
                  // scrollSend 中は専用キーハンドラへルート（H3・C8）
                  onKeyInput: mode == TerminalMode.scrollSend
                      ? onScrollSendKeyInput
                      : (canSendText ? onKeyInput : null),
                  onTap: onTerminalTap,
                  mode: mode,
                  zoomEnabled: true,
                  onZoomChanged: onZoomChanged,
                  verticalScrollController: terminalScrollController,
                  cursorX: cursor.x,
                  cursorY: cursor.y,
                  // Phase 4: herdr caret（非 null 時は
                  // visible/位置/範囲で描画判定。null は従来）。
                  caret: viewData.caret,
                  // inventory: TERM-INPUT-005
                  onArrowSwipe: canSendSpecialKey ? onArrowSwipe : null,
                  // inventory: TERM-SCROLL-006
                  onScrollSendTicks: onScrollSendTicks,
                  // inventory: TERM-NAV-007
                  onTwoFingerSwipe: canFocusDirection ? onTwoFingerSwipe : null,
                  navigableDirections: canFocusDirection
                      ? navigableDirections
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }

  bool _onTerminalScrollNotification(ScrollNotification notification) {
    // モードが scrollSend のときはスクロール通知を親へ伝播しない
    // （scrollSend ドラッグが横スクロールへ漏れないようにする・元実装同等）。
    if (mode == TerminalMode.scrollSend) return true;
    return false;
  }

  /// ペインインジケータ（backend 分岐: herdr = notifier / tmux = Consumer）。
}
