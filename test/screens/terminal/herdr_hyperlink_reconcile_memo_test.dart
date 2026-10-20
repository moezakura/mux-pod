import 'package:flutter_muxpod/screens/terminal/widgets/herdr_hyperlink_reconciler.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_alignment.dart';
import 'package:flutter_muxpod/services/terminal/ansi_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// [HerdrHyperlinkReconcileMemo]（入力が同じなら前回の結果を返す）の
/// 単体テスト。
///
/// `reconcileHerdrHyperlinks` 自体（抑制ルールの適用結果）は
/// `herdr_hyperlink_reconciler_test.dart` で検証済みのため、ここでは
/// メモ化の契約（同じ入力→同一インスタンス、入力が変われば再計算）だけを
/// 対象にする。
void main() {
  String fingerprintOf(String displayText) =>
      HerdrRowFingerprint.rowFingerprint(displayText)!;

  PaneHyperlinks hyperlinksFor(String text, {String url = 'https://a/'}) =>
      PaneHyperlinks(
        frameWidth: 80,
        frameHeight: 1,
        links: [
          PaneHyperlink(
            url: url,
            ranges: const [PaneHyperlinkRange(row: 0, startCol: 6, endCol: 9)],
          ),
        ],
        rowFingerprints: {0: fingerprintOf(text)},
      );

  test(
    '同じ入力（bodyLines identity・hyperlinks 一致・paneWidth・paneHeight）なら同一インスタンスを返す',
    () {
      final parser = AnsiParser();
      final memo = HerdrHyperlinkReconcileMemo();
      final bodyLines = parser.parseLines('click here for more');
      final hyperlinks = hyperlinksFor('click here for more');

      final first = memo.reconcile(
        bodyLines: bodyLines,
        parser: parser,
        hyperlinks: hyperlinks,
        paneWidth: 80,
        paneHeight: 24,
      );
      final second = memo.reconcile(
        bodyLines: bodyLines,
        parser: parser,
        hyperlinks: hyperlinks,
        paneWidth: 80,
        paneHeight: 24,
      );

      expect(identical(first, second), isTrue);
      expect(identical(first[0], second[0]), isTrue);
    },
  );

  test('hyperlinks が値として同一でも別インスタンスなら（paneHyperlinksEquals で）同一結果を返す', () {
    final parser = AnsiParser();
    final memo = HerdrHyperlinkReconcileMemo();
    final bodyLines = parser.parseLines('click here for more');

    final first = memo.reconcile(
      bodyLines: bodyLines,
      parser: parser,
      hyperlinks: hyperlinksFor('click here for more'),
      paneWidth: 80,
      paneHeight: 24,
    );
    // 内容は同じだが別インスタンスの PaneHyperlinks。
    final second = memo.reconcile(
      bodyLines: bodyLines,
      parser: parser,
      hyperlinks: hyperlinksFor('click here for more'),
      paneWidth: 80,
      paneHeight: 24,
    );

    expect(identical(first, second), isTrue);
  });

  test('hyperlinks の url だけ変わると新しい結果を返す', () {
    final parser = AnsiParser();
    final memo = HerdrHyperlinkReconcileMemo();
    final bodyLines = parser.parseLines('click here for more');

    final first = memo.reconcile(
      bodyLines: bodyLines,
      parser: parser,
      hyperlinks: hyperlinksFor('click here for more', url: 'https://a/'),
      paneWidth: 80,
      paneHeight: 24,
    );
    final second = memo.reconcile(
      bodyLines: bodyLines,
      parser: parser,
      hyperlinks: hyperlinksFor('click here for more', url: 'https://b/'),
      paneWidth: 80,
      paneHeight: 24,
    );

    expect(identical(first, second), isFalse);
    expect(
      first[0].segments.where((s) => s.url != null).single.url,
      'https://a/',
    );
    expect(
      second[0].segments.where((s) => s.url != null).single.url,
      'https://b/',
    );
  });

  test('bodyLines が変わる（別インスタンス）と再計算する', () {
    final parser = AnsiParser();
    final memo = HerdrHyperlinkReconcileMemo();
    final hyperlinks = hyperlinksFor('click here for more');

    final first = memo.reconcile(
      bodyLines: parser.parseLines('click here for more'),
      parser: parser,
      hyperlinks: hyperlinks,
      paneWidth: 80,
      paneHeight: 24,
    );
    // 内容は同じ文字列だが、parseLines を再度呼ぶと別インスタンスの
    // List<ParsedLine> になる（行内容自体は前回とキャッシュヒットしうるが、
    // 返す List のインスタンスは新規）。
    final second = memo.reconcile(
      bodyLines: parser.parseLines('click here for more'),
      parser: parser,
      hyperlinks: hyperlinks,
      paneWidth: 80,
      paneHeight: 24,
    );

    // List 自体は新しいインスタンス（bodyLines の identity が変わったため
    // メモがヒットしない）だが、内容としては同じ重ね合わせ結果になる。
    expect(identical(first, second), isFalse);
    expect(
      second[0].segments.where((s) => s.url != null).single.url,
      'https://a/',
    );
  });

  test('paneWidth が変わると再計算する', () {
    final parser = AnsiParser();
    final memo = HerdrHyperlinkReconcileMemo();
    final bodyLines = parser.parseLines('click here for more');
    final hyperlinks = hyperlinksFor('click here for more');

    final first = memo.reconcile(
      bodyLines: bodyLines,
      parser: parser,
      hyperlinks: hyperlinks,
      paneWidth: 80,
      paneHeight: 24,
    );
    final second = memo.reconcile(
      bodyLines: bodyLines,
      parser: parser,
      hyperlinks: hyperlinks,
      paneWidth: 100,
      paneHeight: 24,
    );

    expect(identical(first, second), isFalse);
  });

  test('paneHeight が変わると再計算する', () {
    final parser = AnsiParser();
    final memo = HerdrHyperlinkReconcileMemo();
    final bodyLines = parser.parseLines('click here for more');
    final hyperlinks = hyperlinksFor('click here for more');

    final first = memo.reconcile(
      bodyLines: bodyLines,
      parser: parser,
      hyperlinks: hyperlinks,
      paneWidth: 80,
      paneHeight: 24,
    );
    final second = memo.reconcile(
      bodyLines: bodyLines,
      parser: parser,
      hyperlinks: hyperlinks,
      paneWidth: 80,
      paneHeight: 30,
    );

    expect(identical(first, second), isFalse);
  });
}
