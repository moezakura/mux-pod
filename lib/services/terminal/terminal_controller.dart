import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// ターミナル入力イベント
class TerminalInputEvent {
  /// 入力データ
  final String data;

  /// 特殊キーかどうか
  final bool isSpecialKey;

  const TerminalInputEvent({
    required this.data,
    this.isSpecialKey = false,
  });
}

/// ターミナルサイズ変更イベント
class TerminalResizeEvent {
  final int cols;
  final int rows;
  final int pixelWidth;
  final int pixelHeight;

  const TerminalResizeEvent({
    required this.cols,
    required this.rows,
    this.pixelWidth = 0,
    this.pixelHeight = 0,
  });
}

/// ターミナル設定
class TerminalConfig {
  /// 最大行数
  final int maxLines;

  /// フォントサイズ
  final double fontSize;

  /// フォントファミリー
  final String fontFamily;

  /// カーソルタイプ
  final TerminalCursorType cursorType;

  /// カーソル点滅
  final bool cursorBlink;

  /// 背景の透明度
  final double backgroundOpacity;

  const TerminalConfig({
    this.maxLines = 10000,
    this.fontSize = 14.0,
    this.fontFamily = 'JetBrains Mono',
    this.cursorType = TerminalCursorType.block,
    this.cursorBlink = true,
    this.backgroundOpacity = 1.0,
  });

  TerminalConfig copyWith({
    int? maxLines,
    double? fontSize,
    String? fontFamily,
    TerminalCursorType? cursorType,
    bool? cursorBlink,
    double? backgroundOpacity,
  }) {
    return TerminalConfig(
      maxLines: maxLines ?? this.maxLines,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      cursorType: cursorType ?? this.cursorType,
      cursorBlink: cursorBlink ?? this.cursorBlink,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    );
  }
}

/// MuxPodターミナルコントローラー
///
/// xterm.dartのTerminalとTerminalControllerをラップし、
/// SSH/tmux操作に必要な機能を提供する。
class MuxTerminalController {
  /// xterm Terminal インスタンス
  late final Terminal terminal;

  /// xterm TerminalController インスタンス（選択・ハイライト用）
  late final TerminalController controller;

  /// ターミナル設定
  final TerminalConfig config;

  /// 入力データストリーム
  final _inputController = StreamController<TerminalInputEvent>.broadcast();

  /// リサイズイベントストリーム
  final _resizeController = StreamController<TerminalResizeEvent>.broadcast();

  /// ベルイベントストリーム
  final _bellController = StreamController<void>.broadcast();

  /// タイトル変更ストリーム
  final _titleController = StreamController<String>.broadcast();

  /// 修飾キー状態
  bool _ctrlPressed = false;
  bool _altPressed = false;
  bool _shiftPressed = false;

  /// 現在のターミナルサイズ
  int _cols = 80;
  int _rows = 24;

  /// 入力ストリーム
  Stream<TerminalInputEvent> get onInput => _inputController.stream;

  /// リサイズストリーム
  Stream<TerminalResizeEvent> get onResize => _resizeController.stream;

  /// ベルストリーム
  Stream<void> get onBell => _bellController.stream;

  /// タイトル変更ストリーム
  Stream<String> get onTitleChange => _titleController.stream;

  /// 現在のカラム数
  int get cols => _cols;

  /// 現在の行数
  int get rows => _rows;

  /// Ctrl キーが押されているか
  bool get ctrlPressed => _ctrlPressed;

  /// Alt キーが押されているか
  bool get altPressed => _altPressed;

  /// Shift キーが押されているか
  bool get shiftPressed => _shiftPressed;

  /// コンストラクタ
  MuxTerminalController({
    this.config = const TerminalConfig(),
  }) {
    // Terminal を初期化
    terminal = Terminal(
      maxLines: config.maxLines,
      onBell: _handleBell,
      onTitleChange: _handleTitleChange,
      onOutput: _handleOutput,
      onResize: _handleResize,
    );

    // TerminalController を初期化
    controller = TerminalController();
  }

  /// ベルハンドラ
  void _handleBell() {
    _bellController.add(null);
    // 触覚フィードバック
    HapticFeedback.mediumImpact();
  }

  /// タイトル変更ハンドラ
  void _handleTitleChange(String title) {
    _titleController.add(title);
  }

  /// 出力ハンドラ（ユーザー入力がターミナルに送信される）
  void _handleOutput(String data) {
    // 修飾キーを適用
    String processedData = data;

    if (_ctrlPressed && data.length == 1) {
      final code = data.codeUnitAt(0);
      // a-z または A-Z の場合、Ctrl コードに変換
      if ((code >= 0x61 && code <= 0x7a) || (code >= 0x41 && code <= 0x5a)) {
        processedData = String.fromCharCode((code & 0x1f));
      }
      _ctrlPressed = false;
    }

    if (_altPressed) {
      processedData = '\x1b$processedData';
      _altPressed = false;
    }

    _inputController.add(TerminalInputEvent(data: processedData));
  }

