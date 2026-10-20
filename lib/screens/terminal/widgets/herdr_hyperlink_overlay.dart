// Herdr OSC 8 ハイパーリンク: 整列済みリンク範囲を解析済み行へ重ね合わせる
//
// 入力の具体的な取得元（`PaneHyperlinks` / `ScrollbackLinkCache`）には
// 依存しない。行番号（parsedLines のインデックスと同じ 0-based）→
// リンク範囲のリストという抽象化した入力だけを受け取る。
//
// 実際の ParsedLine 構築（境界分割・隣接統合・メモ化・既知集合への登録）は
// `AnsiLineParser.overlayLineLinks`（`AnsiParser` 経由）に委譲する。
// ここで行うのは、列 → 文字オフセット変換（[FontCalculator]。幅計算は
// 再実装しない）と既存 url のある区間の除外だけ。
library;

import '../../../services/herdr/hyperlink/herdr_hyperlink_alignment.dart'
    show HerdrHyperlinkRange;
import '../../../services/terminal/ansi_parser.dart';
import '../../../services/terminal/font_calculator.dart';

export '../../../services/herdr/hyperlink/herdr_hyperlink_alignment.dart'
    show HerdrHyperlinkRange;

/// 解析済み行へ、行ごとのリンク範囲を重ね合わせる。
///
/// - [parser]: 対象の行を生成した [AnsiParser]（`AnsiDisplayModel.parser`）。
///   [line] が [parser] の既知の行（`parseLines`/`overlayLineLinks` が
///   返したインスタンス）であることが前提。
/// - [linksByLine] のキーは [parsedLines] と同じ 0-based 行インデックス
///   （整列済みの本文行番号）。
/// - リンクが無い行、または区間変換の結果何も変わらない行は、**同一の
///   `ParsedLine` インスタンス**を返す（identity 維持。`AnsiLineRow` の
///   recognizer 使い回しを保つため）。
/// - セグメントに既に `url` がある場合は既存の `url` を優先し、
///   上書きしない（herdr helper 由来のリンクは通常パーサ由来のリンクと
///   衝突しないはずだが、防御的に適用する）。
/// - throw しない。
List<ParsedLine> overlayHerdrHyperlinks({
  required AnsiParser parser,
  required List<ParsedLine> parsedLines,
  required Map<int, List<HerdrHyperlinkRange>> linksByLine,
}) {
  if (linksByLine.isEmpty) return parsedLines;

  var anyChanged = false;
  final result = List<ParsedLine>.generate(parsedLines.length, (index) {
    final ranges = linksByLine[index];
    if (ranges == null || ranges.isEmpty) return parsedLines[index];
    final overlaid = _overlayLine(parser, parsedLines[index], ranges);
    if (!identical(overlaid, parsedLines[index])) anyChanged = true;
    return overlaid;
  }, growable: false);

  return anyChanged ? result : parsedLines;
}

/// [line] へ列単位の [ranges] を重ね合わせる。列 → 文字オフセット変換と
/// 既存 url のある区間の除外を行い、実際の行の構築は
/// [AnsiParser.overlayLineLinks]（`AnsiLineParser.overlayLineLinks`）
/// に委譲する。
ParsedLine _overlayLine(
  AnsiParser parser,
  ParsedLine line,
  List<HerdrHyperlinkRange> ranges,
) {
  final lineText = line.segments.map((s) => s.text).join();
  if (lineText.isEmpty) return line;

  // 各 segment の [start, end) 境界（文字オフセット単位）。
  final segmentBounds = <int>[0];
  var acc = 0;
  for (final segment in line.segments) {
    acc += segment.text.length;
    segmentBounds.add(acc);
  }
  final lineLength = acc;
  if (lineLength == 0) return line;

  int segmentIndexAt(int pos) {
    for (var i = 0; i < line.segments.length; i++) {
      if (pos >= segmentBounds[i] && pos < segmentBounds[i + 1]) return i;
    }
    return line.segments.length - 1;
  }

  // range を文字オフセット区間へ変換する。endCol は inclusive のため、
  // 次列（endCol + 1）の文字オフセットを exclusive な終端とする。
  // 列 → 文字オフセットの変換は caret と同じ経路（幅計算を再実装しない）を
  // 使う。
  //
  // 既存 url のある区間は除外する（部分的に重なる場合は、既存 url が
  // 無い部分だけを切り出す。`overlayLineLinks` 側でも防御的に再確認する
  // が、herdr 由来の新規オーバーレイのみをここで確定させる）。
  final charRanges = <CharLinkRange>[];
  for (final range in ranges) {
    final start = FontCalculator.columnToCharOffset(
      lineText,
      range.startCol,
    ).clamp(0, lineLength);
    final end = FontCalculator.columnToCharOffset(
      lineText,
      range.endCol + 1,
    ).clamp(0, lineLength);
    if (end <= start) continue;

    var cursor = start;
    while (cursor < end) {
      final segIdx = segmentIndexAt(cursor);
      final segEnd = segmentBounds[segIdx + 1] < end
          ? segmentBounds[segIdx + 1]
          : end;
      if (line.segments[segIdx].url == null) {
        charRanges.add(
          CharLinkRange(start: cursor, end: segEnd, url: range.url),
        );
      }
      cursor = segEnd;
    }
  }
  if (charRanges.isEmpty) return line;

  return parser.overlayLineLinks(line, ranges: charRanges);
}
