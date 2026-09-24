import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/custom_keys_provider.dart' show customKeysProvider;
import '../../../screens/custom_keys/custom_keys_screen.dart'
    show CustomKeysScreen;
import '../../../services/backend/domain/pane_frame_reader.dart' show PaneCaret;
import '../../../services/backend/domain/wheel_encoder.dart'
    show ScrollSendKind;
import '../../../services/custom_keys/custom_key_button.dart'
    show CustomKeyButton, CustomKeyStep;
import '../../../services/tmux/pane_navigator.dart' show SwipeDirection;
import '../../../widgets/key_overlay_widget.dart' show KeyOverlayState;
import '../../../widgets/dialogs/custom_key_button_editor_dialog.dart'
    show CustomKeyButtonEditorDialog;
import '../widgets/ansi_terminal_model.dart' show KeyInputEvent, TerminalMode;
import 'terminal_input_mode.dart' show ScrollModeSource, TerminalBufferedUpdate;
import 'terminal_input_ports.dart'
    show
        TerminalInputCapabilities,
        TerminalInputHost,
        TerminalNavigationPort,
        TerminalPaneSendPort,
        TerminalScrollbackPort,
        TerminalTargetIdentityValidator;
import 'terminal_key_sender.dart' show TerminalKeySender;
import 'terminal_mode_controller.dart' show TerminalModeController;
import 'terminal_navigation_controller.dart' show TerminalNavigationController;
import 'terminal_scroll_follow_controller.dart'
    show TerminalScrollFollowController;
import 'terminal_scroll_send_controller.dart' show TerminalScrollSendController;
import 'terminal_viewport_port.dart' show TerminalViewportPort;

/// 入力ダイアログの内容 Widget を組み立てるビルダー（ui 領域が提供）。
typedef TerminalInputDialogBuilder =
    Widget Function({
      required String initialValue,
      required void Function(String value) onValueChanged,
      required Future<void> Function(String value) onSend,
    });

/// view-input の facade。root State がただ 1 つ保持する（`_input`）。
///
/// AnsiTextView / SpecialKeysBar の callback 配線とモード遷移を調停し、外領域
/// （session-runtime / ui）へ mode ・各種 API を提供する。`_savedCommandInput`
/// （C8）を所有する。協調オブジェクトはすべて `late final`（root の初期化時に
/// 生成）。context は保持せず、必要ならメソッド引数で受ける。
class TerminalInputCoordinator {
  TerminalInputCoordinator({
    required this.ref,
    required this.send,
    required this.caps,
    required this.scrollback,
    required this.nav,
    required this.validator,
    required this.host,
    required this.viewport,
    required void Function() onApplyBuffered,
    required bool Function() getCanCopyMode,
    this.dialogBuilder,
  }) : _onApplyBuffered = onApplyBuffered,
       _getCanCopyMode = getCanCopyMode {
    _mode = TerminalModeController(
      ref: ref,
      scrollback: scrollback,
      validator: validator,
    );
    _scrollSend = TerminalScrollSendController(
      ref: ref,
      send: send,
      caps: caps,
      host: host,
      copyModeDetected: () => _mode.isCopyModeDetected,
    );
    _keySender = TerminalKeySender(
      ref: ref,
      send: send,
      caps: caps,
      host: host,
      copyModeDetected: () => _mode.isCopyModeDetected,
    );
    _follow = TerminalScrollFollowController(
      scrollback: scrollback,
      viewport: viewport,
      nav: nav,
      host: host,
      validator: validator,
      mode: () => _mode.mode,
    );
    _navigation = TerminalNavigationController(ref: ref, caps: caps, nav: nav);

    // 上端オーバースクロール → select 遷移（TERM-SCROLL-002/003 固定）。
    _follow.onEnterSelectForHistory = () {
      _mode.applySelectForHistory();
      host.markNeedsBuild();
    };
  }

  final WidgetRef ref;
  final TerminalPaneSendPort send;
  final TerminalInputCapabilities caps;
  final TerminalScrollbackPort scrollback;
  final TerminalNavigationPort nav;
  final TerminalTargetIdentityValidator validator;
  final TerminalInputHost host;
  final TerminalViewportPort viewport;
  final void Function() _onApplyBuffered;
  final bool Function() _getCanCopyMode;
  final TerminalInputDialogBuilder? dialogBuilder;

  late final TerminalModeController _mode;
  late final TerminalScrollSendController _scrollSend;
  late final TerminalKeySender _keySender;
  late final TerminalScrollFollowController _follow;
  late final TerminalNavigationController _navigation;

  // EnterCommand 入力内容保持（ボトムシートを閉じても保持・C8）。
  String _savedCommandInput = '';

  // --- 公開 getters（root build / ui / session） ---

  TerminalMode get mode => _mode.mode;
  ScrollModeSource get scrollModeSource => _mode.source;
  bool get isCopyModeDetected => _mode.isCopyModeDetected;
  double get zoomScale => _mode.zoomScale;
  double get effectiveZoom => _mode.effectiveZoom;
  bool get isZoomed => _mode.isZoomed;
  bool get isBottomLock => _follow.isBottomLock;
  bool get isUserScrollDragging => _follow.isUserScrollDragging;
  bool get shouldFollowBottom => _follow.shouldFollowBottom;

