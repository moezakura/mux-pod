import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart';
import '../../../providers/terminal_display_provider.dart';
import '../../../services/terminal/ansi_parser.dart';
import '../../../services/terminal/font_calculator.dart';
import '../../../services/terminal/terminal_font_styles.dart';
import '../../../services/tmux/pane_navigator.dart';
import '../../../theme/design_colors.dart';
import 'terminal_zoom.dart';

/// キー入力イベント
class KeyInputEvent {
  /// キーデータ（エスケープシーケンスまたは文字）
  final String data;

  /// 特殊キーかどうか
  final bool isSpecialKey;

  /// tmux形式のキー名（Enterの場合は'Enter'など）
  /// isSpecialKeyがtrueの場合に使用
  final String? tmuxKeyName;

  const KeyInputEvent({
    required this.data,
    this.isSpecialKey = false,
    this.tmuxKeyName,
  });
}

/// ターミナルの操作モード
///
/// 3 モードは排他的（同時に成立しない）: 「Scroll 送信」と「選択」が混在
/// しないことを enum 値の分離で構造的に担保する（D1）。
enum TerminalMode {
  /// 通常モード（キー入力が有効・ライブ表示）
  normal,

  /// 選択モード（履歴閲覧＋テキスト選択・tmux copy-mode / SelectionArea・バッファ保持）
  ///
  /// 旧 `TerminalMode.scroll` のリネーム（D1）。
  select,

  /// スクロール送信モード（アプリへ SGR ホイール / PgUp・PgDn / 文字キーを送信・
  /// ローカルスクロール無効・テキスト選択なし・ライブ表示）
  scrollSend,
}

/// ANSIテキスト表示ウィジェット
///
/// capture-pane -e の出力をANSIカラー付きで表示する。
/// RichText/SelectableTextを使用し、xterm依存を排除。
class AnsiTextView extends ConsumerStatefulWidget {
  /// 表示するANSIテキスト
  final String text;

  /// ペインの文字幅
  final int paneWidth;

  /// ペインの文字高さ
  final int paneHeight;

  /// キー入力コールバック
  final void Function(KeyInputEvent)? onKeyInput;

  /// 背景色
  final Color backgroundColor;

  /// 前景色
  final Color foregroundColor;

  /// 操作モード
  final TerminalMode mode;

  /// ピンチズームが有効かどうか
  final bool zoomEnabled;

  /// ズームスケール変更時のコールバック
  final void Function(double scale)? onZoomChanged;

  /// 外部から渡される垂直スクロールコントローラー（オプション）
  final ScrollController? verticalScrollController;

  /// カーソルX位置（0-based）
  final int cursorX;

  /// カーソルY位置（0-based, ペイン上部基準）
  final int cursorY;

  /// ホールド+スワイプで矢印キー入力時のコールバック
  /// direction: 'Up', 'Down', 'Left', 'Right'
  final void Function(String direction)? onArrowSwipe;

  /// 2本指スワイプでペイン切り替え時のコールバック
  final void Function(SwipeDirection direction)? onTwoFingerSwipe;

  /// scrollSend モード中のドラッグ累積ティック通知コールバック（M2・D5）。
  ///
  /// `ticks > 0` = 上スクロール送信・`ticks < 0` = 下スクロール送信。
  /// 1 ティック = 行高 × 1.5（`_lineHeight` 基準・±25% ヒステリシス）。
  /// null なら通知しない。
  // inventory: TERM-SCROLL-006
  final void Function(int ticks)? onScrollSendTicks;

  /// 各方向にペインが存在するかのマップ（視覚フィードバック用）
  final Map<SwipeDirection, bool>? navigableDirections;

  /// ターミナル領域タップ時のコールバック
  final VoidCallback? onTap;

  const AnsiTextView({
    super.key,
    required this.text,
    required this.paneWidth,
    required this.paneHeight,
    this.onKeyInput,
    this.backgroundColor = const Color(0xFF1E1E1E),
    this.foregroundColor = const Color(0xFFD4D4D4),
    this.mode = TerminalMode.normal,
    this.zoomEnabled = true,
    this.onZoomChanged,
    this.verticalScrollController,
    this.cursorX = 0,
    this.cursorY = 0,
    this.onArrowSwipe,
    this.onTwoFingerSwipe,
    this.navigableDirections,
    this.onTap,
    this.onScrollSendTicks,
  });

  @override
  ConsumerState<AnsiTextView> createState() => AnsiTextViewState();
}