  /// リサイズハンドラ
  void _handleResize(int width, int height, int pixelWidth, int pixelHeight) {
    _cols = width;
    _rows = height;
    _resizeController.add(TerminalResizeEvent(
      cols: width,
      rows: height,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    ));
  }

  // ===== データ書き込み =====

  /// バイトデータをターミナルに書き込む
  void write(Uint8List data) {
    terminal.write(utf8.decode(data, allowMalformed: true));
  }

  /// 文字列をターミナルに書き込む
  void writeString(String data) {
    terminal.write(data);
  }

  /// ANSIエスケープシーケンスを書き込む
  void writeEscape(String sequence) {
    terminal.write('\x1b$sequence');
  }

  // ===== 特殊キー送信 =====

  /// ESCキーを送信
  void sendEscape() {
    _inputController.add(const TerminalInputEvent(
      data: '\x1b',
      isSpecialKey: true,
    ));
  }

  /// Tabキーを送信
  void sendTab() {
    _inputController.add(const TerminalInputEvent(
      data: '\t',
      isSpecialKey: true,
    ));
  }

  /// Enterキーを送信
  void sendEnter() {
    _inputController.add(const TerminalInputEvent(
      data: '\r',
      isSpecialKey: true,
    ));
  }

  /// Backspaceキーを送信
  void sendBackspace() {
    _inputController.add(const TerminalInputEvent(
      data: '\x7f',
      isSpecialKey: true,
    ));
  }

  /// Deleteキーを送信
  void sendDelete() {
    _inputController.add(const TerminalInputEvent(
      data: '\x1b[3~',
      isSpecialKey: true,
    ));
  }

  /// 矢印キーを送信
  void sendArrowUp() => _sendArrowKey('A');
  void sendArrowDown() => _sendArrowKey('B');
  void sendArrowRight() => _sendArrowKey('C');
  void sendArrowLeft() => _sendArrowKey('D');

  void _sendArrowKey(String code) {
    String sequence = '\x1b[$code';
    if (_shiftPressed) {
      sequence = '\x1b[1;2$code';
      _shiftPressed = false;
    } else if (_ctrlPressed) {
      sequence = '\x1b[1;5$code';
      _ctrlPressed = false;
    } else if (_altPressed) {
      sequence = '\x1b[1;3$code';
      _altPressed = false;
    }
    _inputController.add(TerminalInputEvent(
      data: sequence,
      isSpecialKey: true,
    ));
  }

  /// Home キーを送信
  void sendHome() {
    _inputController.add(const TerminalInputEvent(
      data: '\x1b[H',
      isSpecialKey: true,
    ));
  }

  /// End キーを送信
  void sendEnd() {
    _inputController.add(const TerminalInputEvent(
      data: '\x1b[F',
      isSpecialKey: true,
    ));
  }

  /// Page Up キーを送信
  void sendPageUp() {
    _inputController.add(const TerminalInputEvent(
      data: '\x1b[5~',
      isSpecialKey: true,
    ));
  }

  /// Page Down キーを送信
  void sendPageDown() {
    _inputController.add(const TerminalInputEvent(
      data: '\x1b[6~',
      isSpecialKey: true,
    ));
  }

  /// ファンクションキーを送信
  void sendFunctionKey(int n) {
    if (n < 1 || n > 12) return;

    final codes = [
      '\x1bOP',   // F1
      '\x1bOQ',   // F2
      '\x1bOR',   // F3
      '\x1bOS',   // F4
      '\x1b[15~', // F5
      '\x1b[17~', // F6
      '\x1b[18~', // F7
      '\x1b[19~', // F8
      '\x1b[20~', // F9
      '\x1b[21~', // F10
      '\x1b[23~', // F11
      '\x1b[24~', // F12
    ];

    _inputController.add(TerminalInputEvent(
      data: codes[n - 1],
      isSpecialKey: true,
    ));
  }

  /// Ctrl+C を送信（SIGINT）
  void sendInterrupt() {
    _inputController.add(const TerminalInputEvent(
      data: '\x03',
      isSpecialKey: true,
    ));
  }

  /// Ctrl+D を送信（EOF）
  void sendEof() {
    _inputController.add(const TerminalInputEvent(
      data: '\x04',
      isSpecialKey: true,
    ));
  }

  /// Ctrl+Z を送信（SIGTSTP）
  void sendSuspend() {
    _inputController.add(const TerminalInputEvent(
      data: '\x1a',
      isSpecialKey: true,
    ));
  }

  /// Ctrl+L を送信（画面クリア）
  void sendClearScreen() {
    _inputController.add(const TerminalInputEvent(
      data: '\x0c',
      isSpecialKey: true,
    ));
  }

  // ===== 修飾キー =====

  /// Ctrl キーをトグル
  void toggleCtrl() {
    _ctrlPressed = !_ctrlPressed;
    HapticFeedback.selectionClick();
  }

  /// Alt キーをトグル
  void toggleAlt() {
    _altPressed = !_altPressed;
    HapticFeedback.selectionClick();
  }

