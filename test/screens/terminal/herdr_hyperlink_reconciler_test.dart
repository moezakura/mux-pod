import 'package:flutter_muxpod/screens/terminal/widgets/herdr_hyperlink_reconciler.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_alignment.dart';
import 'package:flutter_muxpod/services/terminal/ansi_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// テスト用: 本文の行フィンガープリントを本番実装（[HerdrRowFingerprint]）で
/// そのまま計算する（アルゴリズムの再実装ではなく、テストの意図を
/// 読みやすくするための薄いラッパー）。
String _fingerprintOf(String displayText) {
  final fp = HerdrRowFingerprint.rowFingerprint(displayText);
  if (fp == null) {
    throw ArgumentError('empty displayText is not supported in this helper');
  }
  return fp;
}

/// テスト用: 複数行テキストを実際の [AnsiParser.parseLines] でパースして
/// 返す（[reconcileHerdrHyperlinks] は overlay 経路で "AnsiLineParser が
/// 返した既知の行" である前提を置く。手組みの `ParsedLine` を直接
/// 渡すと `overlayLineLinks` 内の `contains(line)` assert に落ちる）。
List<ParsedLine> _linesOf(AnsiParser parser, List<String> texts) =>
    parser.parseLines(texts.join('\n'));

void main() {
  group('reconcileHerdrHyperlinks', () {
    test('hyperlinks が null のときは本文をそのまま返す', () {
      final parser = AnsiParser();
      final body = _linesOf(parser, ['hello world']);
      final result = reconcileHerdrHyperlinks(
        bodyLines: body,
        parser: parser,
        hyperlinks: null,
        paneWidth: 80,
      );
      expect(identical(result, body), isTrue);
    });

    test('links が空のときは本文をそのまま返す', () {
      final parser = AnsiParser();
      final body = _linesOf(parser, ['hello world']);
      final hyperlinks = PaneHyperlinks(frameWidth: 80, frameHeight: 1);
      final result = reconcileHerdrHyperlinks(
        bodyLines: body,
        parser: parser,
        hyperlinks: hyperlinks,
        paneWidth: 80,
      );
      expect(identical(result, body), isTrue);
    });

    test('frameWidth が 0 以下（壊れたデータ）の窓は全リンク抑制'
        '（helper が実 pty サイズを優先するため、依頼幅との一致は見ず、'
        'frameWidth の妥当性チェックのみ行う）', () {
      final parser = AnsiParser();
      final body = _linesOf(parser, ['click here now']);
      final hyperlinks = PaneHyperlinks(
        frameWidth: 0,
        frameHeight: 1,
        links: const [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [PaneHyperlinkRange(row: 0, startCol: 6, endCol: 9)],
          ),
        ],
        rowFingerprints: {0: _fingerprintOf('click here now')},
      );

      final result = reconcileHerdrHyperlinks(
        bodyLines: body,
        parser: parser,
        hyperlinks: hyperlinks,
        paneWidth: 80,
      );

      expect(identical(result, body), isTrue);
    });

    test('frameWidth が依頼幅（max(paneWidth,80)）と違っても、fingerprint が '
        '一致していればリンクは出る（helper が実 pty サイズを優先するため、'
        '依頼幅との不一致自体は抑制理由にならない）', () {
      final parser = AnsiParser();
      final body = _linesOf(parser, ['click here now']);
      final hyperlinks = PaneHyperlinks(
        frameWidth: 100, // paneWidth=80 → 依頼幅 80 とは不一致
        frameHeight: 1,
        links: const [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [PaneHyperlinkRange(row: 0, startCol: 6, endCol: 9)],
          ),
        ],
        rowFingerprints: {0: _fingerprintOf('click here now')},
      );

      final result = reconcileHerdrHyperlinks(
        bodyLines: body,
        parser: parser,
        hyperlinks: hyperlinks,
        paneWidth: 80,
      );

      expect(identical(result, body), isFalse);
      final linked = result[0].segments.where((s) => s.url != null).toList();
      expect(linked, hasLength(1));
      expect(linked.single.url, 'https://example.com/');
    });

    test('paneWidth=54・frameWidth=80 は抑制されない'
        '（fingerprint が一致していれば幅の値自体は問わない）', () {
      final parser = AnsiParser();
      final body = _linesOf(parser, ['click here now']);
      final hyperlinks = PaneHyperlinks(
        frameWidth: 80, // max(54,80)=80 と一致
        frameHeight: 1,
        links: const [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [PaneHyperlinkRange(row: 0, startCol: 6, endCol: 9)],
          ),
        ],
        rowFingerprints: {0: _fingerprintOf('click here now')},
      );

      final result = reconcileHerdrHyperlinks(
        bodyLines: body,
        parser: parser,
        hyperlinks: hyperlinks,
        paneWidth: 54,
      );

      expect(identical(result, body), isFalse);
      final linked = result[0].segments.where((s) => s.url != null).toList();
      expect(linked, hasLength(1));
      expect(linked.single.text, 'here');
      expect(linked.single.url, 'https://example.com/');
    });

    test('paneWidth=54・frameWidth=54 は抑制されない（対照。依頼幅 '
        'max(54,80)=80 と不一致でも、fingerprint が一致していれば、'
        'helper が実 pty サイズ（54）で返してきても問題ない）', () {
      final parser = AnsiParser();
      final body = _linesOf(parser, ['click here now']);
      final hyperlinks = PaneHyperlinks(
        frameWidth: 54, // 実 pty サイズ（helper が優先して使った幅）
        frameHeight: 1,
        links: const [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [PaneHyperlinkRange(row: 0, startCol: 6, endCol: 9)],
          ),
        ],
        rowFingerprints: {0: _fingerprintOf('click here now')},
      );

      final result = reconcileHerdrHyperlinks(
        bodyLines: body,
        parser: parser,
        hyperlinks: hyperlinks,
        paneWidth: 54,
      );

      expect(identical(result, body), isFalse);
      final linked = result[0].segments.where((s) => s.url != null).toList();
      expect(linked, hasLength(1));
      expect(linked.single.url, 'https://example.com/');
    });

    test('paneWidth=54・frameWidth=54 でも、実際に折り返しが異なり本文と '
        'frame の内容が食い違う行だけ行単位で抑制される（helper が実 pty '
        'サイズ（狭い幅）を優先する動機そのもの: 幅が違えば '
        '同じ論理行でも折り返しが変わり、行の内容が本文と一致しなくなる。'
        '幅の不一致そのものではなく、結果として現れる fingerprint の不一致を '
        '通してフェイルセーフに抑制されることを確認する。行の整列自体は '
        'row0-2 の一致（min(3,4)=3 票）で成立させ、row3 だけの除外である '
        'こと＝窓全体の抑制ではなく行単位の抑制であることを、row0 の '
        'リンクが生き残ることで示す）', () {
      final parser = AnsiParser();
      final body = _linesOf(parser, [
        'anchor0 unchanged',
        'anchor1 unchanged',
        'anchor2 unchanged',
        'click here now for more info',
      ]);
      final hyperlinks = PaneHyperlinks(
        frameWidth: 54,
        frameHeight: 4,
        links: const [
          PaneHyperlink(
            url: 'https://survives.example/',
            ranges: [PaneHyperlinkRange(row: 0, startCol: 0, endCol: 6)],
          ),
          PaneHyperlink(
            url: 'https://suppressed.example/',
            ranges: [PaneHyperlinkRange(row: 3, startCol: 6, endCol: 9)],
          ),
        ],
        rowFingerprints: {
          0: _fingerprintOf('anchor0 unchanged'),
          1: _fingerprintOf('anchor1 unchanged'),
          2: _fingerprintOf('anchor2 unchanged'),
          // row3 は実際には別の幅で折り返された内容（本文の row3 とは
          // 一致しない。幅不一致が折り返し差として現れたことの模擬）。
          3: _fingerprintOf('click here now for more info and beyond'),
        },
      );

      final result = reconcileHerdrHyperlinks(
        bodyLines: body,
        parser: parser,
        hyperlinks: hyperlinks,
        paneWidth: 54,
      );

      // 整列（k=0）は row0-2 の一致（3票・min(3,4)=3 を満たす）で成立する
      // （窓全体の抑制ではない）。row3 はリンクを持つがフィンガープリント
      // 不一致のため行単位で除外される。row0 のリンクは生き残る。
      expect(identical(result, body), isFalse);
      final linkedRow0 = result[0].segments
          .where((s) => s.url != null)
          .toList();
      expect(linkedRow0, hasLength(1));
      expect(linkedRow0.single.url, 'https://survives.example/');
      final linkedRow3 = result[3].segments
          .where((s) => s.url != null)
          .toList();
      expect(linkedRow3, isEmpty);
    });

    test('整列できない（フィンガープリントが一致しない）窓は全リンク抑制', () {
      final parser = AnsiParser();
      final body = _linesOf(parser, ['completely different content here']);
      final hyperlinks = PaneHyperlinks(
        frameWidth: 80,
        frameHeight: 1,
        links: const [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [PaneHyperlinkRange(row: 0, startCol: 0, endCol: 4)],
          ),
        ],
        rowFingerprints: {0: 'deadbeefdeadbeef'}, // 本文と一致しないハッシュ
      );

      final result = reconcileHerdrHyperlinks(
        bodyLines: body,
        parser: parser,
        hyperlinks: hyperlinks,
        paneWidth: 80,
      );

      expect(identical(result, body), isTrue);
    });

    test('整列成功時、対応する行にリンクが重ね合わされる', () {
      final parser = AnsiParser();
      final body = _linesOf(parser, ['click here for more']);
      final hyperlinks = PaneHyperlinks(
        frameWidth: 80,
        frameHeight: 1,
        links: const [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [PaneHyperlinkRange(row: 0, startCol: 6, endCol: 9)],
          ),
        ],
        rowFingerprints: {0: _fingerprintOf('click here for more')},
      );

      final result = reconcileHerdrHyperlinks(
        bodyLines: body,
        parser: parser,
        hyperlinks: hyperlinks,
        paneWidth: 80,
      );

      expect(identical(result, body), isFalse);
      final linked = result[0].segments.where((s) => s.url != null).toList();
      expect(linked, hasLength(1));
      expect(linked.single.text, 'here');
      expect(linked.single.url, 'https://example.com/');
    });

    test('整列後に行単位でフィンガープリントが不一致ならその行だけ抑制する', () {
      // body 2 行。frame も 2 行で全体としては整列（k=0）が成立するが、
      // リンクのある行 (row 1) のフィンガープリントだけ本文と食い違う
      // ケース（その間に該当行だけ書き換わった想定）。
      final parser = AnsiParser();
      final body = _linesOf(parser, [
        'anchor line unchanged',
        'click here for more',
      ]);
      final hyperlinks = PaneHyperlinks(
        frameWidth: 80,
        frameHeight: 2,
        links: const [
          PaneHyperlink(
            url: 'https://example.com/',
            ranges: [PaneHyperlinkRange(row: 1, startCol: 6, endCol: 9)],
          ),
        ],
        rowFingerprints: {
          0: _fingerprintOf('anchor line unchanged'),
          1: 'deadbeefdeadbeef', // 本文の row1 とは不一致
        },
      );

      final result = reconcileHerdrHyperlinks(
        bodyLines: body,
        parser: parser,
        hyperlinks: hyperlinks,
        paneWidth: 80,
      );

      // row0 は整列の多数決に使われるが、リンクを持たないため見た目上は
      // 変化しない。row1 はリンクを持つがフィンガープリント不一致のため
      // 抑制される。結果として本文全体が無変更（同一インスタンス）。
      expect(identical(result, body), isTrue);
    });
  });
}