class AnsiTextViewState extends ConsumerState<AnsiTextView> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _horizontalScrollController = ScrollController();
  ScrollController? _internalVerticalScrollController;

  /// キャレット点滅用（離散トグル）。連続アニメだと毎 vsync 再描画され、
  /// 待機中も 60-120fps を消費するため、500ms ごとに ON/OFF を切り替える。
  Timer? _caretBlinkTimer;
  final ValueNotifier<bool> _caretVisible = ValueNotifier<bool>(true);

  /// 使用する垂直スクロールコントローラー
  ScrollController get _verticalScrollController =>
      widget.verticalScrollController ?? _internalVerticalScrollController!;

  late AnsiParser _parser;

  /// 修飾キー状態
  bool _ctrlPressed = false;
  bool _altPressed = false;
  bool _shiftPressed = false;

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
  static const double _panGlowThreshold = 20.0;
  static const Duration _edgeFlashDuration = Duration(milliseconds: 400);

  /// 現在のズームスケール
  double _currentScale = 1.0;

  /// ピンチズーム開始時のスケール
  double _baseScale = 1.0;

  /// パース済み行データキャッシュ（仮想スクロール用）
  List<ParsedLine>? _cachedParsedLines;
  String? _cachedText;
  double? _cachedFontSize;
  String? _cachedFontFamily;

  /// 行の高さ（仮想スクロールで固定高さを使用）
  double _lineHeight = 20.0;

  /// scrollSend ドラッグの端数ティック累積（M2・±25% ヒステリシス用）。
  /// 1 ティック = `_lineHeight × 1.5`。整数部のみコールバックし、端数は保持する。
  double _scrollTickFraction = 0;

  /// scrollSend 中のターミナル領域のアクティブポインタ数（M5・2 本指パン抑止用）。
  int _activePointers = 0;

  @override
  void initState() {
    super.initState();
    // 外部からScrollControllerが渡されていない場合は内部で作成
    if (widget.verticalScrollController == null) {
      _internalVerticalScrollController = ScrollController();
    }
    _parser = AnsiParser(
      defaultForeground: widget.foregroundColor,
      defaultBackground: widget.backgroundColor,
    );

    // 500ms ごとにキャレット表示を反転（離散点滅）。ValueNotifier のみ更新するため、
    // 連続アニメと違い待機中は再描画されない（idle 時 0fps を維持）。
    _caretBlinkTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _caretVisible.value = !_caretVisible.value,
    );
  }

  @override
  void didUpdateWidget(AnsiTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.foregroundColor != widget.foregroundColor ||
        oldWidget.backgroundColor != widget.backgroundColor) {
      _parser = AnsiParser(
        defaultForeground: widget.foregroundColor,
        defaultBackground: widget.backgroundColor,
      );
      // パーサーが変わったのでキャッシュを無効化
      _invalidateCache();
    }
  }

  /// キャッシュを無効化
  void _invalidateCache() {
    _cachedParsedLines = null;
    _cachedText = null;
    _cachedFontSize = null;
    _cachedFontFamily = null;
  }

  /// 行データを取得（キャッシュ使用・仮想スクロール用）
  List<ParsedLine> _getParsedLines({
    required double fontSize,
    required String fontFamily,
  }) {
    final textChanged = _cachedText != widget.text;

    // キャッシュが有効かチェック
    if (_cachedParsedLines != null &&
        !textChanged &&
        _cachedFontSize == fontSize &&
        _cachedFontFamily == fontFamily) {
      return _cachedParsedLines!;
    }

    // 新しくパース（parseLinesは変更行のみ再パースするインクリメンタル方式）
    _cachedParsedLines = _parser.parseLines(widget.text);
    _cachedText = widget.text;
    _cachedFontSize = fontSize;
    _cachedFontFamily = fontFamily;

    // 行の高さを計算（fontSize * lineHeight係数）
    _lineHeight = fontSize * 1.4;

    return _cachedParsedLines!;
  }

  @override
  void dispose() {
    _caretBlinkTimer?.cancel();
    _caretVisible.dispose();
    _focusNode.dispose();
    _horizontalScrollController.dispose();
    // 内部で作成した場合のみ破棄
    _internalVerticalScrollController?.dispose();
    super.dispose();
  }

  /// ズームをリセット
  void resetZoom() {
    setState(() {
      _currentScale = 1.0;
      _baseScale = 1.0;
    });
    widget.onZoomChanged?.call(1.0);
  }


  // === ピンチズーム + 2本指スワイプ処理 ===

  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
    _twoFingerPanStart = details.focalPoint;
    _twoFingerPanDelta = Offset.zero;
    _isTwoFingerPanning = false;
    _twoFingerMode = TwoFingerGesture.undetermined;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // 1本指ドラッグはスクロールに任せる
    if (details.pointerCount <= 1) return;

    // モード確定済み → そのまま処理
    if (_twoFingerMode == TwoFingerGesture.zoom) {
      _applyZoom(details);
      return;
    }
    if (_twoFingerMode == TwoFingerGesture.pan) {
      _twoFingerPanDelta = details.focalPoint - _twoFingerPanStart;
      setState(() {});
      return;
    }

    // モード未確定 → details.scale と焦点移動量で判定
    // （details.scale は片方の指が静止していても信頼できる合図）
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
        setState(() {});
      case TwoFingerGesture.undetermined:
        break;
    }
  }

  void _applyZoom(ScaleUpdateDetails details) {
    final newScale = (_baseScale * details.scale).clamp(0.5, 5.0);
    if (newScale != _currentScale) {
      setState(() {
        _currentScale = newScale;
      });
      widget.onZoomChanged?.call(newScale);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
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
    final direction = widget.mode == TerminalMode.scrollSend
        ? null
        : PaneNavigator.detectSwipeDirection(
            _twoFingerPanDelta,
            threshold: _twoFingerSwipeThreshold,
          );

    if (direction != null) {
      final canNavigate = widget.navigableDirections?[direction] ?? true;
      if (canNavigate) {
        widget.onTwoFingerSwipe?.call(direction);
        HapticFeedback.mediumImpact();
      } else {
        _showEdgeFlash(direction);
      }
    }
    _twoFingerPanDelta = Offset.zero;
    setState(() {});
  }

  /// ピンチ確定。永続ズーム倍率 zoomFactor に焼き込む（全モード共通）。
  /// AutoResize時は terminal_screen が zoomFactor 変更を監視し、実効フォントサイズで
  /// tmux ペインを再フィット（リフロー）させる。それ以外は描画倍率のみ変更。
  void _commitZoom() {
    final settings = ref.read(settingsProvider);
    final scale = _currentScale;
    _currentScale = 1.0;
    _baseScale = 1.0;
    final committed = clampZoomFactor(settings.zoomFactor * scale);
    ref.read(settingsProvider.notifier).setZoomFactor(committed);
    widget.onZoomChanged?.call(1.0);
    if (mounted) setState(() {});
  }

  void _showEdgeFlash(SwipeDirection direction) {
    HapticFeedback.heavyImpact();
    setState(() {
      _twoFingerSwipeResult = direction;
    });
    Future.delayed(_edgeFlashDuration, () {
      if (mounted) {
        setState(() {
          _twoFingerSwipeResult = null;
        });
      }
    });
  }

  // === ホールド+スワイプ処理 ===

  void _onLongPressStart(LongPressStartDetails details) {
    setState(() {
      _isLongPressing = true;
      _longPressStartPosition = details.localPosition;
      _lastSwipeDirection = null;
    });
    HapticFeedback.lightImpact();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
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
      setState(() {
        _lastSwipeDirection = direction;
      });
      widget.onArrowSwipe?.call(direction);
      HapticFeedback.selectionClick();
      // 起点をリセットして連続スワイプ対応
      _longPressStartPosition = details.localPosition;
      // ハイライトを短時間後にリセット
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && _isLongPressing) {
          setState(() {
            _lastSwipeDirection = null;
          });
        }
      });
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    setState(() {
      _isLongPressing = false;
      _longPressStartPosition = null;
      _lastSwipeDirection = null;
    });
  }

  /// スワイプオーバーレイウィジェット
  Widget _buildSwipeOverlay() {
    return Center(
      child: AnimatedOpacity(
        opacity: _isLongPressing ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              // 上矢印
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Icon(
                  Icons.arrow_drop_up,
                  size: 40,
                  color: _lastSwipeDirection == 'Up'
                      ? Colors.amber
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
              // 下矢印
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Icon(
                  Icons.arrow_drop_down,
                  size: 40,
                  color: _lastSwipeDirection == 'Down'
                      ? Colors.amber
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
              // 左矢印
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Icon(
                  Icons.arrow_left,
                  size: 40,
                  color: _lastSwipeDirection == 'Left'
                      ? Colors.amber
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
              // 右矢印
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Icon(
                  Icons.arrow_right,
                  size: 40,
                  color: _lastSwipeDirection == 'Right'
                      ? Colors.amber
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
              // 中央の点
              Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 2本指スワイプ時の視覚フィードバックオーバーレイ
  Widget _buildTwoFingerSwipeOverlay() {
    // 端到達時のフラッシュ表示
    if (_twoFingerSwipeResult != null) {
      return _buildEdgeFlash(_twoFingerSwipeResult!);
    }

    // パン中のエッジグロー表示
    if (_isTwoFingerPanning) {
      return _buildPanGlow();
    }

    return const SizedBox.shrink();
  }

  /// 端到達時の赤系フラッシュ
  Widget _buildEdgeFlash(SwipeDirection direction) {
    final alignment = switch (direction) {
      SwipeDirection.left => Alignment.centerLeft,
      SwipeDirection.right => Alignment.centerRight,
      SwipeDirection.up => Alignment.topCenter,
      SwipeDirection.down => Alignment.bottomCenter,
    };

    final isHorizontal =
        direction == SwipeDirection.left || direction == SwipeDirection.right;

    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: alignment,
          child: Container(
            width: isHorizontal ? 40 : double.infinity,
            height: isHorizontal ? double.infinity : 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: isHorizontal
                    ? (direction == SwipeDirection.left
                        ? Alignment.centerRight
                        : Alignment.centerLeft)
                    : (direction == SwipeDirection.up
                        ? Alignment.bottomCenter
                        : Alignment.topCenter),
                end: isHorizontal
                    ? (direction == SwipeDirection.left
                        ? Alignment.centerLeft
                        : Alignment.centerRight)
                    : (direction == SwipeDirection.up
                        ? Alignment.topCenter
                        : Alignment.bottomCenter),
                colors: [
                  Colors.transparent,
                  Colors.red.withValues(alpha: 0.4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// パン中の方向グロー
  Widget _buildPanGlow() {
    final dx = _twoFingerPanDelta.dx;
    final dy = _twoFingerPanDelta.dy;

    // 移動量が小さすぎる場合は表示しない
    if (dx.abs() < _panGlowThreshold && dy.abs() < _panGlowThreshold) {
      return const SizedBox.shrink();
    }

    SwipeDirection? direction;
    if (dx.abs() > dy.abs()) {
      direction = dx > 0 ? SwipeDirection.right : SwipeDirection.left;
    } else {
      direction = dy > 0 ? SwipeDirection.down : SwipeDirection.up;
    }

    final canNavigate = widget.navigableDirections?[direction] ?? true;
    final color = canNavigate
        ? DesignColors.primary.withValues(alpha: 0.2)
        : Colors.red.withValues(alpha: 0.15);

    final alignment = switch (direction) {
      SwipeDirection.left => Alignment.centerLeft,
      SwipeDirection.right => Alignment.centerRight,
      SwipeDirection.up => Alignment.topCenter,
      SwipeDirection.down => Alignment.bottomCenter,
    };

    final isHorizontal =
        direction == SwipeDirection.left || direction == SwipeDirection.right;

    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: alignment,
          child: Container(
            width: isHorizontal ? 30 : double.infinity,
            height: isHorizontal ? double.infinity : 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: isHorizontal
                    ? (direction == SwipeDirection.left
                        ? Alignment.centerRight
                        : Alignment.centerLeft)
                    : (direction == SwipeDirection.up
                        ? Alignment.bottomCenter
                        : Alignment.topCenter),
                end: isHorizontal
                    ? (direction == SwipeDirection.left
                        ? Alignment.centerLeft
                        : Alignment.centerRight)
                    : (direction == SwipeDirection.up
                        ? Alignment.topCenter
                        : Alignment.bottomCenter),
                colors: [
                  Colors.transparent,
                  color,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 現在のズームスケールを取得
  double get currentScale => _currentScale;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    // select 専用（4 経路分離・D12）: テキスト選択は選択モードのみ。
    // scrollSend はここに含まれない（SelectionArea 非配置）。
    final isSelectMode = widget.mode == TerminalMode.select;

    return LayoutBuilder(
      builder: (context, constraints) {
        // スクリーンサイズをTerminalDisplayProviderに通知（リサイズダイアログ用）
        // build中のprovider変更は禁止のためフレーム後に実行
        // 値が変わった時のみ更新（無限ループ防止）
        final currentDisplay = ref.read(terminalDisplayProvider);
        if (currentDisplay.screenWidth != constraints.maxWidth ||
            currentDisplay.screenHeight != constraints.maxHeight) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(terminalDisplayProvider.notifier).updateScreenSize(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
            }
          });
        }

        // 基本フォントサイズを決定
        late final double baseFontSize;
        if (settings.isAutoFit) {
          // 自動フィット: 画面幅に合わせて計算
          final calcResult = FontCalculator.calculate(
            screenWidth: constraints.maxWidth,
            paneCharWidth: widget.paneWidth,
            fontFamily: settings.fontFamily,
            minFontSize: settings.minFontSize,
          );
          baseFontSize = calcResult.fontSize;
        } else {
          // 手動設定: settings.fontSizeを使用
          baseFontSize = settings.fontSize;
        }

        // ピンチズーム倍率を適用（永続 zoomFactor × 基本サイズ、クランプ）
        final fontSize = zoomedFontSize(
          baseFontSize: baseFontSize,
          zoomFactor: settings.zoomFactor,
          minFontSize: settings.minFontSize,
        );

        // ターミナル幅を計算（ズーム後の実サイズ基準）
        final terminalWidth = FontCalculator.calculateTerminalWidth(
          paneCharWidth: widget.paneWidth,
          fontSize: fontSize,
          fontFamily: settings.fontFamily,
        );

        // 幅が画面を超える場合は水平スクロール（ズーム時のはみ出しをパン可能に）
        final needsHorizontalScroll = terminalWidth > constraints.maxWidth;

        // 行データを取得（キャッシュ使用・仮想スクロール用）
        final parsedLines = _getParsedLines(
          fontSize: fontSize,
          fontFamily: settings.fontFamily,
        );


        // 行に依存しない基本スタイルは1回だけ計算
        // （itemBuilder内での毎フレームGoogleFonts呼び出しを回避）
        final baseTextStyle = TerminalFontStyles.getTextStyle(
          settings.fontFamily,
          fontSize: fontSize,
          height: 1.4,
          color: widget.foregroundColor,
        );

        // 仮想スクロール対応のListView.builder
        Widget listWidget = ListView.builder(
          controller: _verticalScrollController,
          padding: EdgeInsets.zero, // パディングを明示的にゼロにする
          // scrollSend はローカルスクロールを完全無効化（D5: アプリ送信専用モード）
          physics: widget.mode == TerminalMode.scrollSend
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          itemCount: parsedLines.length,
          // 固定の行高さを使用してスクロール計算を高速化
          itemExtent: _lineHeight,
          // RepaintBoundaryを自動追加
          addRepaintBoundaries: true,
          itemBuilder: (context, index) {
            final line = parsedLines[index];
            final textSpan = _parser.lineToTextSpan(
              line,
              fontSize: fontSize,
              fontFamily: settings.fontFamily,
            );

            // 各行のテキストウィジェット
            Widget lineWidget = Text.rich(
              textSpan,
              style: baseTextStyle,
              textScaler: TextScaler.noScaling,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            );

            // カーソルの描画処理
            // カーソル位置の行インデックスを計算
            // parsedLinesには履歴+可視領域が含まれる。
            // 末尾のpaneHeight分が可視領域となる。
            final int cursorLineIndex;
            if (parsedLines.length >= widget.paneHeight) {
              cursorLineIndex = parsedLines.length - widget.paneHeight + widget.cursorY;
            } else {
              // 行数がpaneHeight未満の場合は、単純にcursorYを使用（初期状態など）
              cursorLineIndex = widget.cursorY;
            }

            // 現在の行がカーソル位置と一致する場合、Stackでカーソルを重ねる
            if (index == cursorLineIndex &&
                widget.mode == TerminalMode.normal &&
                settings.showTerminalCursor) {
              // TextPainter.getOffsetForCaretを使用して、レンダリングエンジンが計算した正確なカーソル位置を取得
              double cursorLeft;
              double charWidth;

              // 行全体のテキストとスタイルを使用してTextPainterを作成
              final textSpanFull = _parser.lineToTextSpan(
                line,
                fontSize: fontSize,
                fontFamily: settings.fontFamily,
              );

              final painter = TextPainter(
                text: textSpanFull,
                textDirection: TextDirection.ltr,
                textScaler: TextScaler.noScaling,
              )..layout();

              // 行のプレーンテキストを取得
              final lineText = line.segments.map((s) => s.text).join();
              final lineTextLength = lineText.length;

              // 全角文字を考慮してカラム位置を文字オフセットに変換
              // tmuxのcursor_xはカラム位置（全角=2）だが、
              // TextPositionは文字オフセット（全角=1）を期待する
              final lineDisplayWidth = FontCalculator.getTextDisplayWidth(lineText);
              final charOffset = FontCalculator.columnToCharOffset(lineText, widget.cursorX);

              if (widget.cursorX <= lineDisplayWidth) {
                 // カーソルが行内にある場合、getOffsetForCaretで位置を取得
                 final offset = painter.getOffsetForCaret(
                   TextPosition(offset: charOffset),
                   Rect.zero,
                 );
                 cursorLeft = offset.dx;

                 // カーソル幅も現在の文字の位置から取得（次の文字までの幅）
                 // 行末の場合は標準幅を使用
                 if (charOffset < lineTextLength) {
                    final nextOffset = painter.getOffsetForCaret(
                      TextPosition(offset: charOffset + 1),
                      Rect.zero,
                    );
                    charWidth = nextOffset.dx - offset.dx;
                 } else {
                    charWidth = FontCalculator.measureCharWidth(settings.fontFamily, fontSize);
                 }
              } else {
                 // カーソルが行末より先にある場合（空行や行末以降のスペース）
                 // 行末の位置を取得し、超過分を加算
                 cursorLeft = painter.width;
                 charWidth = FontCalculator.measureCharWidth(settings.fontFamily, fontSize);
                 cursorLeft += (widget.cursorX - lineDisplayWidth) * charWidth;
              }

              lineWidget = Stack(
                clipBehavior: Clip.none,
                children: [
                  lineWidget,
                  ValueListenableBuilder<bool>(
                    valueListenable: _caretVisible,
                    builder: (context, visible, child) {
                      if (!visible) {
                        return const SizedBox.shrink();
                      }
                      // キャレットの高さを文字サイズに合わせる（行間を含めない）
                      final caretHeight = fontSize;
                      // 行内で垂直方向に中央寄せ
                      final caretTop = (_lineHeight - caretHeight) / 2;
                      return Positioned(
                        left: cursorLeft,
                        top: caretTop,
                        width: 2,
                        height: caretHeight,
                        child: Container(
                          color: DesignColors.primary,
                        ),
                      );
                    },
                  ),
                ],
              );
            }

            // 固定幅コンテナ（水平スクロール用）
            if (needsHorizontalScroll) {
              lineWidget = SizedBox(
                width: terminalWidth,
                child: lineWidget,
              );
            }

            return lineWidget;
          },
        );

        // 水平スクロールが必要な場合
        if (needsHorizontalScroll) {
          listWidget = SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: terminalWidth,
              height: constraints.maxHeight,
              child: listWidget,
            ),
          );
        }

        // scrollSend: 1 本指ドラッグ認識子を zoom 認識子より「内側（深い hit-test）」
        // に置く（B5 実測: 外側に置くと gesture arena の競合で連続 Update が欠落
        // するため。内側なら ListView 同様に 1 本指ドラッグが先に勝利する）。
        // onTap は配置しない（タップ認識子がドラッグの連続 Update を欠落させる
        // ため・B5 実測）。2 本指操作は Listener でポインタ数監視して抑止（M5）。
        if (widget.mode == TerminalMode.scrollSend) {
          listWidget = Listener(
            onPointerDown: (_) => _activePointers++,
            onPointerUp: (_) => _activePointers--,
            onPointerCancel: (_) => _activePointers--,
            child: GestureDetector(
              key: const ValueKey('terminal-scroll-send-gesture'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: _onScrollSendDragStart,
              onVerticalDragUpdate: _onScrollSendDragUpdate,
              onVerticalDragEnd: _onScrollSendDragEnd,
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
        if (widget.zoomEnabled && widget.mode != TerminalMode.scrollSend) {
          // RawGestureDetectorで2本指検出時にgesture arenaを強制勝利
          listWidget = RawGestureDetector(
            key: const ValueKey('terminal-two-finger-gesture'),
            gestures: <Type, GestureRecognizerFactory>{
              _EagerScaleGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _EagerScaleGestureRecognizer
                  >(
                    () => _EagerScaleGestureRecognizer(),
                    (_EagerScaleGestureRecognizer instance) {
                      instance
                        ..onStart = _onScaleStart
                        ..onUpdate = _onScaleUpdate
                        ..onEnd = _onScaleEnd;
                    },
                  ),
            },
            child: Transform.scale(
              scale: _currentScale,
              alignment: Alignment.topLeft,
              child: listWidget,
            ),
          );
        }

        // select モードの場合はテキスト選択を有効化（select 専用・D12）
        if (isSelectMode) {
          return Container(
            color: widget.backgroundColor,
            child: SelectionArea(
              child: listWidget,
            ),
          );
        }

        // scrollSend モード: アプリへスクロール送信専用（D5）。
        // - ローカルスクロール無効（NeverScrollableScrollPhysics・上で適用）
        // - テキスト選択なし（SelectionArea 非配置）
        // - ホールド+スワイプ無効（longPress ハンドラを配置しない）
        // - 2 本指スワイプ無効（_onScaleEnd ガード + ポインタ数監視・M5。ピンチは維持）
        // - Focus 追加（物理キーボード PgUp/PgDn 送信用・現状 normal 分岐のみのため）
        // - 1 本指ドラッグ → ティック換算 → onScrollSendTicks で TerminalScreen へ
        if (widget.mode == TerminalMode.scrollSend) {
          return Container(
            color: widget.backgroundColor,
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: _handleKeyEvent,
              child: listWidget,
            ),
          );
        }

        // 通常モード：キーボード入力をハンドリング
        // ホールド+スワイプで矢印キー入力対応
        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: GestureDetector(
            key: const ValueKey('terminal-input-gesture'),
            onTap: () {
              _focusNode.requestFocus();
              widget.onTap?.call();
            },
            onLongPressStart: _onLongPressStart,
            onLongPressMoveUpdate: _onLongPressMoveUpdate,
            onLongPressEnd: _onLongPressEnd,
            child: Stack(
              children: [
                Container(
                  color: widget.backgroundColor,
                  child: listWidget,
                ),
                // ホールド+スワイプオーバーレイ
                if (_isLongPressing) _buildSwipeOverlay(),
                // 2本指スワイプオーバーレイ
                if (_isTwoFingerPanning || _twoFingerSwipeResult != null)
                  _buildTwoFingerSwipeOverlay(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// キーイベントをハンドリング
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onKeyInput == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final key = event.logicalKey;

      // 修飾キーの状態を更新
      if (key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        _ctrlPressed = true;
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight) {
        _altPressed = true;
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight) {
        _shiftPressed = true;
        return KeyEventResult.handled;
      }

      // 特殊キーの処理
      String? data;
      bool isSpecialKey = false;
      String? tmuxKeyName;

      if (key == LogicalKeyboardKey.escape) {
        data = '\x1b';
        isSpecialKey = true;
        tmuxKeyName = 'Escape';
      } else if (key == LogicalKeyboardKey.enter) {
        // Shift+Enterの場合は別のキー名で送信
        if (_shiftPressed) {
          data = '\x1b[27;2;13~'; // xterm拡張: Shift+Enter
          isSpecialKey = true;
          tmuxKeyName = 'S-Enter';
          _shiftPressed = false;
        } else {
          data = '\r';
          isSpecialKey = true;
          tmuxKeyName = 'Enter';
        }
      } else if (key == LogicalKeyboardKey.backspace) {
        data = '\x7f';
        isSpecialKey = true;
        tmuxKeyName = 'BSpace';
      } else if (key == LogicalKeyboardKey.delete) {
        data = _getParamSequence(3, '~');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('DC');
      } else if (key == LogicalKeyboardKey.tab) {
        if (_shiftPressed) {
          data = '\x1b[Z';
          tmuxKeyName = 'BTab';
          _shiftPressed = false;
        } else {
          data = '\t';
          tmuxKeyName = 'Tab';
        }
        isSpecialKey = true;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        data = _getArrowSequence('A');
        isSpecialKey = true;
        tmuxKeyName = _getArrowTmuxKey('Up');
      } else if (key == LogicalKeyboardKey.arrowDown) {
        data = _getArrowSequence('B');
        isSpecialKey = true;
        tmuxKeyName = _getArrowTmuxKey('Down');
      } else if (key == LogicalKeyboardKey.arrowRight) {
        data = _getArrowSequence('C');
        isSpecialKey = true;
        tmuxKeyName = _getArrowTmuxKey('Right');
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        data = _getArrowSequence('D');
        isSpecialKey = true;
        tmuxKeyName = _getArrowTmuxKey('Left');
      } else if (key == LogicalKeyboardKey.home) {
        data = _getFinalCharSequence('H');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('Home');
      } else if (key == LogicalKeyboardKey.end) {
        data = _getFinalCharSequence('F');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('End');
      } else if (key == LogicalKeyboardKey.pageUp) {
        data = _getParamSequence(5, '~');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('PPage');
      } else if (key == LogicalKeyboardKey.pageDown) {
        data = _getParamSequence(6, '~');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('NPage');
      } else if (key == LogicalKeyboardKey.f1) {
        data = _getFKeySequence('P');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F1');
      } else if (key == LogicalKeyboardKey.f2) {
        data = _getFKeySequence('Q');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F2');
      } else if (key == LogicalKeyboardKey.f3) {
        data = _getFKeySequence('R');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F3');
      } else if (key == LogicalKeyboardKey.f4) {
        data = _getFKeySequence('S');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F4');
      } else if (key == LogicalKeyboardKey.f5) {
        data = _getParamSequence(15, '~');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F5');
      } else if (key == LogicalKeyboardKey.f6) {
        data = _getParamSequence(17, '~');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F6');
      } else if (key == LogicalKeyboardKey.f7) {
        data = _getParamSequence(18, '~');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F7');
      } else if (key == LogicalKeyboardKey.f8) {
        data = _getParamSequence(19, '~');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F8');
      } else if (key == LogicalKeyboardKey.f9) {
        data = _getParamSequence(20, '~');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F9');
      } else if (key == LogicalKeyboardKey.f10) {
        data = _getParamSequence(21, '~');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F10');
      } else if (key == LogicalKeyboardKey.f11) {
        data = _getParamSequence(23, '~');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F11');
      } else if (key == LogicalKeyboardKey.f12) {
        data = _getParamSequence(24, '~');
        isSpecialKey = true;
        tmuxKeyName = _getModifiedTmuxKey('F12');
      } else if (event.character != null && event.character!.isNotEmpty) {
        // 通常文字
        data = event.character!;

        // Ctrl+文字の処理
        if (_ctrlPressed && data.length == 1) {
          final code = data.codeUnitAt(0);
          if ((code >= 0x61 && code <= 0x7a) ||
              (code >= 0x41 && code <= 0x5a)) {
            data = String.fromCharCode(code & 0x1f);
          }
        }

        // Alt+文字の処理
        if (_altPressed) {
          data = '\x1b$data';
        }
      }

      if (data != null) {
        widget.onKeyInput!(KeyInputEvent(
          data: data,
          isSpecialKey: isSpecialKey,
          tmuxKeyName: tmuxKeyName,
        ));
        return KeyEventResult.handled;
      }
    } else if (event is KeyUpEvent) {
      final key = event.logicalKey;

      // 修飾キーの解除
      if (key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        _ctrlPressed = false;
      } else if (key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight) {
        _altPressed = false;
      } else if (key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight) {
        _shiftPressed = false;
      }
    }

    return KeyEventResult.ignored;
  }

  /// 矢印キーのシーケンスを取得
  String _getArrowSequence(String code) {
    if (_shiftPressed) {
      return '\x1b[1;2$code';
    } else if (_ctrlPressed) {
      return '\x1b[1;5$code';
    } else if (_altPressed) {
      return '\x1b[1;3$code';
    }
    return '\x1b[$code';
  }

  /// 矢印キーのtmux形式キー名を取得
  String _getArrowTmuxKey(String direction) {
    if (_shiftPressed) {
      return 'S-$direction';
    } else if (_ctrlPressed) {
      return 'C-$direction';
    } else if (_altPressed) {
      return 'M-$direction';
    }
    return direction;
  }

  /// 修飾子付きtmuxキー名を取得（汎用: Home/End/PPage/NPage/DC等）
  /// 修飾子フラグを消費（リセット）する
  String _getModifiedTmuxKey(String baseKey) {
    if (_shiftPressed) {
      _shiftPressed = false;
      return 'S-$baseKey';
    } else if (_ctrlPressed) {
      _ctrlPressed = false;
      return 'C-$baseKey';
    } else if (_altPressed) {
      _altPressed = false;
      return 'M-$baseKey';
    }
    return baseKey;
  }

  /// 修飾子付きCSIシーケンス: 最終文字型（Home: \x1b[H, End: \x1b[F）
  /// 修飾子あり: \x1b[1;{mod}{finalChar}
  String _getFinalCharSequence(String finalChar) {
    final mod = _shiftPressed ? 2 : _ctrlPressed ? 5 : _altPressed ? 3 : 0;
    if (mod == 0) return '\x1b[$finalChar';
    return '\x1b[1;$mod$finalChar';
  }

  /// 修飾子付きCSIシーケンス: パラメータ型（PageUp: \x1b[5~, Delete: \x1b[3~）
  /// 修飾子あり: \x1b[{param};{mod}~
  String _getParamSequence(int param, String suffix) {
    final mod = _shiftPressed ? 2 : _ctrlPressed ? 5 : _altPressed ? 3 : 0;
    if (mod == 0) return '\x1b[$param$suffix';
    return '\x1b[$param;$mod$suffix';
  }

  /// F1-F4用シーケンス（SS3形式、修飾子ありならCSI形式に変換）
  /// F1=P, F2=Q, F3=R, F4=S
  /// 修飾子なし: \x1bO{code}, 修飾子あり: \x1b[1;{mod}{code}
  String _getFKeySequence(String code) {
    final mod = _shiftPressed ? 2 : _ctrlPressed ? 5 : _altPressed ? 3 : 0;
    if (mod == 0) return '\x1bO$code';
    return '\x1b[1;$mod$code';
  }

  // === 修飾キートグル（外部からの制御用） ===

  void toggleCtrl() {
    setState(() {
      _ctrlPressed = !_ctrlPressed;
    });
    HapticFeedback.selectionClick();
  }

  void toggleAlt() {
    setState(() {
      _altPressed = !_altPressed;
    });
    HapticFeedback.selectionClick();
  }

  void toggleShift() {
    setState(() {
      _shiftPressed = !_shiftPressed;
    });
    HapticFeedback.selectionClick();
  }

  bool get ctrlPressed => _ctrlPressed;
  bool get altPressed => _altPressed;
  bool get shiftPressed => _shiftPressed;

  void resetModifiers() {
    setState(() {
      _ctrlPressed = false;
      _altPressed = false;
      _shiftPressed = false;
    });
  }

  // === scrollSend ドラッグ処理（D5・M2） ===

  void _onScrollSendDragStart(DragStartDetails details) {
    _scrollTickFraction = 0;
  }

  void _onScrollSendDragUpdate(DragUpdateDetails details) {
    if (_lineHeight <= 0) return;
    // M5: 2 本指以上の操作は送信ドラッグとして扱わない（2 本指パンによる
    // 誤送信を防止。ペイン切替は scrollSend 中は無効）。
    if (_activePointers > 1) return;
    // 1 ティック = 行高 × 1.5（M2）。上ドラッグ（delta.dy < 0）= 上スクロール
    // 送信（ticks > 0）。累積ティックは TerminalScreen 側（合流送信）へ通知。
    final tickHeight = _lineHeight * 1.5;
    final deltaTicks = -details.delta.dy / tickHeight;
    final ticks = _emitScrollTicks(deltaTicks);
    if (ticks != 0) {
      widget.onScrollSendTicks?.call(ticks);
    }
  }

  void _onScrollSendDragEnd(DragEndDetails details) {
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
        _scrollTickFraction == 0 ||
        _scrollTickFraction.sign == deltaTicks.sign;
    if (!sameDirection) {
      if (deltaTicks.abs() < 0.25) return 0;
      _scrollTickFraction = 0;
    }
    _scrollTickFraction += deltaTicks;
    final whole = _scrollTickFraction.truncate();
    _scrollTickFraction -= whole.toDouble();
    return whole;
  }

  // === スクロール制御 ===

  /// 指定した行インデックスがビューポート最上部に来るよう即座にスクロールする。
  /// 履歴プリペンド後、「直前に最上部だった行」を同じ位置に留めるために使う
  /// （追加行数ぶん絶対位置で移動するので、途中位置へ飛ばない）。
  void jumpToLineFromTop(int lineIndex, [int attempt = 0]) {
    if (!mounted || !_verticalScrollController.hasClients) return;
    final pos = _verticalScrollController.position;
    final target = lineIndex * _lineHeight;
    // 巨大コンテンツでは Sliver が末尾までレイアウトされるまで maxScrollExtent が
    // 小さいまま。現在の最大までジャンプして遅延ビルドを進め、ターゲットに届くまで
    // 数フレーム繰り返す。
    if (pos.maxScrollExtent + 1.0 < target && attempt < 60) {
      _verticalScrollController.jumpTo(pos.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => jumpToLineFromTop(lineIndex, attempt + 1),
      );
      return;
    }
    _verticalScrollController.jumpTo(target.clamp(0.0, pos.maxScrollExtent));
  }

  /// 一番下までスクロール
  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_verticalScrollController.hasClients) {
        _verticalScrollController.animateTo(
          _verticalScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 一番上までスクロール
  void scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_verticalScrollController.hasClients) {
        _verticalScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// カーソル位置までスクロール
  void scrollToCaret() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_verticalScrollController.hasClients) return;

      final parsedLines = _cachedParsedLines;
      if (parsedLines == null || parsedLines.isEmpty) return;

      // カーソル行インデックスを計算（build内と同じロジック）
      final int cursorLineIndex;
      if (parsedLines.length >= widget.paneHeight) {
        cursorLineIndex =
            parsedLines.length - widget.paneHeight + widget.cursorY;
      } else {
        cursorLineIndex = widget.cursorY;
      }

      // カーソル行のスクロールオフセット
      final targetOffset = cursorLineIndex * _lineHeight;

      // ビューポート高さを考慮し、カーソル行が中央付近に来るよう調整
      final viewportHeight =
          _verticalScrollController.position.viewportDimension;
      final centeredOffset =
          targetOffset - (viewportHeight / 2) + (_lineHeight / 2);

      // 有効範囲にクランプ
      final maxExtent = _verticalScrollController.position.maxScrollExtent;
      final clampedOffset = centeredOffset.clamp(0.0, maxExtent);

      _verticalScrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
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
