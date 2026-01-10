import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'terminal_colors.freezed.dart';
part 'terminal_colors.g.dart';

/// ターミナルカラー定義
@freezed
class TerminalColors with _$TerminalColors {
  const factory TerminalColors({
    required String background,
    required String foreground,
    required String cursor,
    required String selection,
    required String black,
    required String red,
    required String green,
    required String yellow,
    required String blue,
    required String magenta,
    required String cyan,
    required String white,
    required String brightBlack,
    required String brightRed,
    required String brightGreen,
    required String brightYellow,
    required String brightBlue,
    required String brightMagenta,
    required String brightCyan,
    required String brightWhite,
  }) = _TerminalColors;

  factory TerminalColors.fromJson(Map<String, dynamic> json) =>
      _$TerminalColorsFromJson(json);
}

/// プリセットカラーテーマ
abstract class TerminalColorPresets {
  /// Dracula テーマ
  static const TerminalColors dracula = TerminalColors(
    background: '#282a36',
    foreground: '#f8f8f2',
    cursor: '#f8f8f2',
    selection: '#44475a',
    black: '#21222c',
    red: '#ff5555',
    green: '#50fa7b',
    yellow: '#f1fa8c',
    blue: '#bd93f9',
    magenta: '#ff79c6',
    cyan: '#8be9fd',
    white: '#f8f8f2',
    brightBlack: '#6272a4',
    brightRed: '#ff6e6e',
    brightGreen: '#69ff94',
    brightYellow: '#ffffa5',
    brightBlue: '#d6acff',
    brightMagenta: '#ff92df',
    brightCyan: '#a4ffff',
    brightWhite: '#ffffff',
  );

  /// Solarized Dark テーマ
  static const TerminalColors solarizedDark = TerminalColors(
    background: '#002b36',
    foreground: '#839496',
    cursor: '#839496',
    selection: '#073642',
    black: '#073642',
    red: '#dc322f',
    green: '#859900',
    yellow: '#b58900',
    blue: '#268bd2',
    magenta: '#d33682',
    cyan: '#2aa198',
    white: '#eee8d5',
    brightBlack: '#002b36',
    brightRed: '#cb4b16',
    brightGreen: '#586e75',
    brightYellow: '#657b83',
    brightBlue: '#839496',
    brightMagenta: '#6c71c4',
    brightCyan: '#93a1a1',
    brightWhite: '#fdf6e3',
  );

  /// Monokai テーマ
  static const TerminalColors monokai = TerminalColors(
    background: '#272822',
    foreground: '#f8f8f2',
    cursor: '#f8f8f2',
    selection: '#49483e',
    black: '#272822',
    red: '#f92672',
    green: '#a6e22e',
    yellow: '#f4bf75',
    blue: '#66d9ef',
    magenta: '#ae81ff',
    cyan: '#a1efe4',
    white: '#f8f8f2',
    brightBlack: '#75715e',
    brightRed: '#f92672',
    brightGreen: '#a6e22e',
    brightYellow: '#f4bf75',
    brightBlue: '#66d9ef',
    brightMagenta: '#ae81ff',
    brightCyan: '#a1efe4',
    brightWhite: '#f9f8f5',
  );

  /// Nord テーマ
  static const TerminalColors nord = TerminalColors(
    background: '#2e3440',
    foreground: '#d8dee9',
    cursor: '#d8dee9',
    selection: '#434c5e',
    black: '#3b4252',
    red: '#bf616a',
    green: '#a3be8c',
    yellow: '#ebcb8b',
    blue: '#81a1c1',
    magenta: '#b48ead',
    cyan: '#88c0d0',
    white: '#e5e9f0',
    brightBlack: '#4c566a',
    brightRed: '#bf616a',
    brightGreen: '#a3be8c',
    brightYellow: '#ebcb8b',
    brightBlue: '#81a1c1',
    brightMagenta: '#b48ead',
    brightCyan: '#8fbcbb',
    brightWhite: '#eceff4',
  );
}

/// Hex文字列をColorに変換
Color hexToColor(String hex) {
  final buffer = StringBuffer();
  if (hex.length == 6 || hex.length == 7) {
    buffer.write('ff');
  }
  buffer.write(hex.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}
