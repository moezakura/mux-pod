import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../services/tmux/pane_navigator.dart';
import 'ansi_terminal_model.dart';
import 'ansi_terminal_overlays.dart';

/// ターミナルのビューツリー合成（P3-2・状態なし）。
///
/// ListView の構築・水平スクロール・モード別ラッパー（scrollSend / zoom /
/// select / normal）をすべて現行の build と同一のツリー形状・Key で再現する。
/// [AnsiLineRow] の生成は [rowBuilder] で受け取る。
class AnsiTerminalView extends StatelessWidget {
  const AnsiTerminalView({
    super.key,
    required this.verticalController,
    required this.padding,
    required this.physics,
    required this.itemCount,
    required this.itemExtent,
    required this.rowBuilder,
    required this.needsHorizontalScroll,
    required this.terminalWidth,
    required this.viewportHeight,
    required this.horizontalController,
    required this.mode,
    required this.isSelectMode,
    required this.zoomEnabled,
    required this.backgroundColor,
    required this.currentScale,
    required this.focusNode,
    required this.onKeyEvent,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
    required this.onScrollSendDragStart,
    required this.onScrollSendDragUpdate,
    required this.onScrollSendDragEnd,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.isLongPressing,
    required this.lastSwipeDirection,
    required this.isTwoFingerPanning,
    required this.twoFingerSwipeResult,
    required this.twoFingerPanDelta,
    required this.navigableDirections,
  });

  final ScrollController verticalController;
  final EdgeInsets padding;
  final ScrollPhysics physics;
  final int itemCount;
  final double itemExtent;
  final Widget Function(BuildContext, int) rowBuilder;
  final bool needsHorizontalScroll;
  final double terminalWidth;
  final double viewportHeight;
  final ScrollController horizontalController;

  final TerminalMode mode;
  final bool isSelectMode;
  final bool zoomEnabled;
  final Color backgroundColor;
  final double currentScale;

  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressMoveUpdateCallback onLongPressMoveUpdate;
  final GestureLongPressEndCallback onLongPressEnd;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final GestureScaleEndCallback onScaleEnd;
  final GestureDragStartCallback onScrollSendDragStart;
  final GestureDragUpdateCallback onScrollSendDragUpdate;
  final GestureDragEndCallback onScrollSendDragEnd;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;
  final VoidCallback onPointerCancel;

  final bool isLongPressing;
  final String? lastSwipeDirection;
  final bool isTwoFingerPanning;
  final SwipeDirection? twoFingerSwipeResult;
  final Offset twoFingerPanDelta;
  final Map<SwipeDirection, bool>? navigableDirections;

