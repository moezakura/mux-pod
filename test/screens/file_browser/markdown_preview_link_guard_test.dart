import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/fake_sftp_client.dart';
import 'helpers/markdown_preview_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('MarkdownPreviewScreen - リンクガード（#11・L-2）', () {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');

    /// url_launcher プラットフォームチャンネルをモックし呼び出しを記録する。
    List<MethodCall> mockUrlLauncher(WidgetTester tester) {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      return calls;
    }

    testWidgets('https リンクのみ外部ブラウザへ launch する', (tester) async {
      final calls = mockUrlLauncher(tester);
      await pumpScreen(
        tester,
        sftpClient: FakeSftpClient(
          contentsByPath: {
            '/home/user/docs/readme.md': bytes(
              '# Links\n\n[openweb](https://example.com/page)\n',
            ),
          },
        ),
      );

      _invokeLinkTap(tester, 'openweb');
      await tester.pump();

      final launches = calls.where((c) => c.method == 'launch').toList();
      expect(launches, hasLength(1));
      expect(
        (launches.single.arguments as Map)['url'],
        'https://example.com/page',
      );
      // スキームガード前の canLaunch 経由で起動する（about_section パターン）
      expect(calls.where((c) => c.method == 'canLaunch'), hasLength(1));
    });

    testWidgets('mailto / #anchor リンクはタップ無視される', (tester) async {
      final calls = mockUrlLauncher(tester);
      await pumpScreen(
        tester,
        sftpClient: FakeSftpClient(
          contentsByPath: {
            '/home/user/docs/readme.md': bytes(
              '# Links\n\n[mailme](mailto:a@b.c)\n\n[secref](#section)\n',
            ),
          },
        ),
      );

      _invokeLinkTap(tester, 'mailme');
      _invokeLinkTap(tester, 'secref');
      await tester.pump();

      expect(calls, isEmpty, reason: '非 https/http は canLaunch も launch も呼ばない');
    });
  });
}

void _invokeLinkTap(WidgetTester tester, String linkText) {
  final richTexts = tester.widgetList<RichText>(find.byType(RichText)).toList();
  for (final rt in richTexts) {
    final spans = <TextSpan>[];
    rt.text.visitChildren((s) {
      if (s is TextSpan) spans.add(s);
      return true;
    });
    for (final span in spans) {
      final recognizer = span.recognizer;
      if (recognizer is TapGestureRecognizer && span.text == linkText) {
        recognizer.onTap!();
        return;
      }
    }
  }
  fail('link span not found: $linkText');
}

/// TextSpan 木を再帰的に走査し、色 + テキストを持つスパンが存在するか判定する。
