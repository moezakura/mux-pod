import 'package:flutter/material.dart';

/// ターミナル用カラー定義
class TerminalColors {
  TerminalColors._();

  // === ANSI 標準16色 ===

  static const Color black = Color(0xFF000000);
  static const Color red = Color(0xFFCD0000);
  static const Color green = Color(0xFF00CD00);
  static const Color yellow = Color(0xFFCDCD00);
  static const Color blue = Color(0xFF0000EE);
  static const Color magenta = Color(0xFFCD00CD);
  static const Color cyan = Color(0xFF00CDCD);
  static const Color white = Color(0xFFE5E5E5);

  // Bright variants
  static const Color brightBlack = Color(0xFF7F7F7F);
  static const Color brightRed = Color(0xFFFF0000);
  static const Color brightGreen = Color(0xFF00FF00);
  static const Color brightYellow = Color(0xFFFFFF00);
  static const Color brightBlue = Color(0xFF5C5CFF);
  static const Color brightMagenta = Color(0xFFFF00FF);
  static const Color brightCyan = Color(0xFF00FFFF);
  static const Color brightWhite = Color(0xFFFFFFFF);

  /// 標準16色のリスト
  static const List<Color> ansi16 = [
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    brightBlack,
    brightRed,
    brightGreen,
    brightYellow,
    brightBlue,
    brightMagenta,
    brightCyan,
    brightWhite,
  ];

  // === ターミナルテーマ ===

  /// デフォルトダークテーマ
  static const TerminalTheme darkTheme = TerminalTheme(
    foreground: Color(0xFFD4D4D4),
    background: Color(0xFF1E1E1E),
    cursor: Color(0xFFFFFFFF),
    cursorText: Color(0xFF000000),
    selection: Color(0x40FFFFFF),
  );

  /// デフォルトライトテーマ
  static const TerminalTheme lightTheme = TerminalTheme(
    foreground: Color(0xFF333333),
    background: Color(0xFFFAFAFA),
    cursor: Color(0xFF000000),
    cursorText: Color(0xFFFFFFFF),
    selection: Color(0x40000000),
  );

  /// Monokai テーマ
  static const TerminalTheme monokaiTheme = TerminalTheme(
    foreground: Color(0xFFF8F8F2),
    background: Color(0xFF272822),
    cursor: Color(0xFFF8F8F0),
    cursorText: Color(0xFF272822),
    selection: Color(0x4049483E),
  );

  /// Dracula テーマ
  static const TerminalTheme draculaTheme = TerminalTheme(
    foreground: Color(0xFFF8F8F2),
    background: Color(0xFF282A36),
    cursor: Color(0xFFF8F8F2),
    cursorText: Color(0xFF282A36),
    selection: Color(0x4044475A),
  );

  /// 256色パレットを生成
  static List<Color> generate256Palette() {
    final colors = <Color>[];

    // 0-15: 標準16色
    colors.addAll(ansi16);

    // 16-231: 6x6x6 カラーキューブ
    for (int r = 0; r < 6; r++) {
      for (int g = 0; g < 6; g++) {
        for (int b = 0; b < 6; b++) {
          final red = r > 0 ? 55 + r * 40 : 0;
          final green = g > 0 ? 55 + g * 40 : 0;
          final blue = b > 0 ? 55 + b * 40 : 0;
          colors.add(Color.fromARGB(255, red, green, blue));
        }
      }
    }

    // 232-255: グレースケール
    for (int i = 0; i < 24; i++) {
      final gray = 8 + i * 10;
      colors.add(Color.fromARGB(255, gray, gray, gray));
    }

    return colors;
  }
}

/// ターミナルテーマ
class TerminalTheme {
  final Color foreground;
  final Color background;
  final Color cursor;
  final Color cursorText;
  final Color selection;

  const TerminalTheme({
    required this.foreground,
    required this.background,
    required this.cursor,
    required this.cursorText,
    required this.selection,
  });
}
