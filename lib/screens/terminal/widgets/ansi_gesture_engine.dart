import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../../../services/tmux/pane_navigator.dart';
import 'ansi_terminal_model.dart';
import 'terminal_zoom.dart';

/// タッチ操作状態機械（ピンチズーム・2 本指パン/スワイプ・ホールド+スワイプ・
/// scrollSend ドラッグティック変換）の唯一の状態所有者（P3-2）。
///
/// Widget プロパティ（モード・各種コールバック・ナビゲーション可否）は
/// キャッシュせず、すべて [AnsiGestureHost] の getter でライブ参照する
/// （P2 critique §1.1 の実行時 prop 固定化を再発させない）。
class AnsiGestureEngine {
  /// State の操作面・通知 API。
  final AnsiGestureHost host;

  /// ホールド+スワイプ用の状態
  bool _isLongPressing = false;
  Offset? _longPressStartPosition;
  String? _lastSwipeDirection;
  static const double _swipeThreshold = 30.0;

  /// 2本指ジェスチャーのモード（指の移動方向で判定し、終了までロック）
  TwoFingerGesture _twoFingerMode = TwoFingerGesture.undetermined;
  Offset _twoFingerPanStart = Offset.zero;
  Offset _twoFingerPanDelta = Offset.zero;
  bool _isTwoFingerPanning = false;
  SwipeDirection? _twoFingerSwipeResult;
  static const double _twoFingerSwipeThreshold = 50.0;
  static const Duration _edgeFlashDuration = Duration(milliseconds: 400);

  /// 現在のズームスケール
  double _currentScale = 1.0;

  /// ピンチズーム開始時のスケール
  double _baseScale = 1.0;

  /// scrollSend ドラッグの端数ティック累積（M2・±25% ヒステリシス用）。
  double _scrollTickFraction = 0;

  /// scrollSend 中のターミナル領域のアクティブポインタ数（M5・2 本指パン抑止用）。
  int _activePointers = 0;

  AnsiGestureEngine({required this.host});

  /// 現在のズームスケール
  double get currentScale => _currentScale;

  /// ズームをリセット
  void resetZoom() {
    _currentScale = 1.0;
    _baseScale = 1.0;
    host.notifyChanged();
    host.onZoomChanged?.call(1.0);
  }

  // === ピンチズーム + 2本指スワイプ処理 ===

  void onScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
    _twoFingerPanStart = details.focalPoint;
    _twoFingerPanDelta = Offset.zero;
    _isTwoFingerPanning = false;
    _twoFingerMode = TwoFingerGesture.undetermined;
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    // 1本指ドラッグはスクロールに任せる
    if (details.pointerCount <= 1) return;

    // モード確定済み → そのまま処理
    if (_twoFingerMode == TwoFingerGesture.zoom) {
      _applyZoom(details);
      return;
    }
    if (_twoFingerMode == TwoFingerGesture.pan) {
      _twoFingerPanDelta = details.focalPoint - _twoFingerPanStart;
      host.notifyChanged();
      return;
    }

