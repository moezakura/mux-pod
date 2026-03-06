import 'dart:developer' as developer;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'terminal_font_styles.dart';

/// フォントサイズ計算結果
typedef FontCalculateResult = ({double fontSize, bool needsScroll});

/// ターミナルフォントサイズ計算サービス
///
/// ペインの文字幅と画面幅から最適なフォントサイズを計算する。
class FontCalculator {
  /// デフォルトのフォントサイズ
  static const double defaultFontSize = 14.0;

  /// 文字幅比率のキャッシュ（フォントファミリー → 比率）
  static final Map<String, double> _charWidthRatioCache = {};

  /// デフォルトのペイン幅（文字数）
  static const int defaultPaneWidth = 80;

  /// 最小ペイン幅（文字数）- これより狭いペインはこの値にクランプ
  static const int minPaneWidth = 10;

  /// 画面幅とペイン文字数からフォントサイズを計算
  ///
  /// [screenWidth] 利用可能なスクリーン幅（ピクセル）
  /// [paneCharWidth] ペインの横幅（文字数）
  /// [fontFamily] フォントファミリー
  /// [minFontSize] 最小フォントサイズ（下限）
  ///
  /// Returns: (fontSize, needsScroll) のRecord
  static FontCalculateResult calculate({
    required double screenWidth,
    required int paneCharWidth,
    required String fontFamily,
    required double minFontSize,
  }) {
    // T031: ペイン幅が0以下の場合はデフォルト80にフォールバック
    int effectivePaneWidth = paneCharWidth;
    if (paneCharWidth <= 0) {
      developer.log(
        'Invalid pane width ($paneCharWidth), using default: $defaultPaneWidth',
        name: 'FontCalculator',
      );
      effectivePaneWidth = defaultPaneWidth;
    }
    // T032: 極端に狭いペイン（10文字未満）は最小値にクランプ
    else if (paneCharWidth < minPaneWidth) {
      developer.log(
        'Narrow pane ($paneCharWidth chars), clamping to minimum: $minPaneWidth',
        name: 'FontCalculator',
      );
      effectivePaneWidth = minPaneWidth;
    }

    // 無効なスクリーン幅の場合はデフォルト値を返す
    if (screenWidth <= 0) {
      developer.log(
        'Invalid screen width ($screenWidth), returning default font size',
        name: 'FontCalculator',
      );
      return (fontSize: defaultFontSize, needsScroll: false);
    }

    // 文字幅比率を測定
    final charWidthRatio = measureCharWidthRatio(fontFamily);

    // 計算: fontSize = screenWidth / (paneWidth × charWidthRatio)
    final calculatedSize = screenWidth / (effectivePaneWidth * charWidthRatio);

    final FontCalculateResult result;
    if (calculatedSize >= minFontSize) {
      result = (fontSize: calculatedSize, needsScroll: false);
    } else {
      // 最小フォントサイズを下回る場合は水平スクロールが必要
      result = (fontSize: minFontSize, needsScroll: true);
    }

    // T034: フォントサイズ計算結果をログ出力
    developer.log(
      'Calculated: screen=${screenWidth.toStringAsFixed(1)}px, '
      'pane=${effectivePaneWidth}chars, '
      'fontSize=${result.fontSize.toStringAsFixed(2)}pt, '
      'scroll=${result.needsScroll}',
      name: 'FontCalculator',
    );

    return result;
  }

