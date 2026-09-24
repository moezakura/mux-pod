// P4: root State の合成アダプタ（ui/root 領域）— 協調オブジェクト生成と
// dispose フェーズ統括のみ。
//
// `_TerminalScreenState`（terminal_screen.dart のシム + root State）から
// 「各領域の協調オブジェクトを生成し、SessionEnv を組み立てて注入する」責務を
// 切り出し、root State を「鍵・ライフサイクル・dispose 統括・テストフック転送・
// build 合成」に限定する（arbitration §2・500 行制約）。
//
// ポート実装は [TerminalScreenPorts]（terminal_screen_ports.dart）が担い、
// 本クラスはその検査対象（[TerminalPortSource]）を実装する。依存方向:
// root → adapter → ports ← session/herdr/view-input。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../providers/tmux_provider.dart';
import '../../services/tmux/tmux_facade.dart';
import 'download_snackbar_display.dart' show downloadSnackBarDisplay;
import 'herdr/herdr_controller.dart';
import 'herdr/herdr_env.dart';
import 'herdr/herdr_types.dart';
import 'herdr_label_input_dialog.dart' show HerdrLabelInputDialog;
import 'input/terminal_input_coordinator.dart';
import 'input/terminal_viewport_port.dart';
import 'input_dialog_content.dart' show InputDialogContent;
import 'session/session_confirm_dialogs.dart';
import 'session/session_connection.dart';
import 'session/session_env.dart';
import 'session/session_lifecycle.dart';
import 'session/session_mutations.dart';
import 'session/session_mutations_teardown.dart';
import 'session/session_poll.dart';
import 'session/session_readers.dart';
import 'session/session_resize.dart';
import 'session/session_runtime.dart';
import 'session/session_tree.dart';
import 'session/terminal_transfer_flow.dart';
import 'terminal_screen_access.dart' show TerminalScreenAccess;
import 'terminal_screen_ports.dart'
    show TerminalPortSource, TerminalScreenPorts;

// 互換のための再 export（参照元が terminal_root_bindings.dart 経由でも解決できる）。
export 'terminal_screen_access.dart' show TerminalScreenAccess;

/// root が保持する唯一の合成アダプタ。
///
/// 協調オブジェクトを生成し（initialize）、P0-P9 の破棄を統括する。すべての
/// port 実装は [TerminalScreenPorts] に委譲し、本クラスはポートが読む根
/// （[TerminalPortSource]）とライフサイクルのみを持つ。
class TerminalScreenAdapter implements TerminalPortSource {
  TerminalScreenAdapter(this.access);

  @override
  final TerminalScreenAccess access;

  // ---- 協調オブジェクト（initialize() で生成・ports から参照）----
  late final TerminalScreenPorts ports;
  @override
  late final SessionEnv env;
  @override
  late final SessionRuntimeController runtime;
  @override
  late final HerdrController herdr;
  @override
  late final TerminalInputCoordinator input;
  @override
  late final TerminalViewportPort viewport;
  late final SessionConnectionFlow connection;
  late final SessionLifecycle lifecycle;
  late final TerminalTransferFlow transfer;
  late final SessionResizeFlow resize;
  @override
  late final TmuxSessionMutations mutations;
  late final TmuxSessionTeardown teardown;

  final TmuxFacade _tmux = TmuxFacade();

  // C9: pending 表示対象（値生成は herdr API・root が保管）。
  Object? _pendingTargetIdentity;
  dynamic _pendingCaret;

  @override
  TmuxFacade get tmux => _tmux;

  // ===================== TerminalPortSource（ポートの読み出し根） =====================

  @override
  Object? get pendingTargetIdentity => _pendingTargetIdentity;
  @override
  set pendingTargetIdentity(Object? value) => _pendingTargetIdentity = value;
  @override
  dynamic get pendingCaret => _pendingCaret;
  @override
  set pendingCaret(dynamic value) => _pendingCaret = value;

  // ===================== 生成 =====================

