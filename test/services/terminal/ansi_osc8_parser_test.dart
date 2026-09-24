import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/ansi_line_parser.dart';
import 'package:flutter_muxpod/services/terminal/ansi_parser.dart';

/// OSC 8 ハイパーリンク対応（Issue #61・🤝#2 行間 URL carry）のパーサ単体テスト。
///
/// - OSC（終端 BEL/7-bit ST・未終端）の消費と OSC バイト列の非混入
/// - OSC 8 変種（params 付き・URI 内 ';'・ネスト URL 上書き・クローズ先行・
///   解析不能開始指示のリセット等）
/// - 行間 URL carry（endUrl・行キャッシュキー (開始スタイル, 開始 URL 状態,
///   行テキスト) 3 要素化）
///
/// 設計根拠: 複合正規表現 1 本（architect D1/D2）・URL 属性は AnsiSegment（D3）・
/// 未終端 OSC 8 は打ち切らず carry（🤝#2 承認済み計画。architect v2 §7-1
/// ケース 6 の「打ち切り」期待値は本計画により carry に上書き）。
/// キー意味論の規約テストは ansi_parse_semantics_test.dart の
/// URL 次元 group、レンダリングは ansi_span_renderer_link_test.dart を参照。
void main() {
  AnsiParser newParser() => AnsiParser();

  group('OSC 変種', () {
    test('OSC 8 開始 (ST 終端・params 付き) 〜 終了 (空 URI) の区間に url が付く', () {
      final parser = newParser();
      final segments = parser
          .parse('\x1b]8;id=x;https://ex.com\x1b\\link\x1b]8;;\x1b\\');
      expect(segments.length, 1);
      expect(segments.single.text, 'link');
      expect(segments.single.url, 'https://ex.com');
    });

    test('OSC 8 開始 (BEL 終端) も ST 終端と同結果 (Issue #61 必須要件)', () {
      final parser = newParser();
      final segments =
          parser.parse('\x1b]8;;https://ex.com\x07link\x1b]8;;\x07');
      expect(segments.single.text, 'link');
      expect(segments.single.url, 'https://ex.com');
    });

    test('OSC 2 (タイトル) は消費のみでリンク状態を変えない', () {
      final parser = newParser();
      final segments = parser.parse('\x1b]2;my title\x07hello');
      expect(segments.single.text, 'hello');
      expect(segments.single.url, isNull);
    });

    test('リンク中の OSC 2 (タイトル) は url を継続させる', () {
      final parser = newParser();
      final segments = parser.parse('\x1b]8;;u\x07a\x1b]2;t\x07b');
      expect(segments.length, 2);
      expect(segments[0].text, 'a');
      expect(segments[0].url, 'u');
      expect(segments[1].text, 'b');
      expect(segments[1].url, 'u');
    });

    test('URI 内の ; は貪欲に URL へ含める', () {
      final parser = newParser();
      final segments = parser.parse('\x1b]8;;https://ex.com/a;b\x07x');
      expect(segments.single.text, 'x');
      expect(segments.single.url, 'https://ex.com/a;b');
    });

    test('クローズ先行 (未オープンの終了指示) は無視され例外を出さない', () {
      final parser = newParser();
      final segments = parser.parse('\x1b]8;;\x1b\\after');
      expect(segments.single.text, 'after');
      expect(segments.single.url, isNull);
    });

    test('ネストしたオープンは URL を上書きする', () {
      final parser = newParser();
      final segments = parser.parse(
        '\x1b]8;;https://a\x07first\x1b]8;;https://b\x07second\x1b]8;;\x07tail',
      );
      expect(segments.length, 3);
      expect(segments[0].text, 'first');
      expect(segments[0].url, 'https://a');
      expect(segments[1].text, 'second');
      expect(segments[1].url, 'https://b');
      expect(segments[2].text, 'tail');
      expect(segments[2].url, isNull);
    });

    test('未知 params キーは無視して URL を抽出する', () {
      final parser = newParser();
      final segments = parser.parse('\x1b]8;unknown=key;https://ex.com\x07L');
      expect(segments.single.text, 'L');
      expect(segments.single.url, 'https://ex.com');
    });

    test('解析不能な開始指示 (params 未完結) はリンク状態をリセットする', () {
      final parser = newParser();
      final segments = parser.parse('\x1b]8;;u\x07a\x1b]8;id=x\x07b');
      expect(segments.length, 2);
      expect(segments[0].text, 'a');
      expect(segments[0].url, 'u');
      expect(segments[1].text, 'b');
      expect(segments[1].url, isNull);
    });

    test('未終端の単独 ESC]8 も解析不能な開始指示としてリセットする', () {
      final parser = newParser();
      final lines = parser.parseLines('\x1b]8;;u\x07a\x1b]8');
      expect(lines.single.segments.single.text, 'a');
      expect(lines.single.segments.single.url, 'u');
      expect(lines.single.endUrl, isNull);
    });

    test('未終端 OSC 8 は打ち切らず carry する (🤝#2)', () {
      final parser = newParser();
      final lines = parser.parseLines('\x1b]8;;https://ex.com/partial\nnext');
      expect(lines[0].segments, isEmpty);
      expect(lines[0].endUrl, 'https://ex.com/partial');
      expect(lines[1].segments.single.text, 'next');
      expect(lines[1].segments.single.url, 'https://ex.com/partial');
    });

    test('未終端でも params 未完結なら carry しない（リセット）', () {
      final parser = newParser();
      final lines = parser.parseLines('\x1b]8;id=x\nnext');
      expect(lines[0].segments, isEmpty);
      expect(lines[0].endUrl, isNull);
      expect(lines[1].segments.single.text, 'next');
      expect(lines[1].segments.single.url, isNull);
    });

    test('parse 経路でも未終端 OSC 8 以降のテキストに url が付く', () {
      final parser = newParser();
      final segments =
          parser.parse('\x1b]8;;https://ex.com/partial\x1b[31mRED');
      expect(segments.single.text, 'RED');
      expect(segments.single.url, 'https://ex.com/partial');
      expect(segments.single.style.foreground, const Color(0xFFCD3131));
    });
  });

  group('行間 carry (🤝#2)', () {
    test('開始行から後続行へ url 状態が引き継がれる', () {
      final parser = newParser();
      final lines = parser.parseLines('\x1b]8;;https://ex.com\x07l0\nl1');
      expect(lines[0].segments.single.text, 'l0');
      expect(lines[0].segments.single.url, 'https://ex.com');
      expect(lines[0].endUrl, 'https://ex.com');
      expect(lines[1].segments.single.text, 'l1');
      expect(lines[1].segments.single.url, 'https://ex.com');
    });

    test('空行を挟んでも carry する', () {
      final parser = newParser();
      final lines = parser.parseLines('\x1b]8;;u\x07l0\n\nl1');
      expect(lines[0].segments.single.url, 'u');
      expect(lines[1].segments, isEmpty);
      expect(lines[1].endUrl, 'u');
      expect(lines[2].segments.single.text, 'l1');
      expect(lines[2].segments.single.url, 'u');
    });

    test('クローズ後の行は url null に戻る (endUrl 導出)', () {
      final parser = newParser();
      final lines = parser.parseLines('\x1b]8;;u\x07l0\x1b]8;;\x07\nl1');
      expect(lines[0].segments.single.url, 'u');
      expect(lines[0].endUrl, isNull);
      expect(lines[1].segments.single.url, isNull);
    });

    test('endStyle に URL は混入せず endUrl に分離される', () {
      final parser = newParser();
      final lines = parser.parseLines('\x1b]8;;u\x07\x1b[31ml0\nl1');
      // リンク中の SGR で style が変化し、次行にも style と url の両方が引き継がれる
      expect(lines[0].endStyle, const AnsiStyle(foreground: Color(0xFFCD3131)));
      expect(lines[0].endUrl, 'u');
      expect(lines[1].segments.single.style.foreground, const Color(0xFFCD3131));
      expect(lines[1].segments.single.url, 'u');
    });
  });

  group('行キャッシュキー 3 要素 (開始スタイル, 開始 URL 状態, 行テキスト)', () {
    test('同一 (style, url, text) は identical', () {
      final parser = newParser();
      final first = parser.parseLines('\x1b]8;;u\x07l0\nl1');
      final second = parser.parseLines('\x1b]8;;u\x07l0\nl1');
      expect(identical(first[0], second[0]), isTrue);
      expect(identical(first[1], second[1]), isTrue);
    });

    test('同一 (style, text) でも開始 URL 状態が異なれば非 identical', () {
      final parser = newParser();
      final linked = parser.parseLines('\x1b]8;;u\x07l1');
      final plain = parser.parseLines('l1');
      expect(linked.single.segments.single.text, plain.single.segments.single.text);
      expect(linked.single.segments.single.url, 'u');
      expect(plain.single.segments.single.url, isNull);
      expect(identical(linked.single, plain.single), isFalse);
    });

    test('行跨ぎリンクの 2 行目は先行行の内容が違っても同一キーなら identical', () {
      final parser = newParser();
      final x = parser.parseLines('\x1b]8;;u\x07l0\nl1');
      final y = parser.parseLines('\x1b]8;;u\x07p\nl1');
      expect(identical(x[1], y[1]), isTrue);
    });
  });

  group('OSC バイト列の非混入・SGR 併用', () {
    test('OSC バイト列はセグメント text に一切混入しない', () {
      final parser = newParser();
      const input = '\x1b]8;id=x;https://ex.com\x1b\\link\x1b]8;;\x1b\\tail';
      final segments = parser.parse(input);
      final joined = segments.map((s) => s.text).join();
      expect(joined, 'linktail');
      for (final s in segments) {
        expect(s.text.contains('\x1b'), isFalse, reason: '${s.text} に ESC が混入');
        expect(s.text.contains(']8;'), isFalse, reason: '${s.text} に OSC 8 が混入');
      }
    });

    test('リンク中の SGR 変更は url を継続させスタイルのみ変わる', () {
      final parser = newParser();
      final segments = parser
          .parse('\x1b]8;;u\x07\x1b[31mred\x1b[0mstill\x1b]8;;\x07tail');
      expect(segments.length, 3);
      expect(segments[0].text, 'red');
      expect(segments[0].url, 'u');
      expect(segments[0].style.foreground, const Color(0xFFCD3131));
      expect(segments[1].text, 'still');
      expect(segments[1].url, 'u');
      expect(segments[1].style, AnsiStyle.defaultStyle);
      expect(segments[2].text, 'tail');
      expect(segments[2].url, isNull);
    });

    test('1 行に複数リンクを配置できる', () {
      final parser = newParser();
      final segments = parser.parse(
        '\x1b]8;;a\x07one\x1b]8;;\x07mid\x1b]8;;b\x07two\x1b]8;;\x07',
      );
      expect(segments.map((s) => s.text).toList(), ['one', 'mid', 'two']);
      expect(segments.map((s) => s.url).toList(), ['a', null, 'b']);
    });
  });

  group('extractOsc8Url (static 純関数・Dart 正規表現の固定)', () {
    test('BEL 終端・params 無しから URL を抽出する', () {
      expect(
        AnsiLineParser.extractOsc8Url('\x1b]8;;https://ex.com\x07'),
        'https://ex.com',
      );
    });

    test('ST 終端・params 付きから URL を抽出する', () {
      expect(
        AnsiLineParser.extractOsc8Url('\x1b]8;id=x;https://ex.com\x1b\\'),
        'https://ex.com',
      );
    });

    test('空 URI は null (リンク終了)', () {
      expect(AnsiLineParser.extractOsc8Url('\x1b]8;;\x07'), isNull);
    });

    test('params 未完結は null (解析不能)', () {
      expect(AnsiLineParser.extractOsc8Url('\x1b]8;id=x\x07'), isNull);
    });

    test('OSC 8 以外は null', () {
      expect(AnsiLineParser.extractOsc8Url('\x1b]2;title\x07'), isNull);
    });

    test('未終端列でも URL を抽出できる (carry 用)', () {
      expect(
        AnsiLineParser.extractOsc8Url('\x1b]8;;https://ex.com/partial'),
        'https://ex.com/partial',
      );
    });

    test('URI 内の ; を含めて抽出する', () {
      expect(
        AnsiLineParser.extractOsc8Url('\x1b]8;;https://e.com/a;b\x07'),
        'https://e.com/a;b',
      );
    });
  });
}
