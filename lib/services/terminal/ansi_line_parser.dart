import 'package:flutter/foundation.dart' show visibleForTesting;

import 'ansi_models.dart';
import 'ansi_sgr_parser.dart';

/// 文字オフセット単位（UTF-16 コードユニット）の URL 範囲 1 件
/// （[AnsiLineParser.overlayLineLinks] の入力）。
///
/// メモ化のキー比較に値の等価性を使うため `==`/`hashCode` をオーバーライド
/// する（同ファイルの [AnsiStyle] と同じ方式。free function ではなくこちら
/// を採用: このファイル内のみで使う小さな値型のため）。
final class CharLinkRange {
  /// 開始（inclusive）。
  final int start;

  /// 終了（exclusive）。
  final int end;

  final String url;

  const CharLinkRange({
    required this.start,
    required this.end,
    required this.url,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CharLinkRange &&
          start == other.start &&
          end == other.end &&
          url == other.url;

  @override
  int get hashCode => Object.hash(start, end, url);
}

/// [AnsiLineParser] が元の行ごとに保持する、直近1件の重ね合わせ結果。
class _OverlayMemo {
  final List<CharLinkRange> ranges;
  final ParsedLine line;
  const _OverlayMemo(this.ranges, this.line);
}

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

  /// [overlayLineLinks] が生成した重ね合わせ済み行のメモ。
  ///
  /// キーは元の行（[parseLines] が返したインスタンス）で、元の行ごとに
  /// 直近1件だけを持つ（弱参照キー。元の行が GC されればこのエントリも
  /// 一緒に消える。`_lineCache` を経由しない直接の副作用はここだけ）。
  final Expando<_OverlayMemo> _overlays = Expando<_OverlayMemo>(
    'herdrOverlayMemo',
  );

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

  /// 直近の [parseLines] が返した [ParsedLine] インスタンス、または
  /// その行に対する直近の [overlayLineLinks] の結果のいずれかと
  /// [identical] かどうかを返す（意味は変えない。「直近の parseLines
  /// が返した行か」の判定を、その行から作られた直近の重ね合わせ結果にも
  /// 広げるだけ。元の行が `_lineCache` から外れれば、重ね合わせ結果も
  /// 判定対象から外れる — [_overlays] は元の行をキーにした弱参照のため）。
  ///
  /// スパンキャッシュ（SpanRenderer の弱参照 Expando）は ParsedLine
  /// インスタンスの同一性に依存するため、ファサードの委譲箇所で
  /// 「LineParser が生成したインスタンス」であることを assert するための
  /// 検証口（設計 v2 の規約違反検知）。
  bool contains(ParsedLine line) => _lineCache.values.any(
    (p) => identical(p, line) || identical(_overlays[p]?.line, line),
  );

  /// [line]（[parseLines] が返した既知の行そのもの。[overlayLineLinks] の
  /// 過去の戻り値は不可）に、文字オフセット単位の URL 範囲を重ねた行を返す。
  ///
  /// 呼び出し規約:
  /// - null: [line]・[ranges]・戻り値のいずれも non-nullable。[ranges] は
  ///   空リスト可（その場合 [line] をそのまま返す。新しいインスタンスは
  ///   作らない）。
  /// - 失敗時: throw しない。各区間は [line] の全文字列長で clamp し、
  ///   clamp 後に `start >= end` になる区間は捨てる。区間が重なる場合は、
  ///   [ranges] に先に現れたものを優先する（決定的規則）。
  /// - 同期処理。
  /// - 副作用は、[line] ごとに直近1件だけ持つメモ（[_overlays]）の更新の
  ///   みで、[_lineCache]（[parseLines] の行キャッシュ）は変更しない。
  ///
  /// [line] が直近の [parseLines] の行キャッシュに無い呼び出しは委譲元の
  /// 契約違反として assert で検知する（[contains] は
  /// 「元の行 または その直近1段の重ね合わせ結果」を既知とする広い判定の
  /// ため、ここでの入力検証には使えない。[overlayLineLinks] の戻り値を再度
  /// 入力に渡すと、2 段目の重ね合わせ結果が [_overlays] に元の行以外の
  /// キーで登録され、[contains] の1段限定の判定から漏れて
  /// [AnsiParser.lineToTextSpan] の assert を壊すため、常に元の行だけを
  /// 受け付ける）。
  ParsedLine overlayLineLinks(
    ParsedLine line, {
    required List<CharLinkRange> ranges,
  }) {
    assert(
      _lineCache.values.any((p) => identical(p, line)),
      'overlayLineLinks の line は AnsiLineParser.parseLines が返した'
      'インスタンスそのものであること（overlayLineLinks の戻り値を再度渡す'
      'ことはできない）',
    );
    if (ranges.isEmpty) return line;

    final memo = _overlays[line];
    if (memo != null && _sameRanges(memo.ranges, ranges)) {
      return memo.line;
    }

    final overlaid = _overlayLine(line, ranges);
    _overlays[line] = _OverlayMemo(List.unmodifiable(ranges), overlaid);
    return overlaid;
  }

  static bool _sameRanges(List<CharLinkRange> a, List<CharLinkRange> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// [line] の全文字列に対して [ranges] を重ね合わせ、新しい行を構築する
  /// （境界分割 + 隣接する同一 style・url のセグメントの統合）。
  ///
  /// [ranges] は既に文字オフセット単位（呼び出し側で列 → 文字オフセット
  /// 変換済み）である前提。既存 url のある位置は上書きしない（主判断は
  /// 呼び出し側だが、ここでも防御的に確認する）。変化が無ければ [line] を
  /// そのまま返す（identity 維持）。
  ParsedLine _overlayLine(ParsedLine line, List<CharLinkRange> ranges) {
    final lineText = line.segments.map((s) => s.text).join();
    final lineLength = lineText.length;
    if (lineLength == 0) return line;

    final segmentBounds = <int>[0];
    var acc = 0;
    for (final segment in line.segments) {
      acc += segment.text.length;
      segmentBounds.add(acc);
    }

    // 位置ごとの割り当て url。clamp・空区間除去の後、「先に現れたものを
    // 優先」する決定的規則で埋める（後続の range は既に埋まった位置を
    // 上書きしない）。
    final assignedUrl = List<String?>.filled(lineLength, null);
    for (final range in ranges) {
      final start = range.start.clamp(0, lineLength);
      final end = range.end.clamp(0, lineLength);
      if (start >= end) continue;
      for (var pos = start; pos < end; pos++) {
        assignedUrl[pos] ??= range.url;
      }
    }

    int segmentIndexAt(int pos) {
      for (var i = 0; i < line.segments.length; i++) {
        if (pos >= segmentBounds[i] && pos < segmentBounds[i + 1]) return i;
      }
      return line.segments.length - 1;
    }

    // segment 境界 + range 境界を集約した分割点でテキストを再構成する。
    final boundarySet = <int>{0, lineLength, ...segmentBounds};
    for (final range in ranges) {
      boundarySet.add(range.start.clamp(0, lineLength));
      boundarySet.add(range.end.clamp(0, lineLength));
    }
    final boundaries = boundarySet.toList()..sort();

    final newSegments = <AnsiSegment>[];
    var changed = false;
    for (var b = 0; b < boundaries.length - 1; b++) {
      final start = boundaries[b];
      final end = boundaries[b + 1];
      if (start >= end) continue;

      final originalSegment = line.segments[segmentIndexAt(start)];
      // 既存 url があれば優先し、上書きしない（防御的確認）。
      final url = originalSegment.url ?? assignedUrl[start];
      if (originalSegment.url == null && url != null) changed = true;

      final text = lineText.substring(start, end);
      if (newSegments.isNotEmpty) {
        final last = newSegments.last;
        if (last.style == originalSegment.style && last.url == url) {
          newSegments[newSegments.length - 1] = AnsiSegment(
            last.text + text,
            originalSegment.style,
            url: url,
          );
          continue;
        }
      }
      newSegments.add(AnsiSegment(text, originalSegment.style, url: url));
    }

    if (!changed) return line;
    return ParsedLine(
      segments: newSegments,
      endStyle: line.endStyle,
      endUrl: line.endUrl,
    );
  }

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
