// session-runtime の分割スロット（arbitration §5・450 行超過時の必須分割先）。
//
// フレームスロットル（16ms）と表示適用（`_scheduleUpdate` / `_applyUpdate` /
// `_applyBufferedUpdate`）を担う。viewNotifier の書込はここが唯一の経路
// （C1/C9: 初回 scrollToCaret と追従は view-input port 経由）。
//
// P8 で破棄される notifier への参照は、`SessionRuntimeController` が持つ
// viewNotifier をこの controller から直接触らず、`SessionViewPipeline` が
// 書込 API を提供する（二重所有を避ける）。
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'session_env.dart';
import 'session_models.dart';

/// フレームスキップを考慮した更新スケジューラ（移設元 L2954-3105）。
/// 描画適用の単一所有画面状態（pipeline が runtime を参照せず利用できる最小面）。
class MutableViewState {
  MutableViewState(this.viewNotifier);

  final ValueNotifier<TerminalViewData> viewNotifier;
}

class SessionViewPipeline {
  SessionViewPipeline(
    this.env,
    this.view, {
    required this.input,
    required bool Function() hasInitialScrolled,
    required void Function(bool) setHasInitialScrolled,
  }) : _hasInitialScrolled = hasInitialScrolled,
       _setHasInitialScrolled = setHasInitialScrolled;

  final SessionEnv env;
  final MutableViewState view;

  /// NG-3: 初回キャレットスクロールの所有フィールドは runtime 側の 1 つ
  /// （切替箇所が false 化する）に統一する。
  final bool Function() _hasInitialScrolled;
  final void Function(bool) _setHasInitialScrolled;

  /// view-input port（C1 scrollToCaret / followToBottom / shouldFollowBottom）。
  final SessionInputPort input;

  // ---- フレームスロットル（移設元 L515-528）----
  static const Duration _minFrameInterval = Duration(milliseconds: 16);
  DateTime _lastFrameTime = DateTime.now();
  bool _pendingUpdate = false;
  String _pendingContent = '';

  /// スロットリング付きで更新をスケジュール（`_scheduleUpdate`）。
  void scheduleUpdate(String content, {Object? targetIdentity, dynamic caret}) {
    _pendingContent = content;

    // C9: pending は root State（PendingViewStore）へ書込（二重所有回避）。
    env.pendingStore.pendingTargetIdentity = targetIdentity;
    env.pendingStore.pendingCaret = caret;

    // すでに更新がスケジュール済みなら何もしない
    if (_pendingUpdate) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastFrameTime);

    if (elapsed >= _minFrameInterval) {
      // 十分な時間が経過しているので即時更新
      _applyUpdate();
    } else {
      // フレームスキップ: 次のフレームで更新
      _pendingUpdate = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!env.host.isMounted || env.host.isDisposed) return;
        _pendingUpdate = false;
        _applyUpdate();
      });
    }
  }

  /// 保留中の更新を適用（`_applyUpdate`・C1/C9 経由）。
  void _applyUpdate() {
    if (!env.host.isMounted || env.host.isDisposed) return;
    // A3改: スロットリング待ちの間に表示対象が変わっていないか照合。
    if (!env.herdr.isCurrentTargetIdentity(
      env.pendingStore.pendingTargetIdentity,
    )) {
      return;
    }
    _lastFrameTime = DateTime.now();
    view.viewNotifier.value = view.viewNotifier.value.copyWith(
      content: _pendingContent,
      caret: env.pendingStore.pendingCaret as dynamic,
    );

    // 初回コンテンツ受信時に一番下へスクロール（TERM-SCROLL-004）
    if (!_hasInitialScrolled() && _pendingContent.isNotEmpty) {
      _setHasInitialScrolled(true);
      input.scrollToCaret();
    } else if (_hasInitialScrolled() &&
        input.isNormalMode &&
        !input.isUserScrollDragging &&
        input.shouldFollowBottom) {
      // Issue #87: 最下部ピン留め（またはロック）中のコンテンツ更新に追従する。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (env.host.isMounted && !env.host.isDisposed) {
          input.followToBottom();
        }
      });
    }
  }

  /// 選択モードのバッファを適用（`_applyBufferedUpdate`・C7 3 段契約）。
  ///
  /// バッファの保管（takeBufferedUpdate）と破棄判定（herdr API）は view-input
  /// 側との 3 段契約。ここではヘルパとして、view-input から引き取った値を
  /// scheduleUpdate へ渡す。
  void applyBufferedUpdate() {
    final buffered = env.input.takeBufferedUpdate();
    if (buffered == null) return;
    scheduleUpdate(
      buffered.content,
      targetIdentity: buffered.targetIdentity,
      caret: buffered.caret,
    );
  }
}
