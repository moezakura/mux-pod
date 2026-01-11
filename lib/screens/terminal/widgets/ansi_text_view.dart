import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart';
import '../../../services/terminal/ansi_parser.dart';
import '../../../services/terminal/font_calculator.dart';
import '../../../services/terminal/terminal_font_styles.dart';

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
enum TerminalMode {
  /// 通常モード（キー入力が有効）
  normal,

  /// コピペモード（テキスト選択が有効、キー入力は無効）
  copyPaste,
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
  });

  @override
  ConsumerState<AnsiTextView> createState() => AnsiTextViewState();
}

class AnsiTextViewState extends ConsumerState<AnsiTextView> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final TransformationController _transformationController =
      TransformationController();

  late AnsiParser _parser;

  /// 修飾キー状態
  bool _ctrlPressed = false;
  bool _altPressed = false;
  bool _shiftPressed = false;

  /// 現在のズームスケール
  double _currentScale = 1.0;

  /// TextSpanキャッシュ
  TextSpan? _cachedTextSpan;
  String? _cachedText;
  double? _cachedFontSize;
  String? _cachedFontFamily;

  @override
  void initState() {
    super.initState();
    _parser = AnsiParser(
      defaultForeground: widget.foregroundColor,
      defaultBackground: widget.backgroundColor,
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
    _cachedTextSpan = null;
    _cachedText = null;
    _cachedFontSize = null;
    _cachedFontFamily = null;
  }

  /// TextSpanを取得（キャッシュ使用）
  TextSpan _getTextSpan({
    required double fontSize,
    required String fontFamily,
  }) {
    // キャッシュが有効かチェック
    if (_cachedTextSpan != null &&
        _cachedText == widget.text &&
        _cachedFontSize == fontSize &&
        _cachedFontFamily == fontFamily) {
      return _cachedTextSpan!;
    }

    // 新しくパースしてキャッシュ
    _cachedTextSpan = _parser.parseToTextSpan(
      widget.text,
      fontSize: fontSize,
      fontFamily: fontFamily,
    );
    _cachedText = widget.text;
    _cachedFontSize = fontSize;
    _cachedFontFamily = fontFamily;

    return _cachedTextSpan!;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  /// ズームをリセット
  void resetZoom() {
    _transformationController.value = Matrix4.identity();
    setState(() {
      _currentScale = 1.0;
    });
    widget.onZoomChanged?.call(1.0);
  }

  /// 現在のズームスケールを取得
  double get currentScale => _currentScale;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isCopyPasteMode = widget.mode == TerminalMode.copyPaste;

    return LayoutBuilder(
      builder: (context, constraints) {
        // フォントサイズを決定
        late final double fontSize;
        late final bool needsHorizontalScroll;

        if (settings.autoFitEnabled) {
          // 自動フィット: 画面幅に合わせて計算
          final calcResult = FontCalculator.calculate(
            screenWidth: constraints.maxWidth,
            paneCharWidth: widget.paneWidth,
            fontFamily: settings.fontFamily,
            minFontSize: settings.minFontSize,
          );
          fontSize = calcResult.fontSize;
          needsHorizontalScroll = calcResult.needsScroll;
        } else {
          // 手動設定: settings.fontSizeを使用
          fontSize = settings.fontSize;
          // 水平スクロールの必要性を判定
          final terminalWidth = FontCalculator.calculateTerminalWidth(
            paneCharWidth: widget.paneWidth,
            fontSize: fontSize,
            fontFamily: settings.fontFamily,
          );
          needsHorizontalScroll = terminalWidth > constraints.maxWidth;
        }

        // ターミナル幅を計算
        final terminalWidth = FontCalculator.calculateTerminalWidth(
          paneCharWidth: widget.paneWidth,
          fontSize: fontSize,
          fontFamily: settings.fontFamily,
        );

        // ANSIテキストをTextSpanに変換（キャッシュ使用）
        final textSpan = _getTextSpan(
          fontSize: fontSize,
          fontFamily: settings.fontFamily,
        );

        // テキストウィジェットを構築
        Widget textWidget = SelectableText.rich(
          textSpan,
          style: TerminalFontStyles.getTextStyle(
            settings.fontFamily,
            fontSize: fontSize,
            height: 1.4,
            color: widget.foregroundColor,
          ),
        );

        // 固定幅コンテナ
        textWidget = SizedBox(
          width: needsHorizontalScroll ? terminalWidth : null,
          child: textWidget,
        );

        // 水平スクロールが必要な場合
        if (needsHorizontalScroll) {
          textWidget = SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: textWidget,
          );
        }

        // 垂直スクロール
        textWidget = SingleChildScrollView(
          controller: _verticalScrollController,
          child: textWidget,
        );

        // ピンチズームが有効な場合、InteractiveViewerでラップ
        if (widget.zoomEnabled) {
          textWidget = InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.5,
            maxScale: 5.0,
            panEnabled: true,
            scaleEnabled: true,
            onInteractionEnd: (details) {
              // ズームスケールを取得して通知
              final scale = _transformationController.value.getMaxScaleOnAxis();
              if (scale != _currentScale) {
                setState(() {
                  _currentScale = scale;
                });
                widget.onZoomChanged?.call(scale);
              }
            },
            child: textWidget,
          );
        }

        // コピペモードの場合はキー入力を無効化
        if (isCopyPasteMode) {
          return Container(
            color: widget.backgroundColor,
            child: textWidget,
          );
        }

        // 通常モード：キーボード入力をハンドリング
        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            child: Container(
              color: widget.backgroundColor,
              child: textWidget,
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
        data = '\x1b[3~';
        isSpecialKey = true;
        tmuxKeyName = 'DC';
      } else if (key == LogicalKeyboardKey.tab) {
        data = '\t';
        isSpecialKey = true;
        tmuxKeyName = 'Tab';
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
        data = '\x1b[H';
        isSpecialKey = true;
        tmuxKeyName = 'Home';
      } else if (key == LogicalKeyboardKey.end) {
        data = '\x1b[F';
        isSpecialKey = true;
        tmuxKeyName = 'End';
      } else if (key == LogicalKeyboardKey.pageUp) {
        data = '\x1b[5~';
        isSpecialKey = true;
        tmuxKeyName = 'PPage';
      } else if (key == LogicalKeyboardKey.pageDown) {
        data = '\x1b[6~';
        isSpecialKey = true;
        tmuxKeyName = 'NPage';
      } else if (key == LogicalKeyboardKey.f1) {
        data = '\x1bOP';
        isSpecialKey = true;
        tmuxKeyName = 'F1';
      } else if (key == LogicalKeyboardKey.f2) {
        data = '\x1bOQ';
        isSpecialKey = true;
        tmuxKeyName = 'F2';
      } else if (key == LogicalKeyboardKey.f3) {
        data = '\x1bOR';
        isSpecialKey = true;
        tmuxKeyName = 'F3';
      } else if (key == LogicalKeyboardKey.f4) {
        data = '\x1bOS';
        isSpecialKey = true;
        tmuxKeyName = 'F4';
      } else if (key == LogicalKeyboardKey.f5) {
        data = '\x1b[15~';
        isSpecialKey = true;
        tmuxKeyName = 'F5';
      } else if (key == LogicalKeyboardKey.f6) {
        data = '\x1b[17~';
        isSpecialKey = true;
        tmuxKeyName = 'F6';
      } else if (key == LogicalKeyboardKey.f7) {
        data = '\x1b[18~';
        isSpecialKey = true;
        tmuxKeyName = 'F7';
      } else if (key == LogicalKeyboardKey.f8) {
        data = '\x1b[19~';
        isSpecialKey = true;
        tmuxKeyName = 'F8';
      } else if (key == LogicalKeyboardKey.f9) {
        data = '\x1b[20~';
        isSpecialKey = true;
        tmuxKeyName = 'F9';
      } else if (key == LogicalKeyboardKey.f10) {
        data = '\x1b[21~';
        isSpecialKey = true;
        tmuxKeyName = 'F10';
      } else if (key == LogicalKeyboardKey.f11) {
        data = '\x1b[23~';
        isSpecialKey = true;
        tmuxKeyName = 'F11';
      } else if (key == LogicalKeyboardKey.f12) {
        data = '\x1b[24~';
        isSpecialKey = true;
        tmuxKeyName = 'F12';
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
}