    // モード未確定 → details.scale と焦点移動量で判定
    _twoFingerPanDelta = details.focalPoint - _twoFingerPanStart;
    _twoFingerMode = classifyTwoFingerGesture(
      scale: details.scale,
      focalTravel: _twoFingerPanDelta.distance,
    );
    switch (_twoFingerMode) {
      case TwoFingerGesture.zoom:
        _isTwoFingerPanning = false;
        _applyZoom(details);
      case TwoFingerGesture.pan:
        _isTwoFingerPanning = true;
        host.notifyChanged();
      case TwoFingerGesture.undetermined:
        break;
    }
  }

  void _applyZoom(ScaleUpdateDetails details) {
    final newScale = (_baseScale * details.scale).clamp(0.5, 5.0);
    if (newScale != _currentScale) {
      _currentScale = newScale;
      host.notifyChanged();
      host.onZoomChanged?.call(newScale);
    }
  }

  void onScaleEnd(ScaleEndDetails details) {
    final wasPanning = _isTwoFingerPanning;
    final wasZooming = _twoFingerMode == TwoFingerGesture.zoom;
    _isTwoFingerPanning = false;
    _twoFingerMode = TwoFingerGesture.undetermined;

    // ズーム確定: プレビュー倍率を永続 zoomFactor に焼き込み、変形をリセット
    if (wasZooming) {
      _commitZoom();
      return;
    }
    if (!wasPanning) return;

    // M5: scrollSend 中は 2 本指スワイプ（ペイン切替）を無効化する。
    // 送信ドラッグ（1 本指）とのジェスチャー競合を回避するため。ピンチズーム
    // （上記 wasZooming 分岐）は全モードで維持（L0-a #5）。
    final direction = host.mode == TerminalMode.scrollSend
        ? null
        : PaneNavigator.detectSwipeDirection(
            _twoFingerPanDelta,
            threshold: _twoFingerSwipeThreshold,
          );

    if (direction != null) {
      final canNavigate = host.navigableDirections?[direction] ?? true;
      if (canNavigate) {
        host.onTwoFingerSwipe?.call(direction);
        HapticFeedback.mediumImpact();
      } else {
        _showEdgeFlash(direction);
      }
    }
    _twoFingerPanDelta = Offset.zero;
    host.notifyChanged();
  }

  /// ピンチ確定。永続ズーム倍率 zoomFactor に焼き込む（全モード共通）。
  /// AutoResize時は terminal_screen が zoomFactor 変更を監視し、実効フォントサイズで
  /// tmux ペインを再フィット（リフロー）させる。それ以外は描画倍率のみ変更。
  void _commitZoom() {
    final scale = _currentScale;
    _currentScale = 1.0;
    _baseScale = 1.0;
    host.commitZoom(scale);
  }

  void _showEdgeFlash(SwipeDirection direction) {
    HapticFeedback.heavyImpact();
    _twoFingerSwipeResult = direction;
    host.notifyChanged();
    Future.delayed(_edgeFlashDuration, () {
      if (host.isMounted) {
        _twoFingerSwipeResult = null;
        host.notifyChanged();
      }
    });
  }

  // === ホールド+スワイプ処理 ===

  void onLongPressStart(LongPressStartDetails details) {
    _isLongPressing = true;
    _longPressStartPosition = details.localPosition;
    _lastSwipeDirection = null;
    host.notifyChanged();
    HapticFeedback.lightImpact();
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isLongPressing || _longPressStartPosition == null) return;

    final delta = details.localPosition - _longPressStartPosition!;
    String? direction;

    // 閾値を超えた方向を検出
    if (delta.dx.abs() > delta.dy.abs()) {
      // 水平方向
      if (delta.dx > _swipeThreshold) {
        direction = 'Right';
      } else if (delta.dx < -_swipeThreshold) {
        direction = 'Left';
      }
    } else {
      // 垂直方向
      if (delta.dy > _swipeThreshold) {
        direction = 'Down';
      } else if (delta.dy < -_swipeThreshold) {
        direction = 'Up';
      }
    }

    if (direction != null) {
      _lastSwipeDirection = direction;
      host.notifyChanged();
      host.onArrowSwipe?.call(direction);
      HapticFeedback.selectionClick();
      // 起点をリセットして連続スワイプ対応
      _longPressStartPosition = details.localPosition;
      // ハイライトを短時間後にリセット
      Future.delayed(const Duration(milliseconds: 150), () {
        if (host.isMounted && _isLongPressing) {
          _lastSwipeDirection = null;
          host.notifyChanged();
        }
      });
    }
  }

  void onLongPressEnd(LongPressEndDetails details) {
    _isLongPressing = false;
    _longPressStartPosition = null;
    _lastSwipeDirection = null;
    host.notifyChanged();
  }

  // === オーバーレイ表示用の状態 getter ===

  bool get isLongPressing => _isLongPressing;
  String? get lastSwipeDirection => _lastSwipeDirection;
  bool get isTwoFingerPanning => _isTwoFingerPanning;
  SwipeDirection? get twoFingerSwipeResult => _twoFingerSwipeResult;
  Offset get twoFingerPanDelta => _twoFingerPanDelta;

  // === scrollSend ポインタ監視（M5） ===

  void pointerDown() {
    _activePointers++;
  }

  void pointerUp() {
    _activePointers--;
  }

  void pointerCancel() {
    _activePointers--;
  }

  // === scrollSend ドラッグ処理（D5・M2） ===

  void onScrollSendDragStart(DragStartDetails details) {
    _scrollTickFraction = 0;
  }

  void onScrollSendDragUpdate(DragUpdateDetails details) {
    if (host.lineHeight <= 0) return;
    // M5: 2 本指以上の操作は送信ドラッグとして扱わない（2 本指パンによる
    // 誤送信を防止。ペイン切替は scrollSend 中は無効）。
    if (_activePointers > 1) return;
    // 1 ティック = 行高 × 1.5（M2）。上ドラッグ（delta.dy < 0）= 上スクロール
    // 送信（ticks > 0）。累積ティックは TerminalScreen 側（合流送信）へ通知。
    final tickHeight = host.lineHeight * 1.5;
    final deltaTicks = -details.delta.dy / tickHeight;
    final ticks = _emitScrollTicks(deltaTicks);
    if (ticks != 0) {
      host.onScrollSendTicks?.call(ticks);
    }
  }

  void onScrollSendDragEnd(DragEndDetails details) {
    _scrollTickFraction = 0;
  }

  /// ティック累積 + ±25% ヒステリシス（ジッタ誤送信防止・M2）。
  ///
  /// 方向反転時のみ、新方向の移動が 0.25 ティック未満なら無視し（デッドゾーン）、
  /// 0.25 ティック以上で反転確定として端数をリセットする。整数部のみ返し、
  /// 端数は [_scrollTickFraction] に保持する。
  int _emitScrollTicks(double deltaTicks) {
    if (deltaTicks == 0) return 0;
    final sameDirection =
        _scrollTickFraction == 0 || _scrollTickFraction.sign == deltaTicks.sign;
    if (!sameDirection) {
      if (deltaTicks.abs() < 0.25) return 0;
      _scrollTickFraction = 0;
    }
    _scrollTickFraction += deltaTicks;
    final whole = _scrollTickFraction.truncate();
    _scrollTickFraction -= whole.toDouble();
    return whole;
  }
}

