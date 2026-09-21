import 'ansi_models.dart';
import 'ansi_sgr_parser.dart';

/// ANSIテキストをセグメント列・行リストへ分解する。
///
/// SGRパラメータの解釈は注入された [AnsiSgrParser] に委譲する。
/// 行パースキャッシュ（[_lineCache]）を所有する。
///
/// 経路分離（設計 v2）: [parse] は正規化なし・行分割なしの入力全体スキャン、
/// [parseLines] は CRLF/CR 正規化 + 行分割 + 行キャッシュ参照を行う。
/// 両者のスキャン走査ループ本体のみ [_scan] で共通化する（前処理は経路別）。
class AnsiLineParser {
  /// SGR (Select Graphic Rendition) パターン: ESC[...m
  static final _sgrRegex = RegExp(r'\x1b\[([0-9;]*)m');

  /// SGRパラメータ解釈器
  final AnsiSgrParser _sgr;

  AnsiLineParser({required AnsiSgrParser sgr}) : _sgr = sgr;

  /// インクリメンタルパース用キャッシュ: (開始スタイル, 行テキスト) → 解析済み行。
  /// 行の出力は (開始スタイル, テキスト) のみに依存するので、位置が変わっても
  /// （出力が流れて全行が上にシフトしても）同一キーで再利用でき、再パースは
  /// 末尾の新規行だけになる。同じ ParsedLine インスタンスを返すため
  /// SpanRenderer のスパンキャッシュ（弱参照キー）も同時にヒットする。
  Map<(AnsiStyle, String), ParsedLine> _lineCache = const {};

  /// ANSIテキストをセグメントに分解
  ///
  /// 正規化（CRLF/CR 置換）や行分割は行わず、入力全体を1ストリームで走査する
  /// （[parseLines] と経路分離）。CR はテキストの一部として残る。
  List<AnsiSegment> parse(String input) {
    return _scan(input, AnsiStyle.defaultStyle).segments;
  }

  /// 行単位でパース（仮想スクロール用）
  ///
  /// 各行を個別にパースし、スタイルを次の行に引き継ぐ。
  /// 返り値の[ParsedLine]リストは、仮想スクロールで行単位にレンダリングするために使用。
  List<ParsedLine> parseLines(String input) {
    // PTY 経由では \r\n や行末の \r が混入するため、行分割前に正規化する
    // （\n\n 由来の空行はここでは削除せず、実データの空行として保持）。
    final normalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '');
    final lines = normalized.split('\n');
    final prev = _lineCache;
    final next = <(AnsiStyle, String), ParsedLine>{};
    final parsed = <ParsedLine>[];
    var currentStyle = AnsiStyle.defaultStyle;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final key = (currentStyle, line);
      // (開始スタイル, テキスト) が一致すれば位置に関係なく再利用（再パース回避）。
      var pl = next[key] ?? prev[key];
      if (pl == null) {
        final r = _scan(line, currentStyle);
        pl = ParsedLine(segments: r.segments, endStyle: r.endStyle);
      }
      parsed.add(pl);
      next[key] = pl;
      currentStyle = pl.endStyle;
    }

    _lineCache = next;
    return parsed;
  }

  /// 直近の [parseLines] が返した [ParsedLine] インスタンスのいずれかと
  /// [identical] かどうかを返す。
  ///
  /// スパンキャッシュ（SpanRenderer の弱参照 Expando）は ParsedLine
  /// インスタンスの同一性に依存するため、ファサードの委譲箇所で
  /// 「LineParser が生成したインスタンス」であることを assert するための
  /// 検証口（設計 v2 の規約違反検知）。
  bool contains(ParsedLine line) =>
      _lineCache.values.any((p) => identical(p, line));

  /// テキストを走査してセグメント列と終了スタイルを返す。
  ///
  /// [parse] と [parseLines] の行単位スキャンの走査ループ共通本体。
  /// 前処理（正規化・行分割・キャッシュ参照・開始スタイル）は経路別に
  /// 固定されており、このヘルパーには含めない（経路分離）。
  ({List<AnsiSegment> segments, AnsiStyle endStyle}) _scan(
    String text,
    AnsiStyle startStyle,
  ) {
    final segments = <AnsiSegment>[];
    var currentStyle = startStyle;
    var lastEnd = 0;

    for (final match in _sgrRegex.allMatches(text)) {
      // マッチ前のテキストを追加
      if (match.start > lastEnd) {
        final t = text.substring(lastEnd, match.start);
        if (t.isNotEmpty) {
          segments.add(AnsiSegment(t, currentStyle));
        }
      }

      // SGRパラメータを解析してスタイルを更新
      final params = match.group(1) ?? '';
      currentStyle = _sgr.apply(params, currentStyle);
      lastEnd = match.end;
    }

    // 残りのテキストを追加
    if (lastEnd < text.length) {
      final t = text.substring(lastEnd);
      if (t.isNotEmpty) {
        segments.add(AnsiSegment(t, currentStyle));
      }
    }

    return (segments: segments, endStyle: currentStyle);
  }
}
