import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

/// ターミナル用等幅フォントスタイル
///
/// Google Fontsの等幅フォントおよびバンドルされた日本語対応フォントを
/// 統一的に取得する。
class TerminalFontStyles {
  TerminalFontStyles._();

  /// バンドルフォント（日本語対応）のファミリー名
  static const List<String> _bundledFontFamilies = [
    'HackGen Console',
    'UDEV Gothic NF',
  ];

  /// フォントフォールバック（特殊記号・絵文字用）
  /// Nerd Fontsや記号をサポートするフォントにフォールバック
  static const List<String> _fontFamilyFallback = [
    'Noto Sans Symbols 2',
    'Noto Color Emoji',
    'Symbols Nerd Font',
    'Noto Sans Symbols',
  ];

  /// サポートするフォントファミリーのリスト
  static const List<String> supportedFontFamilies = [
    'JetBrains Mono',
    'Fira Code',
    'Source Code Pro',
    'Roboto Mono',
    'Ubuntu Mono',
    'Inconsolata',
    'HackGen Console',
    'UDEV Gothic NF',
  ];

  /// デフォルトのフォントファミリー
  static const String defaultFontFamily = 'JetBrains Mono';

  /// 表示名からバンドルフォント名へのマッピング
  static const Map<String, String> _bundledFontMap = {
    'HackGen Console': 'HackGenConsole',
    'UDEV Gothic NF': 'UDEVGothicNF',
  };

  /// フォントファミリー名からTextStyleを取得
  ///
  /// [fontFamily] フォントファミリー名
  /// [fontSize] フォントサイズ
  /// [height] 行の高さ比率
  /// [color] 文字色
  /// [backgroundColor] 背景色
  /// [fontWeight] フォントウェイト
  /// [fontStyle] フォントスタイル（イタリック等）
  /// [decoration] テキスト装飾（下線、取り消し線等）
  static TextStyle getTextStyle(
    String fontFamily, {
    double? fontSize,
    double? height,
    Color? color,
    Color? backgroundColor,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    TextDecoration? decoration,
  }) {
    // バンドルフォント（日本語対応）の場合
    if (_bundledFontFamilies.contains(fontFamily)) {
      return TextStyle(
        inherit: false, // スタイル継承を無効化してメトリクスを安定させる
        fontFamily: _bundledFontMap[fontFamily],
        fontFamilyFallback: _fontFamilyFallback,
        fontSize: fontSize,
        height: height,
        color: color,
        backgroundColor: backgroundColor,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        decoration: decoration,
      );
    }

    // Google Fontsの場合
    TextStyle baseStyle;
    switch (fontFamily) {
      case 'JetBrains Mono':
        baseStyle = GoogleFonts.jetBrainsMono(
          // GoogleFontsはinherit引数を直接持たない場合があるため、copyWithで適用するか、
          // textStyleを受け取るパラメータを確認する必要があるが、
          // GoogleFonts.x()はTextStyleを返すので、後でcopyWith(inherit: false)する
          fontSize: fontSize,
          height: height,
          color: color,
          backgroundColor: backgroundColor,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          decoration: decoration,
        );
        break;
      case 'Fira Code':
        baseStyle = GoogleFonts.firaCode(
          fontSize: fontSize,
          height: height,
          color: color,
          backgroundColor: backgroundColor,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          decoration: decoration,
        );
        break;
      case 'Source Code Pro':
        baseStyle = GoogleFonts.sourceCodePro(
          fontSize: fontSize,
          height: height,
          color: color,
          backgroundColor: backgroundColor,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          decoration: decoration,
        );
        break;
      case 'Roboto Mono':
        baseStyle = GoogleFonts.robotoMono(
          fontSize: fontSize,
          height: height,
          color: color,
          backgroundColor: backgroundColor,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          decoration: decoration,
        );
        break;
      case 'Ubuntu Mono':
        baseStyle = GoogleFonts.ubuntuMono(
          fontSize: fontSize,
          height: height,
          color: color,
          backgroundColor: backgroundColor,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          decoration: decoration,
        );
        break;
      case 'Inconsolata':
        baseStyle = GoogleFonts.inconsolata(
          fontSize: fontSize,
          height: height,
          color: color,
          backgroundColor: backgroundColor,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          decoration: decoration,
        );
        break;
      default:
        // デフォルトはJetBrains Mono
        baseStyle = GoogleFonts.jetBrainsMono(
          fontSize: fontSize,
          height: height,
          color: color,
          backgroundColor: backgroundColor,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          decoration: decoration,
        );
    }

    // フォントフォールバックを追加し、継承を無効化
    return baseStyle.copyWith(
      fontFamilyFallback: _fontFamilyFallback,
      inherit: false,
    );
  }
}
