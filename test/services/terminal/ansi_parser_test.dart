import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/ansi_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnsiParser', () {
    late AnsiParser parser;

    setUp(() {
      parser = AnsiParser(
        defaultForeground: const Color(0xFFD4D4D4),
        defaultBackground: const Color(0xFF1E1E1E),
      );
    });

    test('parse handles reverse video (ESC[7m)', () {
      const input = '\x1b[7mReversed\x1b[27mNormal';
      final segments = parser.parse(input);

      expect(segments.length, 2);
      expect(segments[0].text, 'Reversed');
      expect(segments[0].style.inverse, isTrue);
      expect(segments[1].text, 'Normal');
      expect(segments[1].style.inverse, isFalse);
    });

    test('toTextSpan swaps colors when inverse is true', () {
      // Setup style with explicit colors
      const input = '\x1b[31;42;7mReversed\x1b[0m'; // Red fg, Green bg, Inverse
      final segments = parser.parse(input);

      final textSpan = parser.toTextSpan(
        segments,
        fontSize: 14,
        fontFamily: 'HackGen Console',
      );

      // Expected: FG should be Green (originally BG), BG should be Red (originally FG)
      // Original: 31 (Red) -> 0xFFCD3131, 42 (Green) -> 0xFF0DBC79

      final span = textSpan.children![0] as TextSpan;
      // In toTextSpan:
      // fg = Red, bg = Green
      // inverse -> fg = Green, bg = Red

      expect(span.style!.color, const Color(0xFF0DBC79)); // Green
      expect(span.style!.backgroundColor, const Color(0xFFCD3131)); // Red
    });

    test('toTextSpan handles default colors with inverse', () {
      const input = '\x1b[7mReversed\x1b[0m';
      final segments = parser.parse(input);

      final textSpan = parser.toTextSpan(
        segments,
        fontSize: 14,
        fontFamily: 'HackGen Console',
      );

      final span = textSpan.children![0] as TextSpan;

      // Default FG: 0xFFD4D4D4
      // Default BG: 0xFF1E1E1E
      // Inverse -> FG: 0xFF1E1E1E, BG: 0xFFD4D4D4

      expect(span.style!.color, const Color(0xFF1E1E1E));
      expect(span.style!.backgroundColor, const Color(0xFFD4D4D4));
    });

    test(
      'toTextSpan sets backgroundColor even if it matches defaultBackground when inverse is true',
      () {
        // 30 is Black (0xFF000000), 7 is Inverse
        // Default BG is 0xFF1E1E1E. If we set FG to 0xFF1E1E1E and invert,
        // the new BG will be 0xFF1E1E1E which matches defaultBackground.

        parser = AnsiParser(
          defaultForeground: const Color(0xFF000000),
          defaultBackground: const Color(0xFF1E1E1E),
        );

        const input = '\x1b[7mInverse\x1b[0m';
        final segments = parser.parse(input);
        final textSpan = parser.toTextSpan(
          segments,
          fontSize: 14,
          fontFamily: 'HackGen Console',
        );

        final span = textSpan.children![0] as TextSpan;

        // Swapped: FG -> 0xFF1E1E1E, BG -> 0xFF000000
        expect(span.style!.backgroundColor, const Color(0xFF000000));

        // Test case where BG matches defaultBackground after swap
        // Original FG = defaultBackground, then Inverse
        final styleWithDefaultBGAsFG = const AnsiStyle(
          inverse: true,
        ).copyWith(foreground: const Color(0xFF1E1E1E));
        final segment = AnsiSegment('text', styleWithDefaultBGAsFG);
        final spanWithDefaultBG = parser.toTextSpan(
          [segment],
          fontSize: 14,
          fontFamily: 'HackGen Console',
        );

        final span2 = spanWithDefaultBG.children![0] as TextSpan;
        // fg (swapped) = defaultBackground (0xFF1E1E1E)
        // bg (swapped) = foreground (0xFF1E1E1E)
        // Since inverse is true, it should NOT be null.
        expect(span2.style!.backgroundColor, const Color(0xFF1E1E1E));
      },
    );

    test('parseLines handles reverse video correctly across lines', () {
      const input = '\x1b[7mLine1\nLine2\x1b[27m';
      final parsedLines = parser.parseLines(input);

      expect(parsedLines.length, 2);

      // Line 1
      expect(parsedLines[0].segments[0].text, 'Line1');
      expect(parsedLines[0].segments[0].style.inverse, isTrue);
      expect(parsedLines[0].endStyle.inverse, isTrue); // Should carry over

      // Line 2
      expect(parsedLines[1].segments[0].text, 'Line2');
      expect(parsedLines[1].segments[0].style.inverse, isTrue);
      expect(parsedLines[1].endStyle.inverse, isFalse);
    });

    test('parseLines normalizes CRLF to LF (PTY 経由の改行)', () {
      // PTY の出力変換（ONLCR）で \r\n が混入しても、空行として扱われないこと
      const input = 'line1\r\nline2\r\nline3';
      final parsedLines = parser.parseLines(input);

      expect(parsedLines.length, 3);
      expect(parsedLines[0].segments[0].text, 'line1');
      expect(parsedLines[1].segments[0].text, 'line2');
      expect(parsedLines[2].segments[0].text, 'line3');
    });

    test('parseLines strips lone CR (行末の \\r)', () {
      const input = 'line1\rline2';
      final parsedLines = parser.parseLines(input);

      // \r は改行とみなさず除去され、1行としてパースされる
      expect(parsedLines.length, 1);
      expect(parsedLines[0].segments[0].text, 'line1line2');
    });

    test('handles inverse space (cursor representation)', () {
      const input = 'Prompt\x1b[7m \x1b[27m'; // ' ' is the cursor
      final segments = parser.parse(input);

      expect(segments.length, 2);
      expect(segments[1].text, ' ');
      expect(segments[1].style.inverse, isTrue);

      final textSpan = parser.toTextSpan(
        segments,
        fontSize: 14,
        fontFamily: 'HackGen Console',
      );

      final cursorSpan = textSpan.children![1] as TextSpan;
      // Should replace space with non-breaking space
      expect(cursorSpan.text, '\u00A0');

      expect(cursorSpan.style!.backgroundColor, isNotNull);
      // Default BG is 0xFF1E1E1E, Default FG is 0xFFD4D4D4
      // Swapped: BG should be 0xFFD4D4D4
      expect(cursorSpan.style!.backgroundColor, const Color(0xFFD4D4D4));
    });

    group('effectiveLineBackgroundColor', () {
      test('returns null for plain line (default background)', () {
        final lines = parser.parseLines('plain text');
        expect(parser.effectiveLineBackgroundColor(lines[0]), isNull);
      });

      test('returns null when line ends with reset (trailing default)', () {
        // 青背景 44 = standardColors[4] = 0xFF2472C8
        // 末尾リセット（tmux 合成 \x1b[49m）により endStyle=default のため、
        // テキストのみ span 描画され、余白は default（S4 型・ユーザー承認仕様）
        final lines = parser.parseLines('\x1b[44mCOLORED-TEXT\x1b[49m');
        expect(parser.effectiveLineBackgroundColor(lines[0]), isNull);
      });

      test('returns endStyle background for empty line with SGR only', () {
        // 緑背景 42 のみでテキスト無しの空行
        final lines = parser.parseLines('\x1b[42m');
        expect(lines[0].segments, isEmpty);
        expect(
          parser.effectiveLineBackgroundColor(lines[0]),
          const Color(0xFF0DBC79),
        );
      });

      test('returns inverse-swapped foreground for inverse line', () {
        // 反転時は有効背景 = 元の前景（デフォルト前景）
        final lines = parser.parseLines('\x1b[7mreversed');
        expect(
          parser.effectiveLineBackgroundColor(lines[0]),
          const Color(0xFFD4D4D4), // defaultForeground
        );
      });

      test(
        'returns null for trailing default text after color (endStyle semantics)',
        () {
          // 前半は赤背景、後半はリセット済み → 有効背景は default → null
          // （旧実装前提の「最終セグメント基準」から endStyle 基準へ意味を明確化）
          final lines = parser.parseLines('\x1b[41mRED\x1b[49m tail');
          expect(parser.effectiveLineBackgroundColor(lines[0]), isNull);
        },
      );

      // ==== C-001: endStyle 基準 + ハイブリッド例外（fix-plan §4.1 / regression §4.1） ====

      test('S1型: 途中で色開始＋末尾リセットは null（余白は default）', () {
        // PREFIX-DEFAULT \x1b[44m BLUE-TAIL\x1b[49m
        // 最終セグメント " BLUE-TAIL" は末尾非空白 → endStyle=default → null
        final lines = parser.parseLines(
          'PREFIX-DEFAULT \x1b[44m BLUE-TAIL\x1b[49m',
        );
        expect(parser.effectiveLineBackgroundColor(lines[0]), isNull);
      });

      test('S3型: 複数色＋末尾リセットは null（セル単位は span 描画が担当）', () {
        final lines = parser.parseLines('\x1b[41mRED\x1b[42mGREEN\x1b[49m');
        expect(parser.effectiveLineBackgroundColor(lines[0]), isNull);
      });

      test('S4型: 単色＋末尾リセットは null（ユーザー承認仕様: 余白 default）', () {
        final lines = parser.parseLines('\x1b[42mALL-GREEN\x1b[49m');
        expect(parser.effectiveLineBackgroundColor(lines[0]), isNull);
      });

      test('endStyle 色残り（末尾リセット無し）は行末まで色を塗る', () {
        // P4: 末尾リセット無し → endStyle=blue → 全幅レイヤー blue
        final lines = parser.parseLines('\x1b[44mFULL-COLOR');
        expect(
          parser.effectiveLineBackgroundColor(lines[0]),
          const Color(0xFF2472C8),
        );
      });

      test('HYP-4型: 途中デフォルト + 末尾リセット無しは endStyle=色', () {
        // P5: 途中 "plain " は opaque span で default に塗られる
        final lines = parser.parseLines('plain \x1b[44m tail');
        expect(
          parser.effectiveLineBackgroundColor(lines[0]),
          const Color(0xFF2472C8),
        );
      });

      test('R10型: 末尾で色SGRのみ・後続テキスト無しは endStyle=色', () {
        // P6: 'text \x1b[44m' → endStyle=blue。「text 」span は opaque で default のまま
        final lines = parser.parseLines('text \x1b[44m');
        expect(
          parser.effectiveLineBackgroundColor(lines[0]),
          const Color(0xFF2472C8),
        );
      });

      test('inverse＋リセットは null（余白の偽塗りが解消）', () {
        // P7: \x1b[7mrev\x1b[27m → endStyle=default → null
        final lines = parser.parseLines('\x1b[7mrev\x1b[27m');
        expect(parser.effectiveLineBackgroundColor(lines[0]), isNull);
      });

      test('EV-LOG-006型: 実色スペース行（背景付き末尾空白）は最後のセグメント色', () {
        // P8: \x1b[44mCOLORED-TEXT + 実スペース100 + \x1b[49m → 全幅レイヤー blue
        // （PR#98 の行末色埋め機能維持。実機では span 末尾空白の背景が描画されない）
        final lines = parser.parseLines(
          '\x1b[44mCOLORED-TEXT${' ' * 100}\x1b[49m',
        );
        expect(
          parser.effectiveLineBackgroundColor(lines[0]),
          const Color(0xFF2472C8),
        );
      });

      test('例外ガード: 色付き+末尾1実スペース+リセットは最後のセグメント色', () {
        // P9: PR#98 互換ロックイン（旧実装と同一条件の部分集合）
        final lines = parser.parseLines('\x1b[41mRED \x1b[49m');
        expect(
          parser.effectiveLineBackgroundColor(lines[0]),
          const Color(0xFFCD3131),
        );
      });

      test('例外不発: 末尾デフォルトスペースでは例外が誤発動しない', () {
        // P10: 最後のセグメント " " はデフォルト背景 → 例外なし → endStyle=default → null
        final lines = parser.parseLines('\x1b[42mA \x1b[49m ');
        expect(parser.effectiveLineBackgroundColor(lines[0]), isNull);
      });
    });

    group('toTextSpan opaque background', () {
      test('default 背景セグメントも opaque で backgroundColor が設定される', () {
        // opaque 化: 無色セグメントは旧挙動（null）から defaultBackground の不透明塗りに
        final lines = parser.parseLines('plain');
        final span = parser.lineToTextSpan(
          lines[0],
          fontSize: 14,
          fontFamily: 'HackGen Console',
        );
        final child = span.children![0] as TextSpan;
        expect(child.style!.backgroundColor, const Color(0xFF1E1E1E));
      });
    });
  });
}
