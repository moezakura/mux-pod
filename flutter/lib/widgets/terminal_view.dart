import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../providers/settings_provider.dart';
import '../theme/terminal_colors.dart';

/// ターミナルビューウィジェット
///
/// xterm.dartのTerminalViewをラップして追加機能を提供する。
/// - 設定に基づくフォント/カラー適用
/// - パフォーマンス最適化（RepaintBoundary, スロットリング）
/// - ジェスチャー処理
class TerminalViewWidget extends ConsumerStatefulWidget {
  const TerminalViewWidget({
    super.key,
    required this.terminal,
    this.onResize,
    this.onHorizontalSwipe,
    this.onVerticalSwipe,
    this.autoResize = true,
  });

  final Terminal terminal;
  final void Function(int width, int height)? onResize;
  final void Function(SwipeDirection direction)? onHorizontalSwipe;
  final void Function(SwipeDirection direction)? onVerticalSwipe;
  final bool autoResize;

  @override
  ConsumerState<TerminalViewWidget> createState() => _TerminalViewWidgetState();
}

class _TerminalViewWidgetState extends ConsumerState<TerminalViewWidget> {
  late final TerminalController _controller;

  // Resize throttling
  Timer? _resizeTimer;
  int _pendingWidth = 0;
  int _pendingHeight = 0;
  static const _resizeThrottleDuration = Duration(milliseconds: 100);

  // Swipe detection
  Offset? _panStart;

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();

    // Terminal の onResize コールバックを設定（スロットリング付き）
    if (widget.onResize != null) {
      widget.terminal.onResize = _handleTerminalResize;
    }
  }

  void _handleTerminalResize(int width, int height, int pixelWidth, int pixelHeight) {
    _pendingWidth = width;
    _pendingHeight = height;

    // スロットリング：連続したリサイズを抑制
    _resizeTimer?.cancel();
    _resizeTimer = Timer(_resizeThrottleDuration, () {
      widget.onResize?.call(_pendingWidth, _pendingHeight);
    });
  }

  @override
  void dispose() {
    _resizeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terminalSettings = ref.watch(terminalSettingsProvider);
    final colorsAsync = ref.watch(terminalColorsProvider);

    // デフォルトカラー（ロード中はDracula）
    final colors = colorsAsync.when(
      data: (c) => c,
      loading: () => TerminalColorPresets.dracula,
      error: (_, __) => TerminalColorPresets.dracula,
    );

    return RepaintBoundary(
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: _OptimizedTerminalView(
          terminal: widget.terminal,
          controller: _controller,
          fontSize: terminalSettings.fontSize,
          fontFamily: terminalSettings.fontFamilyName,
          colors: colors,
          cursorBlink: terminalSettings.cursorBlink,
          autoResize: widget.autoResize,
        ),
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    _panStart = details.globalPosition;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // パン中は何もしない（終了時に処理）
  }

  void _onPanEnd(DragEndDetails details) {
    if (_panStart == null) return;

    final velocity = details.velocity.pixelsPerSecond;
    final dx = velocity.dx.abs();
    final dy = velocity.dy.abs();

    // 水平スワイプ
    if (dx > dy && dx > 200) {
      final direction = velocity.dx > 0 ? SwipeDirection.right : SwipeDirection.left;
      widget.onHorizontalSwipe?.call(direction);
    }
    // 垂直スワイプ
    else if (dy > dx && dy > 200) {
      final direction = velocity.dy > 0 ? SwipeDirection.down : SwipeDirection.up;
      widget.onVerticalSwipe?.call(direction);
    }

    _panStart = null;
  }
}

/// 最適化されたTerminalView
///
/// shouldRepaint制御とスケジューラ連携で不要な再描画を削減。
class _OptimizedTerminalView extends StatefulWidget {
  const _OptimizedTerminalView({
    required this.terminal,
    required this.controller,
    required this.fontSize,
    required this.fontFamily,
    required this.colors,
    required this.cursorBlink,
    required this.autoResize,
  });

  final Terminal terminal;
  final TerminalController controller;
  final double fontSize;
  final String fontFamily;
  final TerminalColors colors;
  final bool cursorBlink;
  final bool autoResize;

  @override
  State<_OptimizedTerminalView> createState() => _OptimizedTerminalViewState();
}

class _OptimizedTerminalViewState extends State<_OptimizedTerminalView> {
  // フレームスケジューラ用
  bool _frameScheduled = false;

  @override
  void didUpdateWidget(_OptimizedTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 設定変更時のみ再描画をスケジュール
    if (oldWidget.fontSize != widget.fontSize ||
        oldWidget.fontFamily != widget.fontFamily ||
        oldWidget.colors != widget.colors) {
      _scheduleFrame();
    }
  }

  void _scheduleFrame() {
    if (_frameScheduled) return;
    _frameScheduled = true;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _frameScheduled = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      widget.terminal,
      controller: widget.controller,
      autofocus: true,
      backgroundOpacity: 1.0,
      cursorType: TerminalCursorType.block,
      alwaysShowCursor: true,
      textStyle: TerminalStyle(
        fontSize: widget.fontSize,
        height: 1.2,
        fontFamily: widget.fontFamily,
        fontFamilyFallback: const [
          'JetBrains Mono',
          'Fira Code',
          'Consolas',
          'monospace',
        ],
      ),
      theme: TerminalTheme(
        cursor: _hexToColor(widget.colors.cursor),
        selection: _hexToColor(widget.colors.selection),
        foreground: _hexToColor(widget.colors.foreground),
        background: _hexToColor(widget.colors.background),
        black: _hexToColor(widget.colors.black),
        red: _hexToColor(widget.colors.red),
        green: _hexToColor(widget.colors.green),
        yellow: _hexToColor(widget.colors.yellow),
        blue: _hexToColor(widget.colors.blue),
        magenta: _hexToColor(widget.colors.magenta),
        cyan: _hexToColor(widget.colors.cyan),
        white: _hexToColor(widget.colors.white),
        brightBlack: _hexToColor(widget.colors.brightBlack),
        brightRed: _hexToColor(widget.colors.brightRed),
        brightGreen: _hexToColor(widget.colors.brightGreen),
        brightYellow: _hexToColor(widget.colors.brightYellow),
        brightBlue: _hexToColor(widget.colors.brightBlue),
        brightMagenta: _hexToColor(widget.colors.brightMagenta),
        brightCyan: _hexToColor(widget.colors.brightCyan),
        brightWhite: _hexToColor(widget.colors.brightWhite),
        searchHitBackground: _hexToColor(widget.colors.selection),
        searchHitBackgroundCurrent: _hexToColor(widget.colors.cursor),
        searchHitForeground: _hexToColor(widget.colors.foreground),
      ),
      autoResize: widget.autoResize,
    );
  }
}

/// スワイプ方向
enum SwipeDirection {
  left,
  right,
  up,
  down,
}

/// Hex文字列をColorに変換
Color _hexToColor(String hex) {
  final buffer = StringBuffer();
  if (hex.length == 6 || hex.length == 7) {
    buffer.write('ff');
  }
  buffer.write(hex.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}
