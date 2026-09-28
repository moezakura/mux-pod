import 'package:flutter/foundation.dart' show visibleForTesting;

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
  /// エスケープシーケンスパターン: SGR (ESC[...m) と OSC (ESC]...BEL|ST) を
  /// 1 本の正規表現で消費する（単一 allMatches ループ維持・位置順保証は
  /// 正規表現エンジン任せ・設計 D1/D2）。
  ///
  /// 3 つ目の代替は未終端 OSC（行内で BEL/ST が現れない場合）で、行末まで
  /// 消費する。対応終端は 7-bit ST (`ESC\`) と BEL (`0x07`) のみで、
  /// 8-bit ST (`0x9C`) は非対応。
  static final _escapeRegex = RegExp(
    r'\x1b\[([0-9;]*)m'
    r'|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)'
    r'|\x1b\][^\x07\x1b]*',
  );

  /// OSC 8 の先頭マッチ: `ESC]8;params;URI...` の形式。params は無視
  /// (id= 等のヒントのみのため)。URI は終端文字 (BEL/ST) を含まない
  /// （URI 内の ';' を正しく扱うため 2 番目の ';' 以降は貪欲に一致）。
  static final _osc8Regex = RegExp(r'^\x1b\]8;[^;\x07\x1b]*;([^\x07\x1b]*)');

  /// SGRパラメータ解釈器
  final AnsiSgrParser _sgr;

  AnsiLineParser({required AnsiSgrParser sgr}) : _sgr = sgr;

  /// インクリメンタルパース用キャッシュ:
  /// (開始スタイル, 開始 URL 状態, 行テキスト) → 解析済み行。
  /// 行の出力は (開始スタイル, 開始 URL 状態, テキスト) のみに依存するので
  /// （🤝#2 行間 URL carry）、位置が変わっても（出力が流れて全行が上に
  /// シフトしても）同一キーで再利用でき、再パースは末尾の新規行だけになる。
  /// 同じ ParsedLine インスタンスを返すため SpanRenderer のスパンキャッシュ
  /// （弱参照キー）も同時にヒットする。
  Map<(AnsiStyle, String?, String), ParsedLine> _lineCache = const {};

  /// ANSIテキストをセグメントに分解
  ///
  /// 正規化（CRLF/CR 置換）や行分割は行わず、入力全体を1ストリームで走査する
  /// （[parseLines] と経路分離）。CR はテキストの一部として残る。
  List<AnsiSegment> parse(String input) {
    return _scan(input, AnsiStyle.defaultStyle, null).segments;
  }

  /// 行単位でパース（仮想スクロール用）
  ///
  /// 各行を個別にパースし、スタイルと OSC 8 リンク状態（endUrl）を次の行に
  /// 引き継ぐ（🤝#2 行間 URL carry）。
  /// 返り値の[ParsedLine]リストは、仮想スクロールで行単位にレンダリングするために使用。
  List<ParsedLine> parseLines(String input) {
    // PTY 経由では \r\n や行末の \r が混入するため、行分割前に正規化する
    // （\n\n 由来の空行はここでは削除せず、実データの空行として保持）。
    final normalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '');
    final lines = normalized.split('\n');
    final prev = _lineCache;
    final next = <(AnsiStyle, String?, String), ParsedLine>{};
    final parsed = <ParsedLine>[];
    var currentStyle = AnsiStyle.defaultStyle;
    String? currentUrl;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final key = (currentStyle, currentUrl, line);
      // (開始スタイル, 開始 URL 状態, テキスト) が一致すれば位置に関係なく
      // 再利用（再パース回避）。
      var pl = next[key] ?? prev[key];
      if (pl == null) {
        final r = _scan(line, currentStyle, currentUrl);
        pl = ParsedLine(
          segments: r.segments,
          endStyle: r.endStyle,
          endUrl: r.endUrl,
        );
      }
      parsed.add(pl);
      next[key] = pl;
      currentStyle = pl.endStyle;
      currentUrl = pl.endUrl;
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

  /// テキストを走査してセグメント列・終了スタイル・終了 URL 状態を返す。
  ///
  /// [parse] と [parseLines] の行単位スキャンの走査ループ共通本体。
  /// 前処理（正規化・行分割・キャッシュ参照・開始スタイル・開始 URL 状態）
  /// は経路別に固定されており、このヘルパーには含めない（経路分離）。
  ///
  /// OSC バイト列は [AnsiSegment.text] に一切混入させない（消費 = セグメント
  /// 列から完全除去）。非表示フラグ型（text に残して表示だけ抑える）の中間
  /// 実装はキャレット/幅計算を壊すため禁止する。
  ({List<AnsiSegment> segments, AnsiStyle endStyle, String? endUrl}) _scan(
    String text,
    AnsiStyle startStyle,
    String? startUrl,
  ) {
    final segments = <AnsiSegment>[];
    var currentStyle = startStyle;
    var currentUrl = startUrl;
    var lastEnd = 0;

    for (final match in _escapeRegex.allMatches(text)) {
      // マッチ前のテキストを追加
      if (match.start > lastEnd) {
        final t = text.substring(lastEnd, match.start);
        if (t.isNotEmpty) {
          segments.add(AnsiSegment(t, currentStyle, url: currentUrl));
        }
      }

      // SGRパラメータを解析してスタイルを更新
      final sgrParams = match.group(1);
      if (sgrParams != null) {
        currentStyle = _sgr.apply(sgrParams, currentStyle);
      } else {
        // OSC: OSC 8 と判定できる場合は URL を抽出してリンク状態を更新する。
        // - 空 URI (`ESC]8;;`) → リンク終了 (null)
        // - params 未完結等で URL 抽出不能（解析不能な開始指示）→
        //   安全側としてリンク状態をリセット（空 URI クローズと同扱い）
        // - 未終端（行末に BEL/ST が無い）で URL が抽出できた場合は
        //   行間 carry となる（endUrl・🤝#2）
        // 非 OSC 8 の OSC（タイトル等）は消費のみでリンク状態は不変。
        final osc = match.group(0)!;
        if (_isOsc8(osc)) {
          currentUrl = extractOsc8Url(osc);
        }
      }
      lastEnd = match.end;
    }

    // 残りのテキストを追加
    if (lastEnd < text.length) {
      final t = text.substring(lastEnd);
      if (t.isNotEmpty) {
        segments.add(AnsiSegment(t, currentStyle, url: currentUrl));
      }
    }

    return (segments: segments, endStyle: currentStyle, endUrl: currentUrl);
  }

  /// [osc] が OSC 8 ハイパーリンクの開始/終了指示かどうか
  /// （`ESC]8;` で始まる、または未終端で `ESC]8` だけの列）。
  /// `ESC]87;...` 等の別番号 OSC は含まない。
  static bool _isOsc8(String osc) =>
      osc.startsWith('\x1b]8;') || osc == '\x1b]8';

  /// OSC 8 バイト列から URL を抽出する static 純関数。
  ///
  /// - OSC 8 以外 / params 未完結等で解析不能 → null（呼び出し側は
  ///   リンク状態リセットとして扱う = 解析不能な開始指示は空 URI クローズと同扱い）
  /// - 空 URI（`ESC]8;;` = リンク終了指示）→ null
  /// - URI 部分: 2 番目の `;` 以降・終端文字 (BEL/ST) までの全て
  ///
  /// 純関数として分離しておくことで、将来 herdr wire の構造化リンク
  /// (CellData.hyperlink) 経路へ差し替える際の単一ポイントになる。
  @visibleForTesting
  static String? extractOsc8Url(String osc) {
    final m = _osc8Regex.firstMatch(osc);
    final uri = m?.group(1) ?? '';
    return uri.isEmpty ? null : uri;
  }
}
