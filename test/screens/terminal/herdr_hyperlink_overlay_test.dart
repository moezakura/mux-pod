import 'package:flutter_muxpod/screens/terminal/widgets/herdr_hyperlink_overlay.dart';
import 'package:flutter_muxpod/services/terminal/ansi_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// テスト用: 単一行テキストを実際の [AnsiParser.parseLines] でパースして
/// 返す（[overlayHerdrHyperlinks] が渡す行は "AnsiLineParser が返した既知の
/// 行" である前提。手組みの `ParsedLine` を直接渡すと
/// `overlayLineLinks` 内の `contains(line)` assert に落ちる）。
ParsedLine _lineOf(AnsiParser parser, String text) =>
    parser.parseLines(text)[0];

void main() {
  group('overlayHerdrHyperlinks', () {
    test('ASCII 行: 指定範囲だけに url が付き、前後は装飾のみで残る', () {
      final parser = AnsiParser();
      final line = _lineOf(parser, 'click here for more');

      final result = overlayHerdrHyperlinks(
        parser: parser,
        parsedLines: [line],
        linksByLine: {
          0: const [
            HerdrHyperlinkRange(
              startCol: 6,
              endCol: 9,
              url: 'https://example.com/',
            ),
          ],
        },
      );

      expect(identical(result[0], line), isFalse);
      final segments = result[0].segments;
      expect(segments.map((s) => s.text).join(), 'click here for more');
      final linked = segments.where((s) => s.url != null).toList();
      expect(linked, hasLength(1));
      expect(linked.single.text, 'here');
      expect(linked.single.url, 'https://example.com/');
    });

    test('CJK 全角文字の後を正しく列変換してリンクを付ける', () {
      // "あ" は表示幅2（列0-1）。続く "AB" は列2・3。
      final parser = AnsiParser();
      final line = _lineOf(parser, 'あAB');

      final result = overlayHerdrHyperlinks(
        parser: parser,
        parsedLines: [line],
        linksByLine: {
          0: const [
            HerdrHyperlinkRange(
              startCol: 2,
              endCol: 3,
              url: 'https://a.example/',
            ),
          ],
        },
      );

      final segments = result[0].segments;
      expect(segments.map((s) => s.text).join(), 'あAB');
      // "あ" にはリンクが付かない。
      final ahead = segments.firstWhere((s) => s.text.contains('あ'));
      expect(ahead.url, isNull);
      final linked = segments.where((s) => s.url != null).toList();
      expect(linked, hasLength(1));
      expect(linked.single.text, 'AB');
    });

    test('CJK 全角文字に「かかる」リンクは、その全角文字自体を含めて付ける', () {
      // "日本" は表示幅4（列0-3、各文字が列2つ分）。続く "AB" は列4・5。
      // リンクは "日" の後半セルを含む列0-3全体（"日本" 全体）にかかる。
      final parser = AnsiParser();
      final line = _lineOf(parser, '日本AB');

      final result = overlayHerdrHyperlinks(
        parser: parser,
        parsedLines: [line],
        linksByLine: {
          0: const [
            HerdrHyperlinkRange(
              startCol: 0,
              endCol: 3,
              url: 'https://cjk.example/',
            ),
          ],
        },
      );

      final segments = result[0].segments;
      expect(segments.map((s) => s.text).join(), '日本AB');
      final linked = segments.where((s) => s.url != null).toList();
      expect(linked, hasLength(1));
      expect(linked.single.text, '日本');
      expect(linked.single.url, 'https://cjk.example/');
      final tail = segments.firstWhere((s) => s.text == 'AB');
      expect(tail.url, isNull);
    });

    test('endCol が行テキストの実際の長さを超える場合は行末で clamp される', () {
      // helper 側のフレーム幅（例: 80列）ぶん endCol が振られていても、
      // pane read 側は末尾の空白が落ちて短い行になる。
      // columnToCharOffset が範囲外の列指定に対して文字列長で止まる（clamp）
      // ため、行全体にリンクが付く。
      final parser = AnsiParser();
      final line = _lineOf(parser, 'abc');

      final result = overlayHerdrHyperlinks(
        parser: parser,
        parsedLines: [line],
        linksByLine: {
          0: const [
            HerdrHyperlinkRange(
              startCol: 0,
              endCol: 79,
              url: 'https://overflow.example/',
            ),
          ],
        },
      );

      final segments = result[0].segments;
      expect(segments, hasLength(1));
      expect(segments.single.text, 'abc');
      expect(segments.single.url, 'https://overflow.example/');
    });

    test('行末まで続くリンク（endCol = 最終列）は末尾文字を含む', () {
      final parser = AnsiParser();
      final line = _lineOf(parser, 'tail');

      final result = overlayHerdrHyperlinks(
        parser: parser,
        parsedLines: [line],
        linksByLine: {
          0: const [
            HerdrHyperlinkRange(
              startCol: 0,
              endCol: 3,
              url: 'https://tail.example/',
            ),
          ],
        },
      );

      final segments = result[0].segments;
      expect(segments, hasLength(1));
      expect(segments.single.text, 'tail');
      expect(segments.single.url, 'https://tail.example/');
    });

    test('隣接する別 URL は結合されず、境界で分離したセグメントになる', () {
      final parser = AnsiParser();
      final line = _lineOf(parser, 'foobar');

      final result = overlayHerdrHyperlinks(
        parser: parser,
        parsedLines: [line],
        linksByLine: {
          0: const [
            HerdrHyperlinkRange(
              startCol: 0,
              endCol: 2,
              url: 'https://foo.example/',
            ),
            HerdrHyperlinkRange(
              startCol: 3,
              endCol: 5,
              url: 'https://bar.example/',
            ),
          ],
        },
      );

      final segments = result[0].segments;
      expect(segments.map((s) => s.text).toList(), ['foo', 'bar']);
      expect(segments[0].url, 'https://foo.example/');
      expect(segments[1].url, 'https://bar.example/');
    });

    test('リンクが無い行、または重ならない行は同一の ParsedLine インスタンスを返す', () {
      final parser = AnsiParser();
      // 同じ parser の1回の parseLines で複数行を得る（行間の行キャッシュ
      // キーが独立するよう、内容を変えておく）。
      final lines = parser.parseLines('no links here\nhas a link');
      final unaffected = lines[0];
      final linked = lines[1];

      final result = overlayHerdrHyperlinks(
        parser: parser,
        parsedLines: lines,
        linksByLine: {
          1: const [
            HerdrHyperlinkRange(
              startCol: 8,
              endCol: 9,
              url: 'https://link.example/',
            ),
          ],
        },
      );

      // 変化の無い行 (index 0) は同一インスタンス。
      expect(identical(result[0], unaffected), isTrue);
      // 変化した行 (index 1) は新しいインスタンス。
      expect(identical(result[1], linked), isFalse);
    });

    test('linksByLine が空のときはリスト自体を変更せず返す', () {
      final parser = AnsiParser();
      final input = parser.parseLines('plain');

      final result = overlayHerdrHyperlinks(
        parser: parser,
        parsedLines: input,
        linksByLine: const {},
      );

      expect(identical(result, input), isTrue);
    });

    test('セグメントに既存の url がある場合はそれを優先し上書きしない', () {
      final parser = AnsiParser();
      // 行全体が既存の OSC 8 リンク（パーサ由来）で覆われている状態。
      final line = _lineOf(
        parser,
        '\x1b]8;;https://existing.example/\x07existing link text\x1b]8;;\x07',
      );
      expect(line.segments.single.url, 'https://existing.example/');

      final result = overlayHerdrHyperlinks(
        parser: parser,
        parsedLines: [line],
        linksByLine: {
          0: const [
            HerdrHyperlinkRange(
              startCol: 0,
              endCol: 18,
              url: 'https://from-helper.example/',
            ),
          ],
        },
      );

      // 既存 url が行全体を覆っているため、変化なし＝同一インスタンス。
      expect(identical(result[0], line), isTrue);
      expect(result[0].segments.single.url, 'https://existing.example/');
    });
  });
}
