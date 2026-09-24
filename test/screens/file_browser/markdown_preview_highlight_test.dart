import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/file_browser/markdown_preview_screen.dart';
import 'package:flutter_muxpod/theme/markdown_highlighter.dart';
import '../../helpers/fake_sftp_client.dart';
import 'helpers/markdown_preview_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('MarkdownPreviewScreen - 言語別ハイライト（C-2・M-3）', () {
    testWidgets('言語指定フェンスドコードはハイライト（色付きスパン）で表示する', (tester) async {
      await pumpScreen(
        tester,
        sftpClient: FakeSftpClient(
          contentsByPath: {
            '/home/user/docs/readme.md': bytes(
              '# Code\n\n```dart\nvoid main() { print(42); }\n```\n',
            ),
          },
        ),
      );
      expect(find.byType(MarkdownCodeBlock), findsOneWidget);
      final codeBlock = find.byType(MarkdownCodeBlock);

      // ブロック内の RichText に色指定されたテキストスパンがある（ハイライト）
      final rich = tester.widget<RichText>(
        find.descendant(of: codeBlock, matching: find.byType(RichText)),
      );
      expect(rich.text, isA<TextSpan>());
      expect(
        _hasColoredTextSpan(rich.text),
        isTrue,
        reason: 'keyword/number/string 等に DesignColors 由来の色が付く',
      );
      // コード内容が表示される
      expect(find.textContaining('void main'), findsOneWidget);
    });

    testWidgets('言語なしフェンスドコードは既定描画へフォールバックする（D-2）', (tester) async {
      await pumpScreen(
        tester,
        sftpClient: FakeSftpClient(
          contentsByPath: {
            '/home/user/docs/readme.md': bytes(
              '# Code\n\n```\nplain block\n```\n',
            ),
          },
        ),
      );
      // class 属性なし → MarkdownCodeBlock は生成されない（既定 pre 描画）
      expect(find.byType(MarkdownCodeBlock), findsNothing);
      expect(find.textContaining('plain block'), findsWidgets);
    });

    test('MarkdownHighlighter: 20K 文字超はプレーン表示（M-3）', () {
      final longCode = 'a' * (MarkdownHighlighter.kMaxHighlightChars + 1);
      final span = MarkdownHighlighter(
        isDark: false,
      ).highlight(longCode, 'dart');
      expect(span.children, isNull);
      expect(span.text, longCode); // ハイライトされずそのまま
    });

    test('MarkdownHighlighter: comment は斜体・isDark で色が切替わる', () {
      const code = '// comment\nfinal x = 1; // trailing';
      final dark = MarkdownHighlighter(isDark: true).highlight(code, 'dart');
      final light = MarkdownHighlighter(isDark: false).highlight(code, 'dart');

      final darkSpans = _flatten(dark);
      final lightSpans = _flatten(light);
      // 両方とも色付きスパンを持つ（言語不明でもプレーンにはならない）
      expect(darkSpans.any((s) => s.style?.color != null), isTrue);
      expect(lightSpans.any((s) => s.style?.color != null), isTrue);
      // コメントは斜体
      final italic = darkSpans.where(
        (s) => s.style?.fontStyle == FontStyle.italic,
      );
      expect(italic, isNotEmpty);
    });
  });

  group('MarkdownHighlighter.languageFromClassAttribute', () {
    test('language-xxx から言語名を抽出する', () {
      expect(
        MarkdownHighlighter.languageFromClassAttribute('language-dart'),
        'dart',
      );
      expect(
        MarkdownHighlighter.languageFromClassAttribute('language-cpp'),
        'cpp',
      );
      expect(
        MarkdownHighlighter.languageFromClassAttribute('language-bash'),
        'bash',
      );
    });

    test('プレフィクス不一致・空・null は null を返す', () {
      expect(MarkdownHighlighter.languageFromClassAttribute(null), isNull);
      expect(MarkdownHighlighter.languageFromClassAttribute(''), isNull);
      expect(
        MarkdownHighlighter.languageFromClassAttribute('language-'),
        isNull,
      );
      expect(MarkdownHighlighter.languageFromClassAttribute('plain'), isNull);
    });
  });
}

bool _hasColoredTextSpan(InlineSpan span) {
  if (span is TextSpan) {
    final text = span.text;
    if (text != null && text.isNotEmpty && span.style?.color != null) {
      return true;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (_hasColoredTextSpan(child)) return true;
    }
  }
  return false;
}

List<TextSpan> _flatten(TextSpan span) {
  final out = <TextSpan>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      out.add(s);
      for (final child in s.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  walk(span);
  return out;
}