  /// 送信キューに滞留している入力数（root の `queuedCount` 表示用・HEAD
  /// `_inputQueue.length` と同一）。
  int get queuedCount => _keySender.queuedLength;

  /// C7 選択バッファ内容（root のテストフック转发用）。
  bool get hasBufferedUpdate => _mode.hasBufferedUpdate;
  String get bufferedContent => _mode.bufferedContent;

  /// ピンチズームのプレビュー倍率を設定（AnsiTextView.onZoomChanged 相当）。
  void setZoomScale(double scale) => _mode.onZoomChanged(scale);

  /// FAB タップ（HEAD `_scrollToBottomFollowing`・ロック中は解除して追従）。
  void scrollToBottomFollowing() {
    if (_follow.isBottomLock) _follow.toggleBottomLock(false);
    _follow.scrollToBottomFollowing();
  }

  /// FAB 長押し（HEAD L3519-3521・ロック ON + 最下部追従）。
  void lockBottom() {
    _follow.toggleBottomLock(true);
    _follow.scrollToBottomFollowing();
  }

  /// 送信キューを破棄（root の `ClearQueue` 導線・HEAD `_inputQueue.clear`）。
  void clearInputQueue() => _keySender.clearQueue();

  /// キーオーバーレイの表示状態（root がシェルへ渡す・入力側と共有）。
  KeyOverlayState get keyOverlayState => _keySender.keyOverlayState;

  TerminalScrollFollowController get scrollFollow => _follow;

  // --- モード遷移（副作用順は HEAD L1036-1143 を厳守・R1/R2） ---

  /// 通常モードへ戻す（TERM-MODE-RESET-001）。
  void resetTerminalMode() {
    _scrollSend.discard();
    _mode.restoreScrollSendZoom();
    _mode.applyNormal();
    _follow.resetFollowFlags();
    host.markNeedsBuild();
  }

