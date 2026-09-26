import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/ansi_models.dart';
import 'package:flutter_muxpod/services/terminal/ansi_span_renderer.dart';
import 'package:flutter_muxpod/theme/terminal_colors.dart';

/// リンク（OSC 8）TextSpan 描画の単体テスト。
///
/// - 装飾合成: `TextDecoration.combine` リスト追加方式（SGR 装飾と合成し、
///   上書きしない — critic R7）
/// - リンク色の pin: 適用位置は `resolvePaintColors` 後・dim 前
///   （SGR 前景色未指定時のみ `TerminalColors.brightBlue`）
/// - resolver あり構築のスパンキャッシュ迂回（recognizer をキャッシュに
///   混入させない — 設計 D5）
/// - 同一 URL recognizer 共有（M4）・キャレット分割時の url 引き継ぎ・
///   blink 両相（H2）
///
/// 注: レンダラ単体のため recognizer のライフサイクル（生成/dispose）は
/// 呼び出し側 State の責務であり、本テストでは dispose しない（単体テスト
/// 内で生成した recognizer はテストプロセス終了とともに回収される）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const font = 'JetBrains Mono';
  const fontSize = 14.0;

  TextSpan leafOf(TextSpan span) => span.children!.single as TextSpan;

  group('装飾合成 (critic R7)', () {
    test('SGR underline + lineThrough のリンクは両装飾とリンク下線が合成される', () {
      final renderer = AnsiSpanRenderer();
      final span = renderer.toTextSpan(
        const [
          AnsiSegment(
            'link',
            AnsiStyle(underline: true, strikethrough: true),
            url: 'https://e.com',
          ),
        ],
        fontSize: fontSize,
        fontFamily: font,
      );
      final leaf = leafOf(span);
      // combine リスト「追加」方式: SGR 両装飾 + リンク下線（上書きではない）
      expect(
        leaf.style!.decoration,
        TextDecoration.combine([
          TextDecoration.underline,
          TextDecoration.lineThrough,
          TextDecoration.underline,
        ]),
      );
      // lineThrough が消えていない（リンク下線による上書きが起きていない）
      expect(leaf.style!.decoration, isNot(TextDecoration.underline));
    });

    test('リンク外のセグメントにリンク下線・recognizer は付かない', () {
      final renderer = AnsiSpanRenderer();
      final span = renderer.toTextSpan(
        const [AnsiSegment('plain', AnsiStyle())],
        fontSize: fontSize,
        fontFamily: font,
      );
      final leaf = leafOf(span);
      expect(leaf.style!.decoration, TextDecoration.none);
      expect(leaf.recognizer, isNull);
    });
  });

  group('リンク色の pin (resolvePaintColors 後・dim 前)', () {
    test('SGR 無色のリンクは brightBlue', () {
      final renderer = AnsiSpanRenderer();
      final span = renderer.toTextSpan(
        const [AnsiSegment('link', AnsiStyle(), url: 'https://e.com')],
        fontSize: fontSize,
        fontFamily: font,
      );
      expect(leafOf(span).style!.color, TerminalColors.brightBlue);
    });

    test('SGR 色付きリンクは SGR 色を尊重する', () {
      final renderer = AnsiSpanRenderer();
      const sgrRed = Color(0xFFCD3131);
      final span = renderer.toTextSpan(
        const [
          AnsiSegment(
            'link',
            AnsiStyle(foreground: sgrRed),
            url: 'https://e.com',
          ),
        ],
        fontSize: fontSize,
        fontFamily: font,
      );
      expect(leafOf(span).style!.color, sgrRed);
    });

    test('dim + リンクはリンク色に dim の alpha が掛かる (pin 順序の固定)', () {
      final renderer = AnsiSpanRenderer();
      final span = renderer.toTextSpan(
        const [AnsiSegment('link', AnsiStyle(dim: true), url: 'https://e.com')],
        fontSize: fontSize,
        fontFamily: font,
      );
      expect(
        leafOf(span).style!.color,
        TerminalColors.brightBlue.withValues(alpha: 0.5),
      );
    });

    test('リンク外は既存色のまま (defaultForeground)', () {
      final renderer = AnsiSpanRenderer();
      final span = renderer.toTextSpan(
        const [AnsiSegment('plain', AnsiStyle())],
        fontSize: fontSize,
        fontFamily: font,
      );
      expect(leafOf(span).style!.color, const Color(0xFFD4D4D4));
    });

    test('背景色付き行上のリンクは fg=リンク色・bg=行背景で視認性を保つ', () {
      final renderer = AnsiSpanRenderer();
      const bg = Color(0xFF123456);
      final span = renderer.toTextSpan(
        const [
          AnsiSegment('link', AnsiStyle(background: bg), url: 'https://e.com'),
        ],
        fontSize: fontSize,
        fontFamily: font,
      );
      final leaf = leafOf(span);
      expect(leaf.style!.color, TerminalColors.brightBlue);
      expect(leaf.style!.backgroundColor, bg);
    });

    test('inverse 行上のリンクもリンク色が適用される (pin 位置どおり)', () {
      final renderer = AnsiSpanRenderer();
      final span = renderer.toTextSpan(
        const [AnsiSegment('link', AnsiStyle(inverse: true), url: 'u')],
        fontSize: fontSize,
        fontFamily: font,
      );
      final leaf = leafOf(span);
      // inverse で前背景を入れ替えた後・リンク色が適用される
      expect(leaf.style!.color, TerminalColors.brightBlue);
      expect(leaf.style!.backgroundColor, const Color(0xFFD4D4D4));
    });
  });

  group('resolver とスパンキャッシュ (設計 D5)', () {
    test('resolver ありの 2 回構築は非 identical (キャッシュ迂回)', () {
      final renderer = AnsiSpanRenderer();
      const line = ParsedLine(
        segments: [AnsiSegment('link', AnsiStyle(), url: 'u')],
        endStyle: AnsiStyle.defaultStyle,
      );
      final s1 = renderer.lineToTextSpan(
        line,
        fontSize: fontSize,
        fontFamily: font,
        linkTapResolver: (url) => TapGestureRecognizer(),
      );
      final s2 = renderer.lineToTextSpan(
        line,
        fontSize: fontSize,
        fontFamily: font,
        linkTapResolver: (url) => TapGestureRecognizer(),
      );
      expect(identical(s1, s2), isFalse);
      expect(leafOf(s1).recognizer, isNotNull);
    });

    test('resolver なしは identical (既存キャッシュ規約の回帰)・recognizer 無し', () {
      final renderer = AnsiSpanRenderer();
      const line = ParsedLine(
        segments: [AnsiSegment('link', AnsiStyle(), url: 'u')],
        endStyle: AnsiStyle.defaultStyle,
      );
      final s1 = renderer.lineToTextSpan(
        line,
        fontSize: fontSize,
        fontFamily: font,
      );
      final s2 = renderer.lineToTextSpan(
        line,
        fontSize: fontSize,
        fontFamily: font,
      );
      expect(identical(s1, s2), isTrue);
      // キャッシュ済み span に recognizer が入らないこと
      expect(leafOf(s1).recognizer, isNull);
    });

    test('resolver あり構築はキャッシュを書き込まない (後続の resolver なし構築は新規)', () {
      final renderer = AnsiSpanRenderer();
      const line = ParsedLine(
        segments: [AnsiSegment('link', AnsiStyle(), url: 'u')],
        endStyle: AnsiStyle.defaultStyle,
      );
      final withResolver = renderer.lineToTextSpan(
        line,
        fontSize: fontSize,
        fontFamily: font,
        linkTapResolver: (url) => TapGestureRecognizer(),
      );
      final without = renderer.lineToTextSpan(
        line,
        fontSize: fontSize,
        fontFamily: font,
      );
      // withResolver がキャッシュに書き込んでいたら identical になるはず
      expect(identical(withResolver, without), isFalse);
      expect(leafOf(without).recognizer, isNull);
    });
  });

  group('同一 URL の recognizer 共有 (M4)', () {
    test('同一 URL の複数セグメントは同一 recognizer を共有する', () {
      final renderer = AnsiSpanRenderer();
      final recognizers = <String, TapGestureRecognizer>{};
      final span = renderer.toTextSpan(
        const [
          AnsiSegment('a', AnsiStyle(), url: 'u'),
          AnsiSegment('b', AnsiStyle(), url: 'u'),
          AnsiSegment('c', AnsiStyle(), url: 'other'),
        ],
        fontSize: fontSize,
        fontFamily: font,
        linkTapResolver: (url) =>
            recognizers.putIfAbsent(url, () => TapGestureRecognizer()),
      );
      final leaves = span.children!.cast<TextSpan>().toList();
      expect(leaves.length, 3);
      expect(identical(leaves[0].recognizer, leaves[1].recognizer), isTrue);
      expect(identical(leaves[0].recognizer, leaves[2].recognizer), isFalse);
      expect(leaves[0].recognizer, recognizers['u']);
    });

    test('キャレット分割で 2 断片に分かれた同一 URL も同一 recognizer を共有する', () {
      final renderer = AnsiSpanRenderer();
      final recognizers = <String, TapGestureRecognizer>{};
      const line = ParsedLine(
        segments: [AnsiSegment('linktext', AnsiStyle(), url: 'u')],
        endStyle: AnsiStyle.defaultStyle,
      );
      final span = renderer.lineToTextSpanWithCaret(
        line,
        fontSize: fontSize,
        fontFamily: font,
        caretCharOffset: 4,
        padColumns: 0,
        caret: const WidgetSpan(child: SizedBox(width: 2, height: 2)),
        linkTapResolver: (url) =>
            recognizers.putIfAbsent(url, () => TapGestureRecognizer()),
      );
      final parts = span.children!.toList();
      expect(parts.length, 3);
      final frag1 = parts[0] as TextSpan;
      final frag2 = parts[2] as TextSpan;
      expect(frag1.text, 'link');
      expect(frag2.text, 'text');
      expect(identical(frag1.recognizer, frag2.recognizer), isTrue);
      expect(frag1.recognizer, recognizers['u']);
    });
  });

  group('キャレット分割の url 引き継ぎと blink 両相 (H2)', () {
    test('キャレット分割断片の両方に url が引き継がれる (url 落ち修正)', () {
      final renderer = AnsiSpanRenderer();
      final invoked = <String>[];
      const line = ParsedLine(
        segments: [AnsiSegment('linktext', AnsiStyle(), url: 'u')],
        endStyle: AnsiStyle.defaultStyle,
      );
      renderer.lineToTextSpanWithCaret(
        line,
        fontSize: fontSize,
        fontFamily: font,
        caretCharOffset: 4,
        padColumns: 0,
        caret: const WidgetSpan(child: SizedBox(width: 2, height: 2)),
        linkTapResolver: (url) {
          invoked.add(url);
          return TapGestureRecognizer();
        },
      );
      // resolver が両断片とも正しい url ('u') で呼ばれた = url が落ちていない
      expect(invoked, ['u', 'u']);
    });

    test('blink off 相 (caret == null) も resolver が透過され recognizer 付きになる', () {
      final renderer = AnsiSpanRenderer();
      const line = ParsedLine(
        segments: [AnsiSegment('link', AnsiStyle(), url: 'u')],
        endStyle: AnsiStyle.defaultStyle,
      );
      final off1 = renderer.lineToTextSpanWithCaret(
        line,
        fontSize: fontSize,
        fontFamily: font,
        caretCharOffset: 0,
        padColumns: 0,
        caret: null,
        linkTapResolver: (url) => TapGestureRecognizer(),
      );
      final off2 = renderer.lineToTextSpanWithCaret(
        line,
        fontSize: fontSize,
        fontFamily: font,
        caretCharOffset: 0,
        padColumns: 0,
        caret: null,
        linkTapResolver: (url) => TapGestureRecognizer(),
      );
      // off 相でも recognizer 付き（早期 return の resolver 透過）
      expect(leafOf(off1).recognizer, isNotNull);
      // キャッシュ経路を通っていない（非 identical）
      expect(identical(off1, off2), isFalse);
    });
  });
}