  /// フォントファミリーの文字幅比率を測定（キャッシュ使用）
  ///
  /// 等幅フォントでは、1文字の幅 = fontSize × charWidthRatio
  /// 基準フォントサイズ100で測定し、比率を返す。
  /// 精度向上のため、10文字分の幅を測定して平均を取る。
  static double measureCharWidthRatio(String fontFamily) {
    // キャッシュから取得
    if (_charWidthRatioCache.containsKey(fontFamily)) {
      return _charWidthRatioCache[fontFamily]!;
    }

    const baseFontSize = 100.0;
    // 等幅フォントでも数字とアルファベットで微妙にメトリクスが異なる場合があるため、
    // 典型的なパターンを含めて平均を取る
    const testString = '0123456789';

    final painter = TextPainter(
      text: TextSpan(
        text: testString,
        style: TerminalFontStyles.getTextStyle(fontFamily, fontSize: baseFontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // 平均幅を算出
    // 0.8文字分左にずれる（charWidthが小さい）という報告があるため、
    // 計算結果が小さくなりすぎないよう、ごくわずかなバッファ(0.01%)を持たせるか検討したが、
    // そもそも 'M' (幅広) だけでなく '0' (標準的) も含めることで自然に補正されることを期待。
    // それでも足りない場合はオフセット調整が必要だが、まずは測定文字種の変更で対応。
    final ratio = (painter.width / testString.length) / baseFontSize;

    // キャッシュに保存
    _charWidthRatioCache[fontFamily] = ratio;

    developer.log(
      'Cached char width ratio for "$fontFamily": $ratio',
      name: 'FontCalculator',
    );

    return ratio;
  }

  /// キャッシュをクリア（テスト用またはフォント変更時）
  static void clearCache() {
    _charWidthRatioCache.clear();
  }

  /// テスト用: キャッシュに比率を設定（google_fontsの非同期フォント取得を回避）
  @visibleForTesting
  static void setCachedRatio(String fontFamily, double ratio) {
    _charWidthRatioCache[fontFamily] = ratio;
  }

  /// ターミナルの表示幅（ピクセル）を計算
  ///
  /// 水平スクロールコンテナのサイズ計算に使用。
  static double calculateTerminalWidth({
    required int paneCharWidth,
    required double fontSize,
    required String fontFamily,
  }) {
    final charWidthRatio = measureCharWidthRatio(fontFamily);
    return paneCharWidth * charWidthRatio * fontSize;
  }

  /// 指定されたフォントサイズでの正確な文字幅を測定
  ///
  /// ヒンティングやピクセルアライメントによる非線形なスケーリングを考慮し、
  /// 実際に使用するフォントサイズで測定を行う。
  static double measureCharWidth(String fontFamily, double fontSize) {
    const testString = '0123456789';
    final painter = TextPainter(
      text: TextSpan(
        text: testString,
        style: TerminalFontStyles.getTextStyle(fontFamily, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    return painter.width / testString.length;
  }

  /// ターミナルのカラム位置（cursorX）をコードユニットオフセットに変換
  ///
  /// 全角文字（日本語、中国語、韓国語など）は2カラム分の幅を占めるため、
  /// tmuxのcursor_x（カラム位置）と文字数は異なる。
  /// この関数はカラム位置から正しいコードユニットオフセットを計算する。
  ///
  /// 絵文字の異体字セレクタ（VS16など）も考慮し、グラフィームクラスター
  /// 単位での正確な変換を行う。
  ///
  /// 注意: BMP外の文字（絵文字等）はサロゲートペアとして2コードユニットを
  /// 使用するため、runeカウントではなくコードユニットカウントを返す。
  ///
  /// [text] 対象のテキスト
  /// [columnPosition] ターミナルのカラム位置（0-based）
  ///
  /// Returns: コードユニットオフセット（TextPositionに渡す値）
  static int columnToCharOffset(String text, int columnPosition) {
    int currentColumn = 0;
    int codeUnitOffset = 0;
    final runes = text.runes.toList();

    int i = 0;
    while (i < runes.length) {
      if (currentColumn >= columnPosition) {
        break;
      }

      final rune = runes[i];
      // 次のコードポイントを先読み（VS16チェック用）
      final nextRune = (i + 1 < runes.length) ? runes[i + 1] : null;

      final charWidth = getCharDisplayWidthWithContext(rune, nextRune);
      currentColumn += charWidth;
      // BMP外の文字（U+10000以上）は2コードユニット、それ以外は1コードユニット
      codeUnitOffset += _runeCodeUnitCount(rune);
      i++;
    }

    // 続く幅0の文字（VS16、結合文字など）をスキップ
    // これらは前の文字と一緒に描画されるため、TextPositionとしては
    // これらの後を指す必要がある
    while (i < runes.length) {
      final rune = runes[i];
      final nextRune = (i + 1 < runes.length) ? runes[i + 1] : null;
      if (getCharDisplayWidthWithContext(rune, nextRune) > 0) {
        break;
      }
      codeUnitOffset += _runeCodeUnitCount(rune);
      i++;
    }

    return codeUnitOffset;
  }

  /// runeのコードユニット数を取得
  ///
  /// BMP（Basic Multilingual Plane、U+0000〜U+FFFF）内の文字は1コードユニット、
  /// BMP外の文字（U+10000以上、絵文字など）は2コードユニット（サロゲートペア）。
  static int _runeCodeUnitCount(int rune) {
    return rune > 0xFFFF ? 2 : 1;
  }

  /// 文字のターミナル表示幅を取得（コンテキスト付き）
  ///
  /// 次のコードポイントがVS16（U+FE0F）の場合、絵文字スタイルとして
  /// 幅2を返す。
  static int getCharDisplayWidthWithContext(int codePoint, int? nextCodePoint) {
    // 幅0の文字（結合文字、異体字セレクタなど）
    if (_isZeroWidthChar(codePoint)) {
      return 0;
    }

    // 次がVS16（絵文字スタイル）の場合、多くの文字が幅2になる
    if (nextCodePoint == 0xFE0F) {
      // 既に幅2の文字はそのまま
      final baseWidth = getCharDisplayWidth(codePoint);
      if (baseWidth == 2) return 2;
      // VS16付きで絵文字表示になる文字は幅2
      if (_canBeEmoji(codePoint)) return 2;
    }

    return getCharDisplayWidth(codePoint);
  }

  /// 幅0の文字かどうか判定
  static bool _isZeroWidthChar(int codePoint) {
    // 制御文字
    if (codePoint < 0x20) return true;
    if (codePoint >= 0x7F && codePoint < 0xA0) return true;

    // 異体字セレクタ（Variation Selectors）
    if (codePoint >= 0xFE00 && codePoint <= 0xFE0F) return true;
    // 異体字セレクタ補助（Variation Selectors Supplement）
    if (codePoint >= 0xE0100 && codePoint <= 0xE01EF) return true;

    // Zero Width Joiner / Non-Joiner
    if (codePoint == 0x200D || codePoint == 0x200C) return true;
    // Zero Width Space
    if (codePoint == 0x200B) return true;
    // Word Joiner
    if (codePoint == 0x2060) return true;

    // 結合文字（Combining Diacritical Marks）
    if (codePoint >= 0x0300 && codePoint <= 0x036F) return true;
    // 結合文字拡張
    if (codePoint >= 0x1AB0 && codePoint <= 0x1AFF) return true;
    if (codePoint >= 0x1DC0 && codePoint <= 0x1DFF) return true;
    if (codePoint >= 0x20D0 && codePoint <= 0x20FF) return true;
    if (codePoint >= 0xFE20 && codePoint <= 0xFE2F) return true;

    // Regional Indicator の肌色修飾子
    if (codePoint >= 0x1F3FB && codePoint <= 0x1F3FF) return true;

    return false;
  }

  /// VS16付きで絵文字表示になりうる文字か判定
  static bool _canBeEmoji(int codePoint) {
    // Miscellaneous Symbols
    if (codePoint >= 0x2600 && codePoint <= 0x26FF) return true;
    // Dingbats
    if (codePoint >= 0x2700 && codePoint <= 0x27BF) return true;
    // Miscellaneous Symbols and Pictographs
    if (codePoint >= 0x1F300 && codePoint <= 0x1F5FF) return true;
    // Emoticons
    if (codePoint >= 0x1F600 && codePoint <= 0x1F64F) return true;
    // Transport and Map Symbols
    if (codePoint >= 0x1F680 && codePoint <= 0x1F6FF) return true;
    // Supplemental Symbols and Pictographs
    if (codePoint >= 0x1F900 && codePoint <= 0x1F9FF) return true;
    // Symbols and Pictographs Extended-A
    if (codePoint >= 0x1FA00 && codePoint <= 0x1FA6F) return true;
    // Symbols and Pictographs Extended-B
    if (codePoint >= 0x1FA70 && codePoint <= 0x1FAFF) return true;
    // その他の絵文字になりうる記号
    if (codePoint >= 0x2300 && codePoint <= 0x23FF) return true; // Misc Technical
    if (codePoint >= 0x2B50 && codePoint <= 0x2B55) return true; // Stars etc
    // 数字キーキャップ用
    if (codePoint >= 0x0023 && codePoint <= 0x0039) return true; // # 0-9
    // その他のテキスト/絵文字両用記号
    if (codePoint == 0x00A9 || codePoint == 0x00AE) return true; // © ®
    if (codePoint == 0x2122) return true; // ™
    if (codePoint >= 0x2194 && codePoint <= 0x21AA) return true; // Arrows
    if (codePoint >= 0x231A && codePoint <= 0x231B) return true; // Watch, Hourglass
    if (codePoint >= 0x25AA && codePoint <= 0x25AB) return true; // Squares
    if (codePoint >= 0x25B6 && codePoint <= 0x25C0) return true; // Triangles
    if (codePoint >= 0x25FB && codePoint <= 0x25FE) return true; // Squares
    if (codePoint == 0x2614 || codePoint == 0x2615) return true; // Umbrella, Hot Beverage
    if (codePoint >= 0x2648 && codePoint <= 0x2653) return true; // Zodiac
    if (codePoint == 0x267F) return true; // Wheelchair
    if (codePoint == 0x2693) return true; // Anchor
    if (codePoint == 0x26A1) return true; // High Voltage
    if (codePoint >= 0x26AA && codePoint <= 0x26AB) return true; // Circles
    if (codePoint >= 0x26BD && codePoint <= 0x26BE) return true; // Sports
    if (codePoint >= 0x26C4 && codePoint <= 0x26C5) return true; // Weather
    if (codePoint == 0x26CE) return true; // Ophiuchus
    if (codePoint == 0x26D4) return true; // No Entry
    if (codePoint == 0x26EA) return true; // Church
    if (codePoint >= 0x26F2 && codePoint <= 0x26F3) return true; // Fountain, Golf
    if (codePoint == 0x26F5) return true; // Sailboat
    if (codePoint == 0x26FA) return true; // Tent
    if (codePoint == 0x26FD) return true; // Fuel Pump
    if (codePoint >= 0x2702 && codePoint <= 0x2709) return true; // Office items
    if (codePoint >= 0x270A && codePoint <= 0x270D) return true; // Hands
    if (codePoint == 0x270F) return true; // Pencil
    if (codePoint >= 0x2712 && codePoint <= 0x2714) return true; // Writing
    if (codePoint == 0x2716) return true; // X Mark
    if (codePoint >= 0x271D && codePoint <= 0x2721) return true; // Religious symbols
    if (codePoint == 0x2728) return true; // Sparkles
    if (codePoint >= 0x2733 && codePoint <= 0x2734) return true; // Asterisks
    if (codePoint == 0x2744) return true; // Snowflake
    if (codePoint == 0x2747) return true; // Sparkle
    if (codePoint >= 0x274C && codePoint <= 0x274E) return true; // X marks
    if (codePoint >= 0x2753 && codePoint <= 0x2755) return true; // Question marks
    if (codePoint == 0x2757) return true; // Exclamation
    if (codePoint >= 0x2763 && codePoint <= 0x2764) return true; // Hearts
    if (codePoint >= 0x2795 && codePoint <= 0x2797) return true; // Math
    if (codePoint == 0x27A1) return true; // Arrow
    if (codePoint == 0x27B0) return true; // Curly Loop
    if (codePoint == 0x27BF) return true; // Double Curly Loop
    if (codePoint >= 0x2934 && codePoint <= 0x2935) return true; // Arrows
    if (codePoint >= 0x2B05 && codePoint <= 0x2B07) return true; // Arrows
    if (codePoint >= 0x2B1B && codePoint <= 0x2B1C) return true; // Squares
    if (codePoint == 0x3030) return true; // Wavy Dash
    if (codePoint == 0x303D) return true; // Part Alternation Mark
    if (codePoint == 0x3297) return true; // Circled Ideograph Congratulation
    if (codePoint == 0x3299) return true; // Circled Ideograph Secret

    return false;
  }

  /// 文字のターミナル表示幅を取得（0, 1, または 2）
  ///
  /// Unicode East Asian Width プロパティに基づいて、
  /// 全角文字は2、半角文字は1、結合文字等は0を返す。
  static int getCharDisplayWidth(int codePoint) {
    // 幅0の文字
    if (_isZeroWidthChar(codePoint)) {
      return 0;
    }

    // 全角文字の判定（East Asian Width: F, W, A の一部）
    // CJK統合漢字
    if (codePoint >= 0x4E00 && codePoint <= 0x9FFF) return 2;
    // CJK統合漢字拡張A
    if (codePoint >= 0x3400 && codePoint <= 0x4DBF) return 2;
    // CJK統合漢字拡張B-G
    if (codePoint >= 0x20000 && codePoint <= 0x3FFFF) return 2;
    // ひらがな
    if (codePoint >= 0x3040 && codePoint <= 0x309F) return 2;
    // カタカナ
    if (codePoint >= 0x30A0 && codePoint <= 0x30FF) return 2;
    // 半角・全角形（全角部分）
    if (codePoint >= 0xFF01 && codePoint <= 0xFF60) return 2;
    if (codePoint >= 0xFFE0 && codePoint <= 0xFFE6) return 2;
    // 韓国語（ハングル音節）
    if (codePoint >= 0xAC00 && codePoint <= 0xD7AF) return 2;
    // 韓国語（ハングル字母）
    if (codePoint >= 0x1100 && codePoint <= 0x11FF) return 2;
    if (codePoint >= 0x3130 && codePoint <= 0x318F) return 2;
    // CJK記号・句読点
    if (codePoint >= 0x3000 && codePoint <= 0x303F) return 2;
    // CJK互換用文字
    if (codePoint >= 0x3300 && codePoint <= 0x33FF) return 2;
    if (codePoint >= 0xFE30 && codePoint <= 0xFE4F) return 2;
    // 囲み文字
    if (codePoint >= 0x3200 && codePoint <= 0x32FF) return 2;
    // 絵文字（一般的に2幅）
    if (codePoint >= 0x1F300 && codePoint <= 0x1F9FF) return 2;
    if (codePoint >= 0x1FA00 && codePoint <= 0x1FAFF) return 2;

    // その他は半角
    return 1;
  }

  /// テキストのターミナル表示幅（カラム数）を計算
  ///
  /// 異体字セレクタ（VS16等）を考慮した正確な幅計算を行う。
  static int getTextDisplayWidth(String text) {
    int width = 0;
    final runes = text.runes.toList();

    for (int i = 0; i < runes.length; i++) {
      final rune = runes[i];
      final nextRune = (i + 1 < runes.length) ? runes[i + 1] : null;
      width += getCharDisplayWidthWithContext(rune, nextRune);
    }

    return width;
  }
}