  /// scrollSend モードへ入る（TERM-MODE-UI-001）。
  void enterScrollSendMode() {
    _scrollSend.discard();
    _mode.applyScrollSendFitZoom();
    _mode.applyScrollSend();
    _follow.resetFollowFlags();
    host.markNeedsBuild();
    viewport.scrollToBottom();
    // モード切替で AnsiTextView が再構築され position が取り替わるため、
    // 再構築後に currentState を再取得して末尾スクロールを再発行する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      viewport.scrollToBottom();
    });
  }

  /// select モードへ入る（TERM-MODE-UI-002）。
  void enterSelectMode() {
    _scrollSend.discard();
    _mode.restoreScrollSendZoom();
    _mode.applySelectManual();
    _follow.resetFollowFlags();
    host.markNeedsBuild();
    if (_getCanCopyMode()) {
      // inventory: TERM-COPY-001
      // ignore: unawaited_futures
      _keySender.enterTmuxCopyMode();
    }
    _follow.loadHistoryForScroll();
  }

  /// normal モードへ戻る（TERM-MODE-UI-003）。
  void exitToNormalMode() {
    _scrollSend.discard();
    _mode.restoreScrollSendZoom();
    if (_mode.mode == TerminalMode.select) {
      if (_getCanCopyMode()) {
        // ignore: unawaited_futures
        _keySender.cancelTmuxCopyMode();
      }
      _onApplyBuffered();
    }
    _mode.applyNormal();
    host.markNeedsBuild();
  }

  // --- session poll が呼ぶ自動遷移（H4・D2） ---

  /// tmux copy-mode の自動検出（poll → select(tmux)。fromScrollSend は
  /// scrollSend → select の遷移経路）。
  void handleTmuxCopyModeDetected({required bool fromScrollSend}) {
    _mode.applySelectTmux(fromScrollSend: fromScrollSend);
    _follow.resetFollowFlags();
    if (fromScrollSend) {
      _scrollSend.discard();
      _mode.restoreScrollSendZoom();
      send.recordHerdrSwitchEvent('copy-mode auto transition from scrollSend');
    }
    host.markNeedsBuild();
  }

  /// tmux copy-mode の終了（poll → normal 復帰 + バッファ適用）。
  void handleTmuxCopyModeEnded() {
    _mode.applyTmuxEnded();
    host.markNeedsBuild();
    _onApplyBuffered();
  }

  /// 最後に観測した paneMode を scrollSend controller へ転送（H4②）。
  void observePaneMode(String paneMode) {
    _scrollSend.observePaneMode(paneMode);
  }

  // --- C7 選択バッファ（session 向け） ---

  void captureSelectUpdate({
    required String content,
    PaneCaret? caret,
    Object? targetIdentity,
  }) {
    _mode.captureSelectUpdate(
      content: content,
      caret: caret,
      targetIdentity: targetIdentity,
    );
  }

  TerminalBufferedUpdate? takeBufferedUpdate() => _mode.takeBufferedUpdate();

  // --- C1 / C2（session 向け） ---

  /// キャレット位置へスクロール（guarded・100ms + mounted/_isDisposed）。session
  /// poll の初回表示・caret 追従が呼ぶ。
  void scrollToCaret() => _follow.scrollToCaret();

  /// キューされた入力を送信（session `_onReconnectSuccess` が呼ぶ・C2）。
  Future<void> flushInputQueue() => _keySender.flushInputQueue();

  // --- AnsiTextView / SpecialKeysBar 配線（root build 用） ---

  /// onKeyInput コールバック（scrollSend 中は専用ハンドラ・それ以外は受信可なら
  /// 通常ハンドラ・不可なら null・HEAD L3430-3436 と同一）。
  void Function(KeyInputEvent)? keyInputCallbackFor() {
    if (_mode.mode == TerminalMode.scrollSend) {
      return _keySender.handleScrollSendKeyInput;
    }
    return caps.canSendText ? _keySender.handleKeyInput : null;
  }

  /// onScrollSendTicks 配線（scrollSend モード + copy-mode 未検出のみ集積）。
  void onScrollSendTicks(int ticks) {
    if (_mode.mode != TerminalMode.scrollSend) return;
    if (_mode.isCopyModeDetected) return;
    _scrollSend.onTicks(ticks);
  }

  /// onArrowSwipe 配線（HE の他能力ゲートは root build 側の caps で行う）。
  void Function(String)? get onArrowSwipe =>
      caps.canSendSpecialKey ? _keySender.sendSpecialKeyWithOverlay : null;

  /// onTwoFingerSwipe 配線。
  void Function(SwipeDirection)? get onTwoFingerSwipe =>
      caps.canFocusDirection ? _navigation.handleTwoFingerSwipe : null;

  /// navigableDirections 配線。
  Map<SwipeDirection, bool>? get navigableDirections =>
      caps.canFocusDirection ? _navigation.navigableDirections() : null;

  /// SpecialKeysBar.onKeyPressed 配線。
  void sendKeyWithOverlay(String key) => _keySender.sendKeyWithOverlay(key);

  /// SpecialKeysBar.onSpecialKeyPressed 配線。
  void sendSpecialKeyWithOverlay(String tmuxKey) =>
      _keySender.sendSpecialKeyWithOverlay(tmuxKey);

  /// onTap（FAB 表示）配線。
  void showScrollToBottomButton() => host.showScrollToBottomButton();

  /// zoom リセット（ui のメニュー・Raw AnsiTextView 委譲）。
  void resetZoom() => viewport.resetZoom();

  // --- 入力ダイアログ（C8） ---

  /// コマンド入力ボトムシートを開く（context は保持せず引数で受ける）。
  Future<void> showInputDialog(BuildContext context) async {
    final builder = dialogBuilder;
    if (builder == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => builder(
        initialValue: _savedCommandInput,
        onValueChanged: (value) {
          // 入力内容をリアルタイムで保存。
          _savedCommandInput = value;
        },
        onSend: (value) async {
          // inventory: TERM-INPUT-008
          await _keySender.sendMultilineText(value);
          // 送信成功したら入力内容をクリア。
          _savedCommandInput = '';
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
      ),
    );
    host.showScrollToBottomButton();
  }

  // --- カスタムキー導線 ---

  Future<void> editCustomButton(
    CustomKeyButton button,
    BuildContext context,
  ) async {
    final result = await showDialog<(String, List<CustomKeyStep>)>(
      context: context,
      builder: (_) => CustomKeyButtonEditorDialog(
        initialLabel: button.label,
        initialSteps: button.steps,
        onDelete: () =>
            ref.read(customKeysProvider.notifier).deleteButton(button.id),
      ),
    );
    if (result != null && context.mounted) {
      ref
          .read(customKeysProvider.notifier)
          .updateButton(button.id, label: result.$1, steps: result.$2);
    }
  }

  void openCustomKeysScreen(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CustomKeysScreen()));
  }

  // --- テストフック（root State が同名で転送） ---

  @visibleForTesting
  ScrollModeSource scrollModeSourceForTesting() => _mode.source;

  @visibleForTesting
  bool hasBufferedUpdateForTesting() => _mode.hasBufferedUpdate;

  @visibleForTesting
  String bufferedContentForTesting() => _mode.bufferedContent;

  @visibleForTesting
  void overrideScrollSendKindForTesting(ScrollSendKind? kind) {
    _scrollSend.setKindOverrideForTesting(kind);
  }

  @visibleForTesting
  Future<void> loadHistoryForScrollForTesting({bool preservePosition = false}) {
    return _follow.loadHistoryForScroll(preservePosition: preservePosition);
  }

  @visibleForTesting
  void sendSpecialKeyForTesting(String tmuxKey) {
    _keySender.sendSpecialKeyForTesting(tmuxKey);
  }

  /// P5: scrollSend タイマーとキーオーバーレイを破棄する（root dispose が呼ぶ）。
  void disposeTimers() {
    _scrollSend.dispose();
    _keySender.dispose();
  }

  /// P9: follow の ScrollController リスナーを解除する（root dispose が呼ぶ）。
  void detachScroll() {
    _follow.detach();
  }
}
