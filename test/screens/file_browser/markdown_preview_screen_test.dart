import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/markdown_preview_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/file_browser/markdown_preview_screen.dart';
import '../../helpers/fake_sftp_client.dart';
import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';
import 'helpers/markdown_preview_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('MarkdownPreviewScreen - 基本表示', () {
    testWidgets('AppBar タイトルとファイル名を表示する', (tester) async {
      await pumpScreen(
        tester,
        sftpClient: FakeSftpClient(
          contentsByPath: {
            '/home/user/docs/readme.md': bytes('# Title\n\nHello **world**\n'),
          },
        ),
      );
      expect(find.text('Markdown Preview'), findsOneWidget); // mdPreviewTitle
      expect(find.text('readme.md'), findsOneWidget); // ファイル名
      // Rendered が既定（D-4）
      expect(find.text('Title', findRichText: true), findsOneWidget);
      expect(find.textContaining('world', findRichText: true), findsOneWidget);
    });

    testWidgets('H-3: initState 直後の postFrame で load が開始される', (tester) async {
      final notifier = FakeMarkdownPreviewNotifier(
        const MarkdownPreviewState(),
      );
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sshProvider.overrideWith(
              () => FakeSshNotifier(client: FakeSshClient()),
            ),
            markdownPreviewProvider.overrideWith(() => notifier),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MarkdownPreviewScreen(
              connectionId: 'conn1',
              entry: mdEntry(),
            ),
          ),
        ),
      );
      // 初回フレーム後（postFrameCallback）に load が開始される（H-3）
      expect(notifier.loadCalls, 1);
      expect(find.text('Markdown Preview'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('MarkdownPreviewScreen - Raw/Rendered トグル', () {
    testWidgets('Rendered→Raw（SelectableText）→Rendered を往復できる', (tester) async {
      await pumpScreen(
        tester,
        sftpClient: FakeSftpClient(
          contentsByPath: {
            '/home/user/docs/readme.md': bytes(
              '# Title\n\nLine one\n\nLine two\n',
            ),
          },
        ),
      );
      expect(find.byType(SelectableText), findsNothing);
      expect(find.byType(MarkdownCodeBlock), findsNothing);
      expect(find.text('Title', findRichText: true), findsOneWidget);

      // → Raw
      await tester.tap(find.text('Raw'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('Title', findRichText: true), findsNothing);

      // → Rendered（戻り）
      await tester.tap(find.text('Rendered'));
      await tester.pumpAndSettle();
      expect(find.text('Title', findRichText: true), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('トグル時に現在ビューのスクロール比率を他ビューへ適用する（合意#5）', (tester) async {
      final paragraphs = List.generate(
        150,
        (i) => 'Paragraph number $i with some content text.\n\n',
      ).join();
      await pumpScreen(
        tester,
        sftpClient: FakeSftpClient(
          contentsByPath: {
            '/home/user/docs/readme.md': bytes('# Header\n\n$paragraphs'),
          },
        ),
      );

      // Rendered（既定）ビューをドラッグでスクロール
      // （SelectableText 等の内部 Scrollable を除外するため最外 .first を使う）
      final renderedScrollable = find
          .descendant(
            of: find.byKey(MarkdownPreviewScreen.renderedScrollKey),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(
        find.byKey(MarkdownPreviewScreen.renderedScrollKey),
        const Offset(0, -2000),
      );
      await tester.pump();
      final renderedPos = tester
          .state<ScrollableState>(renderedScrollable)
          .position;
      expect(renderedPos.pixels, greaterThan(0));
      expect(renderedPos.maxScrollExtent, greaterThan(0));
      final ratio = renderedPos.pixels / renderedPos.maxScrollExtent;
      expect(ratio, greaterThan(0));

      // → Raw へトグル（postFrame で jumpTo(比率 × 新 maxScrollExtent)）
      await tester.tap(find.text('Raw'));
      await tester.pump();
      await tester.pump();

      final rawScrollable = find
          .descendant(
            of: find.byKey(MarkdownPreviewScreen.rawScrollKey),
            matching: find.byType(Scrollable),
          )
          .first;
      final rawPos = tester.state<ScrollableState>(rawScrollable).position;
      expect(rawPos.maxScrollExtent, greaterThan(0));
      expect(
        rawPos.pixels,
        closeTo(ratio * rawPos.maxScrollExtent, 0.001),
        reason: 'トグル後の他ビューは比率 × 新 maxScrollExtent へ移動する',
      );
    });
  });

  group('MarkdownPreviewScreen - 状態表示', () {
    testWidgets('空ファイルは mdEmpty を表示する', (tester) async {
      await pumpScreen(
        tester,
        sftpClient: FakeSftpClient(
          contentsByPath: {'/home/user/docs/readme.md': bytes('')},
        ),
      );
      expect(find.text('This file is empty.'), findsOneWidget);
    });

    testWidgets('取得失敗は mdLoadFailed + mdRetry を表示し再試行で復帰する', (tester) async {
      final sftpClient = FlakySftpClient(
        contentsByPath: {'/home/user/docs/readme.md': bytes('# Recovered\n')},
      );
      await pumpScreen(tester, sftpClient: sftpClient);

      expect(find.textContaining('Failed to load'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // 再接続相当: SFTP を回復させて Retry
      sftpClient.failOpen = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to load'), findsNothing);
      expect(find.text('Recovered', findRichText: true), findsOneWidget);
    });

    testWidgets('バイナリ .md は mdBinaryFile を表示し本文を表示しない', (tester) async {
      final binary = Uint8List.fromList([
        ...bytes('# fake md\n'),
        0x00,
        0x01,
        0x02,
        0x03,
      ]);
      await pumpScreen(
        tester,
        sftpClient: FakeSftpClient(
          contentsByPath: {'/home/user/docs/readme.md': binary},
        ),
      );
      expect(
        find.text('This file appears to be binary and cannot be previewed.'),
        findsOneWidget,
      );
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('fake md', findRichText: true), findsNothing);
    });

    testWidgets('20MB 超は mdFileTooLarge 警告を表示する（SFTP 非アクセス・H-3）', (
      tester,
    ) async {
      final sftpClient = RecordingSftpClient();
      await pumpScreen(
        tester,
        sftpClient: sftpClient,
        entry: mdEntry(size: maxPreviewBytes + 1),
      );
      expect(find.text('File is too large'), findsOneWidget);
      expect(
        find.textContaining(
          'This file is 21 MB and exceeds the preview limit.',
        ),
        findsOneWidget,
      );
      expect(sftpClient.openedPaths, isEmpty); // 拒否は読み取らない
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('切詰め保険発動時は mdTruncatedMessage バナーと本文を表示する', (tester) async {
      await pumpScreenWithState(
        tester,
        const MarkdownPreviewState(
          content: '# Truncated\n\nbody text',
          isTruncated: true,
        ),
      );
      expect(
        find.text(
          'This file is larger than the preview limit and has been truncated.',
        ),
        findsOneWidget,
      );
      expect(find.text('Truncated', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('body text', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('バイナリ && 切詰めの複合時はバイナリ表示を優先する（レビュー #3 LOW-2）', (tester) async {
      await pumpScreenWithState(
        tester,
        const MarkdownPreviewState(isBinary: true, isTruncated: true),
      );
      expect(
        find.text('This file appears to be binary and cannot be previewed.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('truncated'),
        findsNothing,
        reason: 'content を表示しないため切詰めバナーは出さない',
      );
    });
  });
}