  /// env / controller を生成し、session の collaboration を注入する。
  /// root State の initState から 1 回だけ呼ぶ。
  void initialize() {
    ports = TerminalScreenPorts(this);

    env = SessionEnv(
      ref: access.ref,
      host: ports,
      pendingStore: ports,
      transferHost: ports,
      herdr: ports,
      input: ports,
      viewport: ports,
      tmux: _tmux,
      // 注意: SessionEnv のフィールド型は非 null の DownloadDisplaySpec を要求
      // するため、純関数が null（発火なし）を返す場合は空の sentinel を返す。
      // 真の「表示なし」は session 側の nil 判定に依存できない（要 session 修正）。
      // NG-1: 純関数が null（表示なし）を返したら null のまま伝搬する。
      downloadSnackBarDisplay: (l10n, next, prevPhase) {
        final spec = downloadSnackBarDisplay(
          l10n as dynamic,
          next as dynamic,
          prevPhase as dynamic,
        );
        if (spec == null) return null;
        return DownloadDisplaySpec(
          message: spec.message,
          backgroundColor: spec.backgroundColor,
        );
      },
    );

    runtime = SessionRuntimeController(env);
    connection = SessionConnectionFlow(env, runtime);
    lifecycle = SessionLifecycle(env, runtime);
    transfer = TerminalTransferFlow(env, runtime);
    resize = SessionResizeFlow(env, runtime);
    mutations = TmuxSessionMutations(env, runtime);
    final dialogs = SessionConfirmDialogs(env, runtime);
    teardown = TmuxSessionTeardown(
      env,
      runtime,
      connection: connection,
      dialogs: dialogs,
      mutations: mutations,
    );
    final poll = SessionPollEngine(env, runtime, connection: connection);
    final readers = SessionReaderComposer(env, runtime);
    final tree = SessionTreeRefresher(env, runtime);

    // session collaboration の注入（root 合成の本体）。
    runtime.pollTick = poll.pollPaneContent;
    runtime.recreatePaneReader = readers.recreatePaneReader;
    runtime.refreshSessionTree = tree.refreshSessionTree;
    runtime.startTreeRefresh = tree.startTreeRefresh;
    runtime.scheduleInitialAutoResize = resize.scheduleInitialAutoResize;
    runtime.restoreResizedWindows = resize.restoreResizedWindows;
    runtime.executeAutoResize = resize.executeAutoResize;

    herdr = HerdrController(
      HerdrEnv(
        ref: access.ref,
        contextProvider: () => access.context,
        isMounted: () => access.isMounted,
        isDisposed: () => access.isDisposed,
        backendKind: () => runtime.backendKind,
        can: (required) => runtime.can(required),
        paneWriter: () => runtime.paneWriter,
        sessionId: () => access.sessionId,
        workspaceLabel: () => access.sessionName,
        initialPaneId: () => access.initialPaneId,
        lastPaneId: () => access.lastPaneId,
        clock: access.herdrCacheClock,
        injectedCaretReader: () => access.herdrCaretReader,
        hasInjectedPaneContentReader: () =>
            access.injectedPaneContentReader != null,
        clearTmuxProvider: () => access.ref.read(tmuxProvider.notifier).clear(),
        suspendPolling: () => runtime.suspendPolling(),
        recreateReaders: () => runtime.recreatePaneReader?.call(),
        resetTerminalMode: () => input.resetTerminalMode(),
        resetView: _resetView,
        boostPolling: () => runtime.boostPolling(),
        startPolling: () => runtime.startPolling(),
        resumePolling: () => runtime.resumePolling(),
        attemptReconnect: () => connection.attemptReconnect(),
        cancelPollTimer: () => runtime.cancelPollTimers(),
        setFrameReader: (r) => runtime.frameReader = r,
        clearViewCaret: _clearViewCaret,
        onSplitPaneRequested: (paneId, direction) =>
            mutations.splitPane(paneId, direction),
        sheetHost: ports,
        showLabelInputDialog: _showLabelInputDialog,
        isResizing: () => runtime.isResizing,
        setResizing: (v) => runtime.isResizing = v,
        setTargetSource: (s) => runtime.targetSource = s,
      ),
    );

    viewport = TerminalViewportPort(access.ansiTextViewKey);
    input = TerminalInputCoordinator(
      ref: access.ref,
      send: ports,
      caps: ports,
      scrollback: ports,
      nav: ports,
      validator: ports,
      host: ports,
      viewport: viewport,
      onApplyBuffered: () => runtime.applyBufferedUpdate(),
      getCanCopyMode: () => runtime.canCopyMode,
      dialogBuilder:
          ({
            required String initialValue,
            required void Function(String value) onValueChanged,
            required Future<void> Function(String value) onSend,
          }) => InputDialogContent(
            initialValue: initialValue,
            onValueChanged: onValueChanged,
            onSend: onSend,
          ),
    );

    // root が結線するライフサイクルフック。
    env.onInitialConnect = connection.connectAndSetup;
    env.afterListenersSetup = transfer.ensureListeners;
    env.onReconnectSuccess = connection.onReconnectSuccess;
    env.onResumePolling = resize.onResumed;
  }

  void _clearViewCaret() {
    final view = runtime.viewNotifier.value;
    if (view.caret != null) {
      runtime.viewNotifier.value = view.copyWith(caret: null);
    }
  }

  /// herdr の切替・セッション確立時の view クリア（HEAD `_switchHerdrTarget` /
  /// `_setupHerdrSession` の ①② 相当・NG-1）。
  void _resetView() {
    runtime.viewNotifier.value = runtime.viewNotifier.value.copyWith(
      content: '',
      caret: null,
    );
    runtime.hasInitialScrolled = false;
  }

  Future<String?> _showLabelInputDialog(HerdrLabelDialogArgs args) async {
    return showDialog<String>(
      context: access.context,
      builder: (_) => HerdrLabelInputDialog(
        title: args.title,
        labelText: args.labelText,
        hintText: args.hintText,
        initialValue: args.initialValue ?? '',
        confirmLabel: args.confirmLabel,
        allowEmpty: args.allowEmpty,
      ),
    );
  }

  // ===================== dispose フェーズ統括（仲裁 §4・root が呼ぶ） =====================

  /// P1: herdr bridge reset（先頭・単独フェーズ）。
  void disposeP1Bridge() => herdr.disposeBridge();

  /// P3: 転送系の ProviderSubscription 2 本。
  void disposeP3Subscriptions() => transfer.disposeSubscriptions();

  /// P4: poll / tree タイマー。
  void disposeP4Pollers() => runtime.cancelPollTimers();

  /// P5: scrollSend / keyOverlay タイマー（view-input）。
  void disposeP5InputTimers() => input.disposeTimers();

  /// P6: autoResize / background タイマー。
  void disposeP6ResizeTimers() => resize.cancelResizeTimers();

  /// P7: herdr cache / identity / resolved target の null 化。
  void disposeP7Caches() {
    herdr.disposeCaches();
    _pendingTargetIdentity = null;
    _pendingCaret = null;
  }

  /// P8: notifier 群（view → herdrDisplay → herdrPaneIndicator → latency）。
  void disposeP8Notifiers() {
    runtime.disposeViewNotifier();
    herdr.disposeNotifiers();
    runtime.disposeLatencyNotifier();
  }

  /// P9: ScrollController の listener 解除。
  void disposeP9Detach() => input.detachScroll();
}
