import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/ansi_line_parser.dart';
import 'package:flutter_muxpod/services/terminal/ansi_parser.dart';
import 'package:flutter_muxpod/services/terminal/ansi_sgr_parser.dart';

/// [AnsiLineParser.overlayLineLinks]（herdr OSC 8 ハイパーリンクの
/// 重ね合わせ）のメモ化・既知集合（[AnsiLineParser.contains]）・区間処理
/// （clamp・空区間・重なり）の単体テスト。
///
/// [AnsiParser] 経由（委譲のみ）で呼ぶ。実際の重ね合わせ結果の内容（列変換・
/// 既存 url の優先等）は widget 層のテスト（`herdr_hyperlink_overlay_test.dart`）で
/// 検証済みのため、ここでは契約（メモ化・既知集合・
/// 決定的な区間処理規則）だけを対象にする。
/// [AnsiLineParser] を直接使う（[AnsiParser.lineToTextSpan] 経由だと
/// GoogleFonts のフォント読み込み（非同期・アセット依存）が絡み、ここで
/// 検証したい contains()/メモ化の契約と無関係な失敗要因が混ざるため避ける）。
AnsiLineParser newLineParser() => AnsiLineParser(sgr: AnsiSgrParser());

void main() {
  group('overlayLineLinks のメモ化', () {
    test('同じ line（identical）・同じ ranges の内容なら同一インスタンスを返す', () {
      final parser = AnsiParser();
      final line = parser.parseLines('click here')[0];
      const ranges = [CharLinkRange(start: 6, end: 10, url: 'https://a/')];

      final first = parser.overlayLineLinks(line, ranges: ranges);
      // 内容が同じ別インスタンスの ranges（値の等価性で判定されること）。
      final second = parser.overlayLineLinks(
        line,
        ranges: const [CharLinkRange(start: 6, end: 10, url: 'https://a/')],
      );

      expect(identical(first, second), isTrue);
    });

    test('ranges の内容が変わると新しいインスタンスを返す（直近1件だけ保持）', () {
      final parser = AnsiParser();
      final line = parser.parseLines('click here')[0];

      final first = parser.overlayLineLinks(
        line,
        ranges: const [CharLinkRange(start: 6, end: 10, url: 'https://a/')],
      );
      final second = parser.overlayLineLinks(
        line,
        ranges: const [CharLinkRange(start: 6, end: 10, url: 'https://b/')],
      );

      expect(identical(first, second), isFalse);
      expect(
        second.segments.where((s) => s.url != null).single.url,
        'https://b/',
      );
    });

    test('ranges が空なら line そのものを返す（新しいインスタンスを作らない）', () {
      final parser = AnsiParser();
      final line = parser.parseLines('plain text')[0];

      final result = parser.overlayLineLinks(line, ranges: const []);

      expect(identical(result, line), isTrue);
    });

    test('渡された ranges を呼び出し後に変更しても、メモの判定は汚染されない（防御的コピー）', () {
      // メモが呼び出し側の ranges リストをそのまま（参照で）持っていると、
      // 呼び出し後に呼び出し側がそのリストを別用途で書き換えたとき、
      // 次回呼び出しの _sameRanges 判定が誤ってヒットし、古い行を返して
      // しまう。List.unmodifiable によるコピーでこれを防ぐ。
      final lineParser = newLineParser();
      final line = lineParser.parseLines('click here')[0];

      final ranges = <CharLinkRange>[
        const CharLinkRange(start: 6, end: 10, url: 'https://a/'),
      ];
      final first = lineParser.overlayLineLinks(line, ranges: ranges);
      expect(
        first.segments.where((s) => s.url != null).single.url,
        'https://a/',
      );

      // 呼び出し後に、呼び出し側が同じリストを別の用途で書き換える
      // （バッファ再利用を想定）。
      ranges.clear();
      ranges.add(const CharLinkRange(start: 6, end: 10, url: 'https://b/'));

      // 新しい（別インスタンスの）ranges で、書き換え後の内容と同じ値を
      // 渡す。メモが元の ranges への参照を保持していたら、書き換え後の
      // 内容と一致してしまい、誤って古い行（'https://a/'）を返してしまう。
      final second = lineParser.overlayLineLinks(
        line,
        ranges: [const CharLinkRange(start: 6, end: 10, url: 'https://b/')],
      );

      expect(
        second.segments.where((s) => s.url != null).single.url,
        'https://b/',
      );
    });
  });

  group('contains() の意味（直近の parseLines が返した行か）', () {
    test('overlayLineLinks が生成した行は contains() が true を返す', () {
      final lineParser = newLineParser();
      final line = lineParser.parseLines('click here')[0];
      final overlaid = lineParser.overlayLineLinks(
        line,
        ranges: const [CharLinkRange(start: 6, end: 10, url: 'https://a/')],
      );

      expect(overlaid, isNot(same(line)));
      expect(lineParser.contains(overlaid), isTrue);
    });

    test('元の行が次の parseLines でキャッシュから外れたら、重ねた行も既知でなくなる', () {
      final lineParser = newLineParser();
      final line = lineParser.parseLines('click here')[0];
      final overlaid = lineParser.overlayLineLinks(
        line,
        ranges: const [CharLinkRange(start: 6, end: 10, url: 'https://a/')],
      );

      // 事前に既知の状態であることを確認する。
      expect(lineParser.contains(overlaid), isTrue);

      // 全く異なる内容で parseLines を呼び、行キャッシュを入れ替える
      // （元の 'click here' 行はどのキーにも一致せず _lineCache から外れる）。
      lineParser.parseLines('completely different content that never repeats');

      // 重ねた行は、元の行が直近の行キャッシュに無くなったため既知でなくなる。
      expect(lineParser.contains(overlaid), isFalse);
    });

    test('overlayLineLinks の戻り値を再度 line として渡すと AssertionError になる（2段目の禁止）', () {
      // contains() は「元の行 or その直近1段の重ね合わせ結果」までしか
      // 既知と判定しない。overlayLineLinks の戻り値を再度入力に渡すと、
      // 2段目の結果が _overlays に元の行以外のキーで登録されてしまい、
      // contains() の1段限定の判定から漏れて lineToTextSpan の assert を
      // 壊す。これを防ぐため、overlayLineLinks 自身の入力検証は
      // 「parseLines が返したインスタンスそのもの」だけを受け付ける
      // （contains() より厳しい）。
      final lineParser = newLineParser();
      final line = lineParser.parseLines('click here')[0];
      final overlaid = lineParser.overlayLineLinks(
        line,
        ranges: const [CharLinkRange(start: 6, end: 10, url: 'https://a/')],
      );

      expect(
        () => lineParser.overlayLineLinks(
          overlaid,
          ranges: const [CharLinkRange(start: 0, end: 4, url: 'https://b/')],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('overlayLineLinks の区間処理（clamp・空区間・重なり）', () {
    test('start >= end（clamp 後を含む）の区間は捨てる', () {
      final parser = AnsiParser();
      final line = parser.parseLines('abcdef')[0];

      // end が start 以下（無効な区間）は無視され、有効な区間だけが残る。
      final result = parser.overlayLineLinks(
        line,
        ranges: const [
          CharLinkRange(start: 3, end: 3, url: 'https://empty/'),
          CharLinkRange(start: 5, end: 2, url: 'https://backwards/'),
          CharLinkRange(start: 0, end: 2, url: 'https://valid/'),
        ],
      );

      final linked = result.segments.where((s) => s.url != null).toList();
      expect(linked, hasLength(1));
      expect(linked.single.text, 'ab');
      expect(linked.single.url, 'https://valid/');
    });

    test('end が行の文字列長を超える区間は行末で clamp される', () {
      final parser = AnsiParser();
      final line = parser.parseLines('abc')[0];

      final result = parser.overlayLineLinks(
        line,
        ranges: const [CharLinkRange(start: 0, end: 999, url: 'https://tail/')],
      );

      expect(result.segments, hasLength(1));
      expect(result.segments.single.text, 'abc');
      expect(result.segments.single.url, 'https://tail/');
    });

    test('区間が重なる場合は ranges に先に現れたものを優先する（決定的規則）', () {
      final parser = AnsiParser();
      final line = parser.parseLines('abcdef')[0];

      final result = parser.overlayLineLinks(
        line,
        ranges: const [
          CharLinkRange(start: 0, end: 4, url: 'https://first/'),
          CharLinkRange(start: 2, end: 6, url: 'https://second/'),
        ],
      );

      // 0-3 は first、4-5 は first に取られていない残りとして second。
      final linked = result.segments.where((s) => s.url != null).toList();
      expect(linked.map((s) => s.text).toList(), ['abcd', 'ef']);
      expect(linked[0].url, 'https://first/');
      expect(linked[1].url, 'https://second/');
    });

    test('既存 url のある位置は上書きしない（防御的確認・overlay と同じく既存 url を優先する規則）', () {
      final parser = AnsiParser();
      final line = parser.parseLines(
        '\x1b]8;;https://existing/\x07linked\x1b]8;;\x07',
      )[0];
      expect(line.segments.single.url, 'https://existing/');

      final result = parser.overlayLineLinks(
        line,
        ranges: const [CharLinkRange(start: 0, end: 6, url: 'https://new/')],
      );

      // 変化なし＝同一インスタンス（既存 url を上書きしなかった）。
      expect(identical(result, line), isTrue);
      expect(result.segments.single.url, 'https://existing/');
    });
  });
}
