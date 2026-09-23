import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart';
import '../../../providers/terminal_display_provider.dart';
import '../../../services/backend/domain/pane_frame_reader.dart';
import '../../../services/terminal/font_calculator.dart';
import '../../../services/terminal/terminal_font_styles.dart';
import '../../../services/tmux/pane_navigator.dart';
import 'ansi_display_model.dart';
import 'ansi_gesture_engine.dart';
import 'ansi_key_composer.dart';
import 'ansi_key_input_engine.dart';
import 'ansi_line_row.dart';
import 'ansi_scroll_driver.dart';
import 'ansi_terminal_model.dart';
import 'ansi_terminal_view.dart';
import 'terminal_zoom.dart';

export 'ansi_terminal_model.dart' show KeyInputEvent, TerminalMode;

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

  /// herdr のカーソル情報（Phase 4）。
  ///
  /// null なら従来どおり [cursorX] / [cursorY]（tmux 等）を描画する。
  /// 非 null の場合、[PaneCaret.visible] == false・位置不明（x/y null）・
  /// 範囲外（frame 寸法を超える）は**カーソルを描画しない**（従来の
  /// cursorX/cursorY へフォールバックしない。`cursor: null` 観測と正当な
  /// `(0,0)` を nullable で分離するため）。座標変換（[FontCalculator]
  /// による全角セル・行末のオフセット計算）は [cursorX] / [cursorY] と
  /// 同じ経路へ集約する。
  final PaneCaret? caret;

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
    this.caret,
    this.onArrowSwipe,
    this.onTwoFingerSwipe,
    this.navigableDirections,
    this.onTap,
    this.onScrollSendTicks,
  });

  @override
  ConsumerState<AnsiTextView> createState() => AnsiTextViewState();
}

