import 'package:flutter/material.dart';

import 'ansi_models.dart';

/// SGR (Select Graphic Rendition) パラメータ解釈器
///
/// ANSIエスケープシーケンスのSGRパラメータ文字列を解釈して [AnsiStyle] を
/// 更新する。標準8色・明るい8色・256色パレットを保持する。
class AnsiSgrParser {
  /// 標準8色（通常）
  static const List<Color> standardColors = [
    Color(0xFF000000), // 0: Black
    Color(0xFFCD3131), // 1: Red
    Color(0xFF0DBC79), // 2: Green
    Color(0xFFE5E510), // 3: Yellow
    Color(0xFF2472C8), // 4: Blue
    Color(0xFFBC3FBC), // 5: Magenta
    Color(0xFF11A8CD), // 6: Cyan
    Color(0xFFE5E5E5), // 7: White
  ];

  /// 標準8色（明るい）
  static const List<Color> brightColors = [
    Color(0xFF666666), // 8: Bright Black
    Color(0xFFF14C4C), // 9: Bright Red
    Color(0xFF23D18B), // 10: Bright Green
    Color(0xFFF5F543), // 11: Bright Yellow
    Color(0xFF3B8EAE), // 12: Bright Blue
    Color(0xFFD670D6), // 13: Bright Magenta
    Color(0xFF29B8DB), // 14: Bright Cyan
    Color(0xFFFFFFFF), // 15: Bright White
  ];

  /// デフォルトの前景色（256色パレットの範囲外フォールバック）
  final Color defaultForeground;

  /// デフォルトの背景色
  final Color defaultBackground;

  AnsiSgrParser({
    this.defaultForeground = const Color(0xFFD4D4D4),
    this.defaultBackground = const Color(0xFF1E1E1E),
  });

  /// SGRパラメータを解析してスタイルを更新
  AnsiStyle apply(String params, AnsiStyle current) {
    if (params.isEmpty) {
      return AnsiStyle.defaultStyle;
    }

    final codes = params.split(';').map((s) => int.tryParse(s) ?? 0).toList();
    var style = current;
    var i = 0;

    while (i < codes.length) {
      final code = codes[i];

      switch (code) {
        case 0: // リセット
          style = AnsiStyle.defaultStyle;
          break;
        case 1: // 太字
          style = style.copyWith(bold: true);
          break;
        case 2: // 薄暗い
          style = style.copyWith(dim: true);
          break;
        case 3: // イタリック
          style = style.copyWith(italic: true);
          break;
        case 4: // 下線
          style = style.copyWith(underline: true);
          break;
        case 7: // 反転
          style = style.copyWith(inverse: true);
          break;
        case 9: // 取り消し線
          style = style.copyWith(strikethrough: true);
          break;
        case 21: // 太字解除 (一部の端末)
        case 22: // 太字・薄暗さ解除
          style = style.copyWith(bold: false, dim: false);
          break;
        case 23: // イタリック解除
          style = style.copyWith(italic: false);
          break;
        case 24: // 下線解除
          style = style.copyWith(underline: false);
          break;
        case 27: // 反転解除
          style = style.copyWith(inverse: false);
          break;
        case 29: // 取り消し線解除
          style = style.copyWith(strikethrough: false);
          break;
        case 30:
        case 31:
        case 32:
        case 33:
        case 34:
        case 35:
        case 36:
        case 37:
          // 標準前景色 (30-37)
          style = style.copyWith(foreground: standardColors[code - 30]);
          break;
        case 38:
          // 拡張前景色
          if (i + 1 < codes.length) {
            if (codes[i + 1] == 5 && i + 2 < codes.length) {
              // 256色モード: 38;5;n
              style = style.copyWith(foreground: _get256Color(codes[i + 2]));
              i += 2;
            } else if (codes[i + 1] == 2 && i + 4 < codes.length) {
              // 24ビットカラー: 38;2;r;g;b
              style = style.copyWith(
                foreground: Color.fromARGB(
                  255,
                  codes[i + 2].clamp(0, 255),
                  codes[i + 3].clamp(0, 255),
                  codes[i + 4].clamp(0, 255),
                ),
              );
              i += 4;
            }
          }
          break;
        case 39: // デフォルト前景色
          style = style.copyWith(clearForeground: true);
          break;
        case 40:
        case 41:
        case 42:
        case 43:
        case 44:
        case 45:
        case 46:
        case 47:
          // 標準背景色 (40-47)
          style = style.copyWith(background: standardColors[code - 40]);
          break;
        case 48:
          // 拡張背景色
          if (i + 1 < codes.length) {
            if (codes[i + 1] == 5 && i + 2 < codes.length) {
              // 256色モード: 48;5;n
              style = style.copyWith(background: _get256Color(codes[i + 2]));
              i += 2;
            } else if (codes[i + 1] == 2 && i + 4 < codes.length) {
              // 24ビットカラー: 48;2;r;g;b
              style = style.copyWith(
                background: Color.fromARGB(
                  255,
                  codes[i + 2].clamp(0, 255),
                  codes[i + 3].clamp(0, 255),
                  codes[i + 4].clamp(0, 255),
                ),
              );
              i += 4;
            }
          }
          break;
        case 49: // デフォルト背景色
          style = style.copyWith(clearBackground: true);
          break;
        case 90:
        case 91:
        case 92:
        case 93:
        case 94:
        case 95:
        case 96:
        case 97:
          // 明るい前景色 (90-97)
          style = style.copyWith(foreground: brightColors[code - 90]);
          break;
        case 100:
        case 101:
        case 102:
        case 103:
        case 104:
        case 105:
        case 106:
        case 107:
          // 明るい背景色 (100-107)
          style = style.copyWith(background: brightColors[code - 100]);
          break;
      }
      i++;
    }

    return style;
  }

  /// 256色パレットから色を取得
  Color _get256Color(int index) {
    if (index < 0 || index > 255) {
      return defaultForeground;
    }

    // 0-7: 標準色
    if (index < 8) {
      return standardColors[index];
    }

    // 8-15: 明るい色
    if (index < 16) {
      return brightColors[index - 8];
    }

    // 16-231: 6x6x6 カラーキューブ
    if (index < 232) {
      final n = index - 16;
      final r = (n ~/ 36) % 6;
      final g = (n ~/ 6) % 6;
      final b = n % 6;
      return Color.fromARGB(
        255,
        r > 0 ? (r * 40 + 55) : 0,
        g > 0 ? (g * 40 + 55) : 0,
        b > 0 ? (b * 40 + 55) : 0,
      );
    }

    // 232-255: グレースケール
    final gray = (index - 232) * 10 + 8;
    return Color.fromARGB(255, gray, gray, gray);
  }
}
