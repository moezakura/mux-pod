import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/ansi_parser.dart';

/// 責務ベース再設計（refactor-p1）で追加した規約のテスト。
///
/// ① [AnsiParser.parse] と [AnsiParser.parseLines] の経路分離の意味論
///    （parse = 正規化なし入力全体スキャン、parseLines = CRLF/CR 正規化 + 行分割）
/// ② 行パースキャッシュ: 同一行の再 parseLines で返る ParsedLine が
///    [identical] であること（スパンキャッシュの前提）
/// ③ スパンキャッシュ: 同一 ParsedLine への lineToTextSpan 2 回目が
///    同一 [TextSpan] インスタンスを返すこと
/// ④ ファサード委譲の assert: LineParser が生成していない ParsedLine は
///    AssertionError になること（規約違反の早期検出）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AnsiParser newParser() => AnsiParser(
    defaultForeground: const Color(0xFFD4D4D4),
    defaultBackground: const Color(0xFF1E1E1E),
  );

  group('経路分離: parse（正規化なし）と parseLines（正規化あり）', () {
    test('parse は CR のみを正規化せずテキストのまま残す', () {
      final parser = newParser();
      // 単独 CR は parseLines では除去されるが、parse ではテキストに残る
      final segments = parser.parse('line1\rline2');
      expect(segments.length, 1);
      expect(segments[0].text, 'line1\rline2');
    });

    test('parse は CRLF を正規化せずテキストのまま残す', () {
      final parser = newParser();
      final segments = parser.parse('a\r\nb');
      expect(segments.length, 1);
      expect(segments[0].text, 'a\r\nb');
    });

    test('parse は改行混在でも行分割せず1ストリームで走査する', () {
      final parser = newParser();
      // SGR は解釈されるが、CR/LF はどれもテキストの一部として残る
      final segments = parser.parse('a\nb\rc\r\nd\x1b[31mRED');
      expect(segments.length, 2);
      expect(segments[0].text, 'a\nb\rc\r\nd');
      expect(segments[0].style, AnsiStyle.defaultStyle);
      expect(segments[1].text, 'RED');
      expect(segments[1].style.foreground, const Color(0xFFCD3131));
    });

    test('parseLines は CRLF を LF に正規化して行分割する', () {
      final parser = newParser();
      final lines = parser.parseLines('a\r\nb\r\nc');
      expect(lines.length, 3);
      expect(lines[0].segments.single.text, 'a');
      expect(lines[1].segments.single.text, 'b');
      expect(lines[2].segments.single.text, 'c');
    });

    test('parseLines は単独 CR を除去する', () {
      final parser = newParser();
      final lines = parser.parseLines('line1\rline2');
      expect(lines.length, 1);
      expect(lines[0].segments.single.text, 'line1line2');
    });

    test('同じ入力で parse と parseLines のセグメント内容が異なることを明示', () {
      final parser = newParser();
      const input = 'a\r\nb\rc';
      final parseSegments = parser.parse(input);
      final parsedLines = parser.parseLines(input);
      // parse: 1 セグメントに CR が残る
      expect(parseSegments.length, 1);
      expect(parseSegments[0].text, 'a\r\nb\rc');
      // parseLines: 正規化後は 2 行（'a', 'bc'）
      expect(parsedLines.length, 2);
      expect(parsedLines[0].segments.single.text, 'a');
      expect(parsedLines[1].segments.single.text, 'bc');
    });
  });

  group('行パースキャッシュ同一性（スパンキャッシュの前提）', () {
    test('同一行の再 parseLines で返る ParsedLine が identical', () {
      final parser = newParser();
      final first = parser.parseLines('l0\nl1\nl2');
      final second = parser.parseLines('l0\nl1\nl2');
      expect(second.length, first.length);
      for (var i = 0; i < first.length; i++) {
        expect(
          identical(first[i], second[i]),
          isTrue,
          reason: 'line $i: 同一内容の再パースは同一インスタンスを返すこと',
        );
      }
    });

    test('位置が変わっても同一 (開始スタイル, テキスト) は同一インスタンス', () {
      final parser = newParser();
      final first = parser.parseLines('l0\nl1\nl2');
      // 先頭行が消えて全行が上にシフトしても、内容が同じ行は再利用される
      final second = parser.parseLines('l1\nl2\nl3');
      expect(identical(first[1], second[0]), isTrue);
      expect(identical(first[2], second[1]), isTrue);
      expect(identical(first[0], second[2]), isFalse);
    });
  });

  group('スパンキャッシュ同一性', () {
    test('同一 ParsedLine への lineToTextSpan 2 回目が同一 TextSpan', () {
      final parser = newParser();
      final lines = parser.parseLines('hello \x1b[32mworld');
      final span1 = parser.lineToTextSpan(
        lines[0],
        fontSize: 14,
        fontFamily: 'JetBrains Mono',
      );
      final span2 = parser.lineToTextSpan(
        lines[0],
        fontSize: 14,
        fontFamily: 'JetBrains Mono',
      );
      expect(identical(span1, span2), isTrue);
    });

    test('フォントサイズが違えば同一 TextSpan を返さない', () {
      final parser = newParser();
      final lines = parser.parseLines('x');
      final span1 = parser.lineToTextSpan(
        lines[0],
        fontSize: 14,
        fontFamily: 'JetBrains Mono',
      );
      final span2 = parser.lineToTextSpan(
        lines[0],
        fontSize: 16,
        fontFamily: 'JetBrains Mono',
      );
      expect(identical(span1, span2), isFalse);
    });
  });

  group('ファサード委譲の assert(identical) 規約', () {
    test('LineParser が生成していない ParsedLine は AssertionError', () {
      final parser = newParser();
      // キャッシュ外（parseLines 経由で取得していない）インスタンス
      final foreign = const ParsedLine(
        segments: [],
        endStyle: AnsiStyle.defaultStyle,
      );
      expect(
        () => parser.lineToTextSpan(
          foreign,
          fontSize: 14,
          fontFamily: 'JetBrains Mono',
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => parser.effectiveLineBackgroundColor(foreign),
        throwsA(isA<AssertionError>()),
      );
    });

    test('parseLines が返した ParsedLine は assert を通過する', () {
      final parser = newParser();
      final lines = parser.parseLines('a');
      // 例外なく返ること（throwsA でないこと）を検証
      expect(
        () => parser.effectiveLineBackgroundColor(lines[0]),
        returnsNormally,
      );
      expect(
        () => parser.lineToTextSpan(
          lines[0],
          fontSize: 14,
          fontFamily: 'JetBrains Mono',
        ),
        returnsNormally,
      );
    });
  });
}
