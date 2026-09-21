import 'package:flutter/material.dart';

import 'ansi_line_parser.dart';
import 'ansi_models.dart';
import 'ansi_span_renderer.dart';
import 'ansi_sgr_parser.dart';

export 'ansi_models.dart';

/// ANSIエスケープシーケンスパーサー
///
/// capture-pane -e の出力（ANSIカラー付きテキスト）を
/// TextSpanに変換するためのパーサー。
///
/// 責務ベース再設計（refactor-p1）の公開ファサード。実処理は
/// [AnsiSgrParser]（SGR 解釈・パレット）/ [AnsiLineParser]（行分解・行キャッシュ）/
/// [AnsiSpanRenderer]（TextSpan 変換・スパンキャッシュ）へ委譲する。
class AnsiParser {
  /// SGRパラメータ解釈器
  final AnsiSgrParser _sgr;

  /// 行パーサ（行キャッシュ所有）
  late final AnsiLineParser _lineParser;

  /// スパンレンダラ（スパンキャッシュ所有）
  final AnsiSpanRenderer _spanRenderer;

  /// デフォルトの前景色
  final Color defaultForeground;

  /// デフォルトの背景色
  final Color defaultBackground;

  AnsiParser({
    this.defaultForeground = const Color(0xFFD4D4D4),
    this.defaultBackground = const Color(0xFF1E1E1E),
  }) : _sgr = AnsiSgrParser(
         defaultForeground: defaultForeground,
         defaultBackground: defaultBackground,
       ),
       _spanRenderer = AnsiSpanRenderer(
         defaultForeground: defaultForeground,
         defaultBackground: defaultBackground,
       ) {
    _lineParser = AnsiLineParser(sgr: _sgr);
  }

  /// ANSIテキストをセグメントに分解
  ///
  /// 正規化（CRLF/CR 置換）や行分割は行わず、入力全体を1ストリームで走査する
  /// （[parseLines] と経路分離）。
  List<AnsiSegment> parse(String input) => _lineParser.parse(input);

  /// ANSIテキストを直接TextSpanに変換
  TextSpan parseToTextSpan(
    String input, {
    required double fontSize,
    required String fontFamily,
  }) {
    final segments = _lineParser.parse(input);
    return _spanRenderer.toTextSpan(
      segments,
      fontSize: fontSize,
      fontFamily: fontFamily,
    );
  }

  /// 行単位でパース（仮想スクロール用）
  ///
  /// 各行を個別にパースし、スタイルを次の行に引き継ぐ。
  /// 返り値の[ParsedLine]リストは、仮想スクロールで行単位にレンダリングするために使用。
  List<ParsedLine> parseLines(String input) => _lineParser.parseLines(input);

  /// セグメントをTextSpanに変換
  TextSpan toTextSpan(
    List<AnsiSegment> segments, {
    required double fontSize,
    required String fontFamily,
  }) {
    return _spanRenderer.toTextSpan(
      segments,
      fontSize: fontSize,
      fontFamily: fontFamily,
    );
  }

  /// ParsedLineをTextSpanに変換
  TextSpan lineToTextSpan(
    ParsedLine line, {
    required double fontSize,
    required String fontFamily,
  }) {
    assert(
      _lineParser.contains(line),
      'ParsedLine は AnsiLineParser.parseLines が返したインスタンスであること'
      '（スパンキャッシュのキーはインスタンス同一性に依存する）',
    );
    return _spanRenderer.lineToTextSpan(
      line,
      fontSize: fontSize,
      fontFamily: fontFamily,
    );
  }

  /// キャレット（任意のインライン要素）を指定文字位置に直接挿入した行スパンを構築する。
  ///
  /// テキストレイアウト中の正確な位置にキャレットを「合成（Stack+Positioned）」
  /// せず直接埋め込むための API（Issue #70 根本対応）。
  ///
  /// - [caretCharOffset]: キャレットを挿入するコードユニットオフセット。
  ///   セグメント境界・行末・空行のいずれでもよい（クランプされる）。
  /// - [padColumns]: 行テキスト終端よりさらに右のカラムにキャレットを置く場合の
  ///   埋めセル数（No-Break Space で埋める）。
  /// - [caret]: 挿入するインライン要素。null の場合はキャッシュ済みの通常行スパンを返す。
  TextSpan lineToTextSpanWithCaret(
    ParsedLine line, {
    required double fontSize,
    required String fontFamily,
    required int caretCharOffset,
    required int padColumns,
    InlineSpan? caret,
  }) {
    assert(
      _lineParser.contains(line),
      'ParsedLine は AnsiLineParser.parseLines が返したインスタンスであること'
      '（スパンキャッシュのキーはインスタンス同一性に依存する）',
    );
    return _spanRenderer.lineToTextSpanWithCaret(
      line,
      fontSize: fontSize,
      fontFamily: fontFamily,
      caretCharOffset: caretCharOffset,
      padColumns: padColumns,
      caret: caret,
    );
  }

  /// セグメント/行スタイルから描画用の前景色・背景色と「背景を描くか」を決定する。
  ///
  /// inverse 時は前背景を入れ替える。`paintBackground`（`inverse || 背景≠default`）
  /// は行背景レイヤー（[effectiveLineBackgroundColor]）の要否判定に使う単一ソース
  /// （R3）であり、セグメント→span 変換側は opaque 化により背景色を常時設定する
  /// （HYP-4 opaque）。
  ({Color foreground, Color background, bool paintBackground})
  resolvePaintColors(AnsiStyle style) =>
      _spanRenderer.resolvePaintColors(style);

  /// 行全体の有効背景色（行末まで延長・空行背景用）を返す。
  ///
  /// tmux capture-pane は「デフォルト背景の末尾空セル」を出力せず、行が有色で
  /// 終わる場合に合成 `\x1b[49m` を付加する（skeptic ライブ実験・EV-LOG-006）。
  /// したがって行末セルの真のスタイルは「行内最後の SGR 適用後」= [ParsedLine.endStyle]
  /// であり、非空行も endStyle から導出する（旧「最終セグメントと同じ」前提は FALSE）。
  ///
  /// 例外: 最終セグメントが**背景付きで空白で終わる**行（例: アプリが明示的に書いた
  /// 色付きスペース列 EV-LOG-006 型）は、その空白が実在の色付きセルであり、実機の
  /// Flutter は span 末尾の空白背景を描画しない（EV-LOG-003 before: blue x=8..158 で
  /// 終端）ため、最終セグメント色で全幅レイヤーを残す（PR#98 の「行末まで色埋め」を
  /// 回帰させない）。末尾空白でない最終セグメントの行（S1/S3/S4）は余白=endStyle。
  ///
  /// デフォルト背景と等しい場合は null（背景レイヤー不要）を返す。
  Color? effectiveLineBackgroundColor(ParsedLine line) {
    assert(
      _lineParser.contains(line),
      'ParsedLine は AnsiLineParser.parseLines が返したインスタンスであること'
      '（スパンキャッシュのキーはインスタンス同一性に依存する）',
    );
    return _spanRenderer.effectiveLineBackgroundColor(line);
  }
}
