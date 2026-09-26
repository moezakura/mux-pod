// session-runtime 領域の合成ルート（root State が has-a する単一状態所有者）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../services/backend/domain/pane_content_reader.dart';
import '../../../../services/backend/domain/pane_frame_reader.dart';
import '../../../../services/backend/domain/pane_writer.dart';
import '../../../../services/backend/domain/multiplexer_backend.dart'
    show MultiplexerBackendKind;
import '../../../../services/terminal/adaptive_polling.dart';
import '../target_source.dart';
import 'session_env.dart';
import 'session_models.dart';
import 'session_view_pipeline.dart';

/// session-runtime の単一状態所有者・合成ルート。
///
/// - 表示データ [`viewNotifier`] と [`latencyNotifier`] を所有（P8 で破棄）
/// - poll 用タイマー・適応型間隔を所有（P4 で破棄）
/// - reader/writer/targetSource ポインタと能力 getter を所有
/// - フレームスロットルと表示適用は [`SessionViewPipeline`]（分割スロット）へ委譲
class SessionRuntimeController {
  SessionRuntimeController(this.env) {
    _pipeline = SessionViewPipeline(
      env,
      MutableViewState(viewNotifier),
      input: env.input,
      // NG-3: 切替箇所（session_mutations）が false 化する単一の所有フィールド。
      hasInitialScrolled: () => hasInitialScrolled,
      setHasInitialScrolled: (v) => hasInitialScrolled = v,
    );
  }

  final SessionEnv env;

  // ---- 表示データ（P8: viewNotifier → latencyNotifier の順で破棄・仲裁 §4.5）----
  final ValueNotifier<TerminalViewData> viewNotifier =
      ValueNotifier<TerminalViewData>(const TerminalViewData());
  final ValueNotifier<int> latencyNotifier = ValueNotifier<int>(0);

  // ---- poll 制御（P4 で破棄）----
  Timer? pollTimer;
  Timer? treeRefreshTimer;
  int _pollGeneration = 0;
  bool get canPoll => !isDisposed && !pollingSuspended && !isInBackground;
  bool isPolling = false;
  bool isDisposed = false;

  // ---- 適応型ポーリング（実測・TERM-LIFE-015/017）----
  int currentPollingInterval = 100;
  static const int minPollingInterval = 50;
  static const int maxPollingInterval = 2000;
  int unchangedPolls = 0;
  String? lastPolledContent;

  // ---- 接続状態（ui に read-only）----
  dynamic sshState;
  String? connectionError;
  bool isConnecting = false;

  // ---- 能力・backend----
  PaneWriter? paneWriter;
  PaneContentReader? paneReader;
  PaneFrameReader? frameReader;
  TargetSource? targetSource;
  MultiplexerBackendKind backendKind = MultiplexerBackendKind.unknown;
  Object? tmuxVersion; // TmuxVersionInfo?

  // ---- ガード ----
  bool isCreatingWindow = false;
  bool isResizing = false;
  bool pollingSuspended = false;
  bool isInBackground = false;
  bool directInputEnabled = true;

  // ---- 表示追従 ----
  bool hasInitialScrolled = false;
  bool isBottomLock = false;
  bool isUserScrollDragging = false;
  bool isProgrammaticScroll = false;
  bool isPinnedToBottom = true;

  // ---- フレームスロットル（pipeline が実体を持つ）----
  late final SessionViewPipeline _pipeline;
  SessionViewPipeline get pipeline => _pipeline;

  // ---------------------------------------------------------------------------
  // 能力 getter（設計 §1.1 I・移設元 L698-751）
  // ---------------------------------------------------------------------------

  /// 指定した操作能力が現在のバックエンドで有効か。
  bool can(PaneCapabilities required) {
    final caps = _paneCapabilities;
    return (required.sendText == false || caps.sendText) &&
        (required.sendKeys == false || caps.sendKeys) &&
        (required.focus == false || caps.focus) &&
        (required.split == false || caps.split) &&
        (required.close == false || caps.close) &&
        (required.rename == false || caps.rename) &&
        (required.zoom == false || caps.zoom) &&
        (required.resize == false || caps.resize) &&
        (required.paste == false || caps.paste) &&
        (required.copyMode == false || caps.copyMode) &&
        (required.imageTransfer == false || caps.imageTransfer) &&
        (required.workspaceCrud == false || caps.workspaceCrud) &&
        (required.tabCrud == false || caps.tabCrud) &&
        (required.absoluteResize == false || caps.absoluteResize) &&
        (required.wheelSend == false || caps.wheelSend);
  }

