import 'package:flutter/material.dart';

import '../../../../services/backend/domain/pane_frame_reader.dart';
import '../../../../services/terminal/ansi_parser.dart';
import '../../../../services/terminal/font_calculator.dart';
import '../../../../theme/design_colors.dart';

/// ANSI 表示モデル（リビルド最適化の中核）。
///
/// [AnsiParser]，パース結果キャッシュ，行高，カーソル解決，キャレットスパン
/// 生成を所有する。State は build 内で [parsedLines] を毎回呼び、
/// キャッシュキー（text / fontSize / fontFamily）が一致する間は再パースしない。
///
/// 親ウィジェットの前景色・背景色はコンストラクタで与え、
/// 色変更時は [updatePalette] で AnsiParser を再生成しキャッシュを無効化する
/// （旧 `didUpdateWidget` の parser 再生成→`_invalidateCache` と等価）。
class AnsiDisplayModel {
  AnsiParser _parser;

  /// パース済み行データキャッシュ（仮想スクロール用）
  List<ParsedLine>? _cachedParsedLines;
  String? _cachedText;
  double? _cachedFontSize;
  String? _cachedFontFamily;

  /// 行の高さ（仮想スクロールで固定高さを使用）
  double _lineHeight = 20.0;

  AnsiDisplayModel({required Color foreground, required Color background})
    : _parser = AnsiParser(
        defaultForeground: foreground,
        defaultBackground: background,
      );

  /// 現在のパーサー（行スパン変換・背景色解決に使用）。
  AnsiParser get parser => _parser;

  /// 最後にパースした行データ（スクロール命令のキャレット位置算出に使用）。
  ///
  /// 未パース（build 前）は null。scrollToCaret は null ガードして無視する。
  List<ParsedLine>? get parsedLinesCache => _cachedParsedLines;

  /// 行の高さ（最新のパース時の `fontSize × lineHeightRatio`）。
  double get lineHeight => _lineHeight;

  /// フォント色変更時にパーサーを再生成しキャッシュを無効化する。
  ///
  /// 旧 `didUpdateWidget` の「色不一致の場合のみ
  /// `AnsiParser(defaultForeground:…, defaultBackground:…)` を再生成し
  /// `_invalidateCache()`」と等価（v2・critique §2.2）。
  void updatePalette({required Color foreground, required Color background}) {
    _parser = AnsiParser(
      defaultForeground: foreground,
      defaultBackground: background,
    );
    _cachedParsedLines = null;
    _cachedText = null;
    _cachedFontSize = null;
    _cachedFontFamily = null;
  }

  /// 行データを取得（キャッシュ使用・仮想スクロール用）。
  ///
  /// キャッシュが有効な間は再パースしない（parseLines は変更行のみ再パース
  /// するインクリメンタル方式を内部で使用）。
  List<ParsedLine> parsedLines({
    required String text,
    required double fontSize,
    required String fontFamily,
  }) {
    final textChanged = _cachedText != text;

    if (_cachedParsedLines != null &&
        !textChanged &&
        _cachedFontSize == fontSize &&
        _cachedFontFamily == fontFamily) {
      return _cachedParsedLines!;
    }

    _cachedParsedLines = _parser.parseLines(text);
    _cachedText = text;
    _cachedFontSize = fontSize;
    _cachedFontFamily = fontFamily;

    _lineHeight = fontSize * FontCalculator.lineHeightRatio;

    return _cachedParsedLines!;
  }

  /// 描画に使う解決済みカーソル位置と描画可否（純静的）。
  ///
  /// - [PaneCaret]（herdr・Phase 4）が非 null: `visible && 位置既知（x/y
  ///   non-null）&& frame 範囲内` のときだけ描画する（[draw] == true）。
  ///   非表示・位置不明・範囲外は描画しない（従来の cursorX/cursorY には
  ///   フォールバックしない。`cursor:null` 観測と正当な `(0,0)` を分離）。
  /// - [PaneCaret] が null（tmux 等・未取得）: 従来どおり [cursorX] /
  ///   [cursorY] を描画する。
  static ({int x, int y, bool draw}) resolveCaret({
    required PaneCaret? caret,
    required int cursorX,
    required int cursorY,
  }) {
    if (caret == null) {
      return (x: cursorX, y: cursorY, draw: true);
    }
    final x = caret.x;
    final y = caret.y;
    final draw =
        caret.visible &&
        x != null &&
        y != null &&
        x >= 0 &&
        y >= 0 &&
        // frame 寸法が未知（0 以下）のときは範囲検証をスキップする。
        (caret.frameWidth <= 0 || x < caret.frameWidth) &&
        (caret.frameHeight <= 0 || y < caret.frameHeight);
    return (x: x ?? cursorX, y: y ?? cursorY, draw: draw);
  }

  /// キャレット（細い縦バー）のインライン要素を構築する（純静的）。
  ///
  /// ゼロ幅のプレースホルダ（[WidgetSpan]）としてテキスト内の正確な文字境界に
  /// 挿入され、[OverflowBox] で次の文字に重ねて描画する。テキスト幅を一切
  /// 変えないため、以降の文字の描画位置はターミナル格子のまま保たれる。
  static WidgetSpan caretSpan(double fontSize) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SizedBox(
        width: 0,
        height: 0,
        child: OverflowBox(
          maxWidth: 2,
          maxHeight: fontSize,
          alignment: Alignment.center,
          child: SizedBox(
            width: 2,
            height: fontSize,
            child: const ColoredBox(color: DesignColors.primary),
          ),
        ),
      ),
    );
  }
}