  /// Shift キーをトグル
  void toggleShift() {
    _shiftPressed = !_shiftPressed;
    HapticFeedback.selectionClick();
  }

  /// すべての修飾キーをリセット
  void resetModifiers() {
    _ctrlPressed = false;
    _altPressed = false;
    _shiftPressed = false;
  }

  // ===== ターミナル操作 =====

  /// ターミナルをクリア
  void clear() {
    terminal.write('\x1b[2J\x1b[H');
  }

  /// ソフトリセット
  void softReset() {
    terminal.write('\x1b[!p');
  }

  /// 選択テキストを取得
  String? getSelectedText() {
    final selection = controller.selection;
    if (selection == null) return null;

    final buffer = terminal.buffer;
    final lines = <String>[];

    for (int y = selection.begin.y; y <= selection.end.y; y++) {
      if (y < 0 || y >= buffer.lines.length) continue;

      final line = buffer.lines[y];
      final startX = (y == selection.begin.y) ? selection.begin.x : 0;
      final endX = (y == selection.end.y) ? selection.end.x : line.length;

      final lineText = StringBuffer();
      for (int x = startX; x < endX && x < line.length; x++) {
        final codePoint = line.getCodePoint(x);
        if (codePoint > 0) {
          lineText.writeCharCode(codePoint);
        }
      }
      lines.add(lineText.toString());
    }

    return lines.join('\n');
  }

  /// 選択をクリア
  void clearSelection() {
    controller.clearSelection();
  }

  /// テキストをペースト
  void paste(String text) {
    // ブラケットペーストモードが有効な場合
    if (terminal.bracketedPasteMode) {
      _inputController.add(TerminalInputEvent(
        data: '\x1b[200~$text\x1b[201~',
      ));
    } else {
      _inputController.add(TerminalInputEvent(data: text));
    }
  }

  // ===== テーマ =====

  /// ダークテーマを取得
  static TerminalTheme get darkTheme => TerminalTheme(
        cursor: const Color(0xFFFFFFFF),
        selection: const Color(0x80FFFFFF),
        foreground: const Color(0xFFD4D4D4),
        background: const Color(0xFF1E1E1E),
        black: const Color(0xFF000000),
        red: const Color(0xFFCD3131),
        green: const Color(0xFF0DBC79),
        yellow: const Color(0xFFE5E510),
        blue: const Color(0xFF2472C8),
        magenta: const Color(0xFFBC3FBC),
        cyan: const Color(0xFF11A8CD),
        white: const Color(0xFFE5E5E5),
        brightBlack: const Color(0xFF666666),
        brightRed: const Color(0xFFF14C4C),
        brightGreen: const Color(0xFF23D18B),
        brightYellow: const Color(0xFFF5F543),
        brightBlue: const Color(0xFF3B8EEA),
        brightMagenta: const Color(0xFFD670D6),
        brightCyan: const Color(0xFF29B8DB),
        brightWhite: const Color(0xFFFFFFFF),
        searchHitBackground: const Color(0xFFFFE300),
        searchHitBackgroundCurrent: const Color(0xFFFF6D00),
        searchHitForeground: const Color(0xFF000000),
      );

  /// ライトテーマを取得
  static TerminalTheme get lightTheme => TerminalTheme(
        cursor: const Color(0xFF000000),
        selection: const Color(0x40000000),
        foreground: const Color(0xFF333333),
        background: const Color(0xFFFAFAFA),
        black: const Color(0xFF000000),
        red: const Color(0xFFCD3131),
        green: const Color(0xFF00BC00),
        yellow: const Color(0xFFA5A500),
        blue: const Color(0xFF0451A5),
        magenta: const Color(0xFFBC05BC),
        cyan: const Color(0xFF0598BC),
        white: const Color(0xFF555555),
        brightBlack: const Color(0xFF666666),
        brightRed: const Color(0xFFCD3131),
        brightGreen: const Color(0xFF14CE14),
        brightYellow: const Color(0xFFB5BA00),
        brightBlue: const Color(0xFF0451A5),
        brightMagenta: const Color(0xFFBC05BC),
        brightCyan: const Color(0xFF0598BC),
        brightWhite: const Color(0xFFA5A5A5),
        searchHitBackground: const Color(0xFFFFE300),
        searchHitBackgroundCurrent: const Color(0xFFFF6D00),
        searchHitForeground: const Color(0xFF000000),
      );

  /// テキストスタイルを取得
  TerminalStyle get textStyle => TerminalStyle(
        fontSize: config.fontSize,
        fontFamily: config.fontFamily,
      );

  // ===== リソース解放 =====

  /// リソースを解放
  void dispose() {
    _inputController.close();
    _resizeController.close();
    _bellController.close();
    _titleController.close();
    controller.dispose();
  }
}

/// ファクトリ関数
MuxTerminalController createTerminalController({
  TerminalConfig config = const TerminalConfig(),
}) {
  return MuxTerminalController(config: config);
}
