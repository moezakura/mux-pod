import 'dart:developer' as developer;

import 'package:flutter/painting.dart';
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
}