  @override
  Widget build(BuildContext context) {
    // 仮想スクロール対応のListView.builder
    Widget listWidget = ListView.builder(
      controller: verticalController,
      // コンテンツ不足時のみ下端アライン用の先頭パディングを付与。
      // scrollSend はローカルスクロールを完全無効化（D5: アプリ送信専用モード）。
      padding: padding,
      physics: physics,
      itemCount: itemCount,
      // 固定の行高さを使用してスクロール計算を高速化
      itemExtent: itemExtent,
      // RepaintBoundaryを自動追加
      addRepaintBoundaries: true,
      itemBuilder: rowBuilder,
    );

    // 水平スクロールが必要な場合
    if (needsHorizontalScroll) {
      listWidget = SingleChildScrollView(
        controller: horizontalController,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: SizedBox(
          width: terminalWidth,
          height: viewportHeight,
          child: listWidget,
        ),
      );
    }

    // scrollSend: 1 本指ドラッグ認識子を zoom 認識子より「内側（深い hit-test）」
    // に置く（B5 実測: 外側に置くと gesture arena の競合で連続 Update が欠落
    // するため。内側なら ListView 同様に 1 本指ドラッグが先に勝利する）。
    // onTap は配置しない（タップ認識子がドラッグの連続 Update を欠落させる
    // ため・B5 実測）。2 本指操作は Listener でポインタ数監視して抑止（M5）。
    if (mode == TerminalMode.scrollSend) {
      listWidget = Listener(
        onPointerDown: (_) => onPointerDown(),
        onPointerUp: (_) => onPointerUp(),
        onPointerCancel: (_) => onPointerCancel(),
        child: GestureDetector(
          key: const ValueKey('terminal-scroll-send-gesture'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: onScrollSendDragStart,
          onVerticalDragUpdate: onScrollSendDragUpdate,
          onVerticalDragEnd: onScrollSendDragEnd,
          child: listWidget,
        ),
      );
    }

    // ピンチズーム + 2本指スワイプ（全モード維持・L0-a #5）
    // ※ scrollSend 中は zoom 認識子を無効化する（Phase 3 #6 分岐・B5 実測）:
    //   `_EagerScaleGestureRecognizer` が gesture arena に参加すると 1 本指
    //   ドラッグの連続 Update が欠落し、送信ティックが不足することを widget
    //   テストで確認した（競合実測 = 無効化分岐の適用条件・L0-a #5）。
    //   scrollSend 中のズームはモードを抜けてから行う。
    if (zoomEnabled && mode != TerminalMode.scrollSend) {
      // RawGestureDetectorで2本指検出時にgesture arenaを強制勝利
      listWidget = RawGestureDetector(
        key: const ValueKey('terminal-two-finger-gesture'),
        gestures: <Type, GestureRecognizerFactory>{
          _EagerScaleGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _EagerScaleGestureRecognizer
              >(() => _EagerScaleGestureRecognizer(), (
                _EagerScaleGestureRecognizer instance,
              ) {
                instance
                  ..onStart = onScaleStart
                  ..onUpdate = onScaleUpdate
                  ..onEnd = onScaleEnd;
              }),
        },
        child: Transform.scale(
          scale: currentScale,
          alignment: Alignment.topLeft,
          child: listWidget,
        ),
      );
    }

    // select モードの場合はテキスト選択を有効化（select 専用・D12）
    if (isSelectMode) {
      return Container(
        color: backgroundColor,
        child: SelectionArea(child: listWidget),
      );
    }

    // scrollSend モード: アプリへスクロール送信専用（D5）。
    // - ローカルスクロール無効（NeverScrollableScrollPhysics・上で適用）
    // - テキスト選択なし（SelectionArea 非配置）
    // - ホールド+スワイプ無効（longPress ハンドラを配置しない）
    // - 2 本指スワイプ無効（_onScaleEnd ガード + ポインタ数監視・M5。ピンチは維持）
    // - Focus 追加（物理キーボード PgUp/PgDn 送信用・現状 normal 分岐のみのため）
    // - 1 本指ドラッグ → ティック換算 → onScrollSendTicks で TerminalScreen へ
    if (mode == TerminalMode.scrollSend) {
      return Container(
        color: backgroundColor,
        child: Focus(
          focusNode: focusNode,
          autofocus: true,
          onKeyEvent: onKeyEvent,
          child: listWidget,
        ),
      );
    }

    // 通常モード：キーボード入力をハンドリング
    // ホールド+スワイプで矢印キー入力対応
    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: onKeyEvent,
      child: GestureDetector(
        key: const ValueKey('terminal-input-gesture'),
        onTap: () {
          focusNode.requestFocus();
          onTap?.call();
        },
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        child: Stack(
          children: [
            Container(color: backgroundColor, child: listWidget),
            // ホールド+スワイプオーバーレイ
            if (isLongPressing)
              AnsiSwipeOverlay(
                isLongPressing: isLongPressing,
                lastSwipeDirection: lastSwipeDirection,
              ),
            // 2本指スワイプオーバーレイ
            if (isTwoFingerPanning || twoFingerSwipeResult != null)
              AnsiTwoFingerOverlay(
                twoFingerSwipeResult: twoFingerSwipeResult,
                isTwoFingerPanning: isTwoFingerPanning,
                panDelta: twoFingerPanDelta,
                navigableDirections: navigableDirections,
              ),
          ],
        ),
      ),
    );
  }
}

/// 2本指以上を検出した場合、gesture arenaを強制的に勝ち取るScaleGestureRecognizer。
///
/// 通常のScaleGestureRecognizerは内部のSingleChildScrollViewの
/// HorizontalDragGestureRecognizerにarenaで負けてしまう。
/// このクラスは2本指検出時にrejectGesture()をacceptGesture()にオーバーライドし、
/// arenaを強制勝利する。1本指の場合はsuper.rejectGesture()で通常通り
/// ScrollViewに譲るため、1本指スクロールは影響を受けない。
class _EagerScaleGestureRecognizer extends ScaleGestureRecognizer {
  int _pointerCount = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointerCount++;
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointerCount = (_pointerCount - 1).clamp(0, 99);
    }
  }

  @override
  void rejectGesture(int pointer) {
    if (_pointerCount >= 2) {
      acceptGesture(pointer);
    } else {
      super.rejectGesture(pointer);
    }
  }

  @override
  void dispose() {
    _pointerCount = 0;
    super.dispose();
  }
}