  PaneCapabilities get _paneCapabilities =>
      paneWriter?.capabilities ?? const PaneCapabilities();

  /// 現在のバックエンドの実行能力束（root のテストフック转发用）。
  PaneCapabilities get paneCapabilities => _paneCapabilities;

  bool get canSendText => can(const PaneCapabilities(sendText: true));
  bool get canSendSpecialKey => can(const PaneCapabilities(sendKeys: true));
  bool get canFocusDirection => can(const PaneCapabilities(focus: true));
  bool get canSplitPane => can(const PaneCapabilities(split: true));
  bool get canCopyMode => can(const PaneCapabilities(copyMode: true));
  bool get canPaste => can(const PaneCapabilities(paste: true));
  bool get canWheelSend => can(const PaneCapabilities(wheelSend: true));

  // ---------------------------------------------------------------------------
  // poll 制御（移設元 L1958-2063・P4 dispose 対象）
  // ---------------------------------------------------------------------------

  /// 初回ポーリング開始（`_startPolling`）。
  void startPolling() {
    _pollGeneration++;
    pollTimer?.cancel();
    scheduleNextPoll();
  }

  /// 次のポーリングをスケジュール（`_scheduleNextPoll`）。
  void scheduleNextPoll() {
    if (!canPoll) return;
    pollTimer?.cancel();
    final generation = _pollGeneration;
    pollTimer = Timer(Duration(milliseconds: currentPollingInterval), () async {
      if (!canPoll || generation != _pollGeneration) return;
      await onPollTick();
      if (generation == _pollGeneration) scheduleNextPoll();
    });
  }

  /// 各 poll 周期の 1 回分。SessionPollEngine が実装を注入する。
  Future<void> Function()? pollTick;
  Future<void> onPollTick() async {
    if (!canPoll) return;
    final fn = pollTick;
    if (fn != null) {
      await fn();
    }
  }

  // ---- コラボレータ注入（root State が結線）----

  /// reader/writer 再生成（session_readers が注入）。
  void Function()? recreatePaneReader;

  /// セッションツリー更新（session_tree が注入）。
  Future<void> Function()? refreshSessionTree;
  void Function()? startTreeRefresh;

  /// autoResize（session_resize が注入）。
  void Function()? scheduleInitialAutoResize;
  Future<void> Function()? restoreResizedWindows;

  /// _executeAutoResize（session_resize が注入・pane を引数）。
  Future<void> Function(Object pane, {bool force})? executeAutoResize;

  /// キー入力後の即時ブースト（`_boostPolling`）。
  void boostPolling() {
    if (currentPollingInterval == minPollingInterval) return;
    currentPollingInterval = minPollingInterval;
    pollTimer?.cancel();
    scheduleNextPoll();
  }

  /// 適応型間隔更新（`_updatePollingInterval`）。
  void updatePollingInterval({bool copyModeActive = false}) {
    final recommended = AdaptivePollingInterval.calculateInterval(
      unchangedPolls,
    );
    final maxInterval = copyModeActive
        ? 500
        : SessionRuntimeController.maxPollingInterval;
    currentPollingInterval = recommended.clamp(minPollingInterval, maxInterval);
  }

  /// ポーリング停止（P4）。
  void cancelPollTimers() {
    _pollGeneration++;
    pollTimer?.cancel();
    pollTimer = null;
    treeRefreshTimer?.cancel();
    treeRefreshTimer = null;
  }

  /// suspend / resume（herdr は suspendPolling/resumePolling コールバックで間接操作）。
  void suspendPolling() {
    pollingSuspended = true;
    cancelPollTimers();
  }

  void resumePolling() {
    pollingSuspended = false;
  }

  // ---------------------------------------------------------------------------
  // 表示適用（pipeline に委譲・C1/C9 経由）
  // ---------------------------------------------------------------------------

  void scheduleUpdate(String content, {Object? targetIdentity, dynamic caret}) {
    _pipeline.scheduleUpdate(
      content,
      targetIdentity: targetIdentity,
      caret: caret,
    );
  }

  void applyBufferedUpdate() => _pipeline.applyBufferedUpdate();

  /// P8a: viewNotifier 破棄（root State が dispose で呼ぶ）。
  void disposeViewNotifier() {
    viewNotifier.dispose();
  }

  /// P8c: latencyNotifier 破棄（viewNotifier の後に呼ぶ・仲裁 §4.5）。
  void disposeLatencyNotifier() {
    latencyNotifier.dispose();
  }
}