/// AnsiTextView のファサード State（P3-2 合成ルート）。
///
/// 表示モデル・キーエンジン・ジェスチャーエンジン・スクロールドライバーを
/// has-a で所有し、公開 API の委譲と [AnsiTerminalView] への配線のみを行う。
/// 協調オブジェクトはすべて initState で生成（`late final`）する。
/// テストが `AnsiTextViewState()` を直接 new した場合も、静的委譲
/// （[deriveBaseChar]/[isAsciiPrintable]）はインスタンス状態に触れない。
class AnsiTextViewState extends ConsumerState<AnsiTextView>
    implements AnsiGestureHost, AnsiScrollDriverHost {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _horizontalScrollController = ScrollController();

  /// キャレット点滅用（離散トグル）。連続アニメだと毎 vsync 再描画され、
  /// 待機中も 60-120fps を消費するため、500ms ごとに ON/OFF を切り替える。
  Timer? _caretBlinkTimer;
  final ValueNotifier<bool> _caretVisible = ValueNotifier<bool>(true);

  /// 表示モデル（parser・キャッシュ・行高の所有）。
  late final AnsiDisplayModel _content;

  /// キーイベント状態機械（修飾子 4 状態の所有）。
  late final AnsiKeyInputEngine _keyEngine;

  /// タッチ操作状態機械（ズーム・スワイプ・ティックの所有）。
  late final AnsiGestureEngine _gestureEngine;

  /// 垂直スクロールの所有と制御命令。
  late final AnsiScrollDriver _scrollDriver;

  /// 描画に使う解決済みカーソル位置と描画可否。
  ({int x, int y, bool draw}) get _resolvedCaret =>
      AnsiDisplayModel.resolveCaret(
        caret: widget.caret,
        cursorX: widget.cursorX,
        cursorY: widget.cursorY,
      );

  @override
  void initState() {
    super.initState();
    // 協調オブジェクトは initState / late final で生成する（フィールド
    // 初期化子にしない）。`AnsiTextViewState()` を直接 new するテストが
    // LateInitializationError を起こさないための規約（v2・critique §2.3）。
    _content = AnsiDisplayModel(
      foreground: widget.foregroundColor,
      background: widget.backgroundColor,
    );
    _gestureEngine = AnsiGestureEngine(host: this);
    _keyEngine = AnsiKeyInputEngine();
    _scrollDriver = AnsiScrollDriver(content: _content, host: this);

    // 外部からScrollControllerが渡されていない場合は内部で作成
    _scrollDriver.attach();

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
      // 色変更時のみ AnsiParser を再生成しキャッシュを無効化する
      // （現行の parser 再生成→_invalidateCache と等価）。
      _content.updatePalette(
        foreground: widget.foregroundColor,
        background: widget.backgroundColor,
      );
    }
  }

  @override
  void dispose() {
    _caretBlinkTimer?.cancel();
    _caretVisible.dispose();
    _focusNode.dispose();
    _horizontalScrollController.dispose();
    // 内部で作成した場合のみ破棄
    _scrollDriver.dispose();
    super.dispose();
  }

  // === 公開 API（委譲） ===

  /// ズームをリセット
  void resetZoom() => _gestureEngine.resetZoom();

  /// 現在のズームスケールを取得
  double get currentScale => _gestureEngine.currentScale;

  /// 指定した行インデックスがビューポート最上部に来るよう即座にスクロールする。
  void jumpToLineFromTop(int lineIndex, [int attempt = 0]) =>
      _scrollDriver.jumpToLineFromTop(lineIndex, attempt);

  /// 一番下までスクロール
  Future<void> scrollToBottom() => _scrollDriver.scrollToBottom();

  /// コンテンツ追従で最下部へジャンプする（自動スクロール・Issue #87）。
  void followToBottom([int attempt = 0]) =>
      _scrollDriver.followToBottom(attempt);

  /// 一番上までスクロール
  void scrollToTop() => _scrollDriver.scrollToTop();

  /// カーソル位置までスクロール
  void scrollToCaret() => _scrollDriver.scrollToCaret();

  // === 修飾キートグル（外部からの制御用） ===

  void toggleCtrl() {
    setState(() => _keyEngine.toggleCtrl());
    HapticFeedback.selectionClick();
  }

  void toggleAlt() {
    setState(() => _keyEngine.toggleAlt());
    HapticFeedback.selectionClick();
  }

  void toggleShift() {
    setState(() => _keyEngine.toggleShift());
    HapticFeedback.selectionClick();
  }

  bool get ctrlPressed => _keyEngine.ctrlPressed;
  bool get altPressed => _keyEngine.altPressed;
  bool get shiftPressed => _keyEngine.shiftPressed;

  void resetModifiers() {
    setState(_keyEngine.resetModifiers);
  }

  /// 単一の ASCII 印字可能文字 (0x20-0x7E) かどうか
  ///
  /// テストから直接参照するため公開している（@visibleForTesting）。
  @visibleForTesting
  static bool isAsciiPrintable(String s) => AnsiKeyComposer.isAsciiPrintable(s);

  /// event.character が非 ASCII（OS 合成文字）の場合に logicalKey から
  /// ASCII 文字を導出する（静的委譲・インスタンス状態不使用）。
  ///
  /// テストから直接参照するため公開している（@visibleForTesting）。
  @visibleForTesting
  String? deriveBaseChar(String keyLabel, {bool shiftPressed = false}) =>
      AnsiKeyComposer.deriveBaseChar(keyLabel, shiftPressed: shiftPressed);

  // === キーイベント（エンジン経由・ライブ参照） ===

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) =>
      _keyEngine.handleKeyEvent(node, event, onKeyInput: widget.onKeyInput);

  // === AnsiGestureHost 実装 ===

  @override
  TerminalMode get mode => widget.mode;

  @override
  bool get zoomEnabled => widget.zoomEnabled;

  @override
  Map<SwipeDirection, bool>? get navigableDirections =>
      widget.navigableDirections;

  @override
  void Function(SwipeDirection direction)? get onTwoFingerSwipe =>
      widget.onTwoFingerSwipe;

  @override
  void Function(String direction)? get onArrowSwipe => widget.onArrowSwipe;

  @override
  void Function(int ticks)? get onScrollSendTicks => widget.onScrollSendTicks;

  @override
  void Function(double scale)? get onZoomChanged => widget.onZoomChanged;

  @override
  double get lineHeight => _content.lineHeight;

  @override
  bool get isMounted => mounted;

  @override
  void notifyChanged() {
    if (mounted) setState(() {});
  }

  @override
  void commitZoom(double scale) {
    final settings = ref.read(settingsProvider);
    final committed = clampZoomFactor(settings.zoomFactor * scale);
    ref.read(settingsProvider.notifier).setZoomFactor(committed);
    widget.onZoomChanged?.call(1.0);
    if (mounted) setState(() {});
  }

  // === AnsiScrollDriverHost 実装 ===

  @override
  ScrollController? get externalVerticalScrollController =>
      widget.verticalScrollController;

  @override
  int get paneHeight => widget.paneHeight;

  @override
  ({int x, int y, bool draw}) get resolvedCaret => _resolvedCaret;

  @override
  bool get isActive => mounted;

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
              ref
                  .read(terminalDisplayProvider.notifier)
                  .updateScreenSize(
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
        final parsedLines = _content.parsedLines(
          text: widget.text,
          fontSize: fontSize,
          fontFamily: settings.fontFamily,
        );

        // 行に依存しない基本スタイルは1回だけ計算
        // （itemBuilder内での毎フレームGoogleFonts呼び出しを回避）
        final baseTextStyle = TerminalFontStyles.getTextStyle(
          settings.fontFamily,
          fontSize: fontSize,
          height: FontCalculator.lineHeightRatio,
          color: widget.foregroundColor,
        );

        final lineHeight = _content.lineHeight;

        // コンテンツがビューポートに満たない場合、先頭パディングで下端に揃える
        // （履歴が少ないライブ表示でもターミナルとして自然な見た目になる）。
        // コンテンツ高 ≥ ビューポート高ならパディングなし（従来動作を維持）。
        final contentHeight = parsedLines.length * lineHeight;
        final viewportHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : contentHeight;
        final bottomAlignPadding = contentHeight < viewportHeight
            ? viewportHeight - contentHeight
            : 0.0;

        final resolvedCaret = _resolvedCaret;

        return AnsiTerminalView(
          verticalController: _scrollDriver.controller,
          padding: EdgeInsets.only(top: bottomAlignPadding),
          physics: widget.mode == TerminalMode.scrollSend
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          itemCount: parsedLines.length,
          itemExtent: lineHeight,
          rowBuilder: (context, index) => AnsiLineRow(
            line: parsedLines[index],
            index: index,
            content: _content,
            parsedLineCount: parsedLines.length,
            paneHeight: widget.paneHeight,
            mode: widget.mode,
            showTerminalCursor: settings.showTerminalCursor,
            resolvedCaret: resolvedCaret,
            caretVisible: _caretVisible,
            baseTextStyle: baseTextStyle,
            fontSize: fontSize,
            fontFamily: settings.fontFamily,
            terminalWidth: terminalWidth,
            lineHeight: lineHeight,
            needsHorizontalScroll: needsHorizontalScroll,
          ),
          needsHorizontalScroll: needsHorizontalScroll,
          terminalWidth: terminalWidth,
          viewportHeight: constraints.maxHeight,
          horizontalController: _horizontalScrollController,
          mode: widget.mode,
          isSelectMode: isSelectMode,
          zoomEnabled: widget.zoomEnabled,
          backgroundColor: widget.backgroundColor,
          currentScale: _gestureEngine.currentScale,
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          onTap: widget.onTap,
          onLongPressStart: _gestureEngine.onLongPressStart,
          onLongPressMoveUpdate: _gestureEngine.onLongPressMoveUpdate,
          onLongPressEnd: _gestureEngine.onLongPressEnd,
          onScaleStart: _gestureEngine.onScaleStart,
          onScaleUpdate: _gestureEngine.onScaleUpdate,
          onScaleEnd: _gestureEngine.onScaleEnd,
          onScrollSendDragStart: _gestureEngine.onScrollSendDragStart,
          onScrollSendDragUpdate: _gestureEngine.onScrollSendDragUpdate,
          onScrollSendDragEnd: _gestureEngine.onScrollSendDragEnd,
          onPointerDown: _gestureEngine.pointerDown,
          onPointerUp: _gestureEngine.pointerUp,
          onPointerCancel: _gestureEngine.pointerCancel,
          isLongPressing: _gestureEngine.isLongPressing,
          lastSwipeDirection: _gestureEngine.lastSwipeDirection,
          isTwoFingerPanning: _gestureEngine.isTwoFingerPanning,
          twoFingerSwipeResult: _gestureEngine.twoFingerSwipeResult,
          twoFingerPanDelta: _gestureEngine.twoFingerPanDelta,
          navigableDirections: widget.navigableDirections,
        );
      },
    );
  }
}