/// [AnsiGestureEngine] が State から読み取るホストインターフェース。
abstract class AnsiGestureHost {
  /// 現在の操作モード（ライブ参照）。
  TerminalMode get mode;

  /// ピンチズームが有効か（ライブ参照）。
  bool get zoomEnabled;

  /// 各方向にペインが存在するかのマップ（ライブ参照）。
  Map<SwipeDirection, bool>? get navigableDirections;

  /// 2 本指スワイプでペイン切り替え時のコールバック（ライブ参照）。
  void Function(SwipeDirection direction)? get onTwoFingerSwipe;

  /// ホールド+スワイプで矢印キー入力時のコールバック（ライブ参照）。
  void Function(String direction)? get onArrowSwipe;

  /// scrollSend のドラッグ累積ティック通知コールバック（ライブ参照）。
  void Function(int ticks)? get onScrollSendTicks;

  /// ズームスケール変更時のコールバック（ライブ参照）。
  void Function(double scale)? get onZoomChanged;

  /// 行の高さ（ティック換算用・ライブ参照）。
  double get lineHeight;

  /// State が生きているか（= mounted）。
  bool get isMounted;

  /// 状態変化を通知（= State の setState）。
  void notifyChanged();

  /// ピンチ確定: 永続 zoomFactor への焼き込み（settingsProvider 更新）と
  /// onZoomChanged(1.0) 呼び出し、再構築を行うのは State 側。
  void commitZoom(double scale);
}
