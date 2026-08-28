import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/markdown_preview_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/file_browser/markdown_preview_screen.dart';
import 'package:flutter_muxpod/screens/file_browser/widgets/sftp_markdown_image.dart';
import 'package:flutter_muxpod/services/sftp/file_entry.dart';
import 'package:flutter_muxpod/theme/markdown_highlighter.dart';

import '../../helpers/fake_sftp_client.dart';
import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';

/// 1x1 透明 PNG（Image.memory のデコード検証用・構造検証のための実バイト）。
final Uint8List kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

/// open の呼び出しパスを記録する FakeSftpClient（SFTP 読込の範囲検証用）。
class _RecordingSftpClient extends FakeSftpClient {
  final List<String> openedPaths = [];

  _RecordingSftpClient({super.contentsByPath});

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    openedPaths.add(path);
    return super.open(path, mode: mode);
  }
}

/// open 失敗→成功を切替できる FakeSftpClient（再試行テスト用）。
class _FlakySftpClient extends FakeSftpClient {
  bool failOpen = true;

  _FlakySftpClient({super.contentsByPath});

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    if (failOpen) throw Exception('sftp io failure');
    return super.open(path, mode: mode);
  }
}

/// 画面側 load 呼び出しを検証するためのスタブ Notifier（H-3 用）。
class _FakeMarkdownNotifier extends MarkdownPreviewNotifier {
  _FakeMarkdownNotifier(this._initial);

  final MarkdownPreviewState _initial;
  int loadCalls = 0;

  @override
  MarkdownPreviewState build() => _initial;

  @override
  Future<void> load({
    required String connectionId,
    required FileEntry entry,
  }) async {
    loadCalls++;
  }
}

FileEntry _mdEntry({int? size, String path = '/home/user/docs/readme.md'}) {
  return FileEntry(
    name: path.split('/').last,
    fullPath: path,
    isDirectory: false,
    size: size,
  );
}

Uint8List _bytes(String text) => utf8.encode(text);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 実 Provider 経由で画面を起動する（SFTP fixture は [sftpClient]）。
  Future<FakeSshClient> pumpScreen(
    WidgetTester tester, {
    FakeSftpClient? sftpClient,
    FileEntry? entry,
    FakeSshClient? sshClient,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final client =
        sshClient ??
        (FakeSshClient()..sftpClient = sftpClient ?? FakeSftpClient());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sshProvider.overrideWith(() => FakeSshNotifier(client: client)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MarkdownPreviewScreen(
            connectionId: 'conn1',
            entry: entry ?? _mdEntry(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return client;
  }

  /// スタブ Notifier（markdownPreviewProvider override）で画面を起動する。
  Future<void> pumpScreenWithState(
    WidgetTester tester,
    MarkdownPreviewState state,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sshProvider.overrideWith(
            () => FakeSshNotifier(client: FakeSshClient()),
          ),
          markdownPreviewProvider.overrideWith(
            () => _FakeMarkdownNotifier(state),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MarkdownPreviewScreen(connectionId: 'conn1', entry: _mdEntry()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('MarkdownPreviewScreen - 基本表示', () {
    testWidgets('AppBar タイトルとファイル名を表示する', (tester) async {
      await pumpScreen(
        tester,
        sftpClient: FakeSftpClient(
          contentsByPath: {
            '/home/user/docs/readme.md': _bytes('# Title\n\nHello **world**\n'),
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
      final notifier = _FakeMarkdownNotifier(const MarkdownPreviewState());
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
              entry: _mdEntry(),
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
            '/home/user/docs/readme.md': _bytes(
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
            '/home/user/docs/readme.md': _bytes('# Header\n\n$paragraphs'),
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
          contentsByPath: {'/home/user/docs/readme.md': _bytes('')},
        ),
      );
      expect(find.text('This file is empty.'), findsOneWidget);
    });

    testWidgets('取得失敗は mdLoadFailed + mdRetry を表示し再試行で復帰する', (tester) async {
      final sftpClient = _FlakySftpClient(
        contentsByPath: {'/home/user/docs/readme.md': _bytes('# Recovered\n')},
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
        ..._bytes('# fake md\n'),
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
      final sftpClient = _RecordingSftpClient();
      await pumpScreen(
        tester,
        sftpClient: sftpClient,
        entry: _mdEntry(size: maxPreviewBytes + 1),
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

  group('MarkdownPreviewScreen - 画像ガード（構造検証・L-3）', () {
    const mdImages = '''
# Images

![relative](./img.png)
![traversal](../secret.png)
![root](/etc/passwd.png)
![https](https://example.com/logo.png)
![private](http://192.168.1.10/x.png)
![loopback](http://127.0.0.1:8080/x.png)
![data](data:image/png;base64,iVBORw0KGgo=)
![ftp](ftp://example.com/x.png)
''';

    testWidgets('相対は SFTP 解決・拒否群は placeholder・https のみネットワーク（許可時のみ取得）', (
      tester,
    ) async {
      final sftpClient = _RecordingSftpClient(
        contentsByPath: {
          '/home/user/docs/readme.md': _bytes(mdImages),
          '/home/user/docs/img.png': kTinyPng,
        },
      );
      await pumpScreen(tester, sftpClient: sftpClient);

      // --- SFTP 読込は md 本体 + 許可された相対パス 1 件のみ
      //（denied 群は一切 open されない）---
      expect(sftpClient.openedPaths, [
        '/home/user/docs/readme.md',
        '/home/user/docs/img.png',
      ], reason: 'トラバーサル・ルート・絶対 URL は SFTP を一切呼ばない');
      // 相対成功 → Image.memory（ImageProvider 構造で検証）
      final memoryImages = tester
          .widgetList<Image>(
            find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage),
          )
          .toList();
      expect(memoryImages, hasLength(1));

      // --- https のみネットワーク許可（localhost / private IP は拒否）---
      // 構造検証: imageBuilder が Image.network（NetworkImage）を返したこと自体が
      // 「許可時のみ GET」を表す（テスト環境では HTTP 失敗で errorBuilder が
      // build されるが、Image ウィジェットは木に残るため NetworkImage で判定可）。
      final networkImages = tester
          .widgetList<Image>(
            find.byWidgetPredicate(
              (w) => w is Image && w.image is NetworkImage,
            ),
          )
          .toList();
      expect(networkImages, hasLength(1), reason: 'https://example.com のみ許可');
      expect(
        (networkImages.single.image as NetworkImage).url,
        'https://example.com/logo.png',
      );

      // --- 拒否群（traversal / root / private / loopback / data / ftp）---
      expect(find.byIcon(Icons.broken_image), findsNWidgets(6));
    });
  });

  group('SftpMarkdownImage.resolveImage（純関数・構造検証）', () {
    test('相対パスは .md ディレクトリ基準で SFTP 解決する', () {
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('./img.png'),
        mdBaseDirectory: '/home/user/docs',
      );
      expect(r.kind, MarkdownImageResolvedKind.sftp);
      expect(r.sftpPath, '/home/user/docs/img.png');
    });

    test('サブディレクトリ相対はベース配下なら許可する', () {
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('assets/img.png'),
        mdBaseDirectory: '/home/user/docs',
      );
      expect(r.kind, MarkdownImageResolvedKind.sftp);
      expect(r.sftpPath, '/home/user/docs/assets/img.png');
    });

    test('`../` でベース外へ脱出する相対パスは拒否する（パストラバーサル）', () {
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('../secret.png'),
        mdBaseDirectory: '/home/user/docs',
      );
      expect(r.kind, MarkdownImageResolvedKind.denied);
    });

    test('ルート相対（先頭 /）はベース配下でないため拒否する（D-3）', () {
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('/etc/passwd.png'),
        mdBaseDirectory: '/home/user/docs',
      );
      expect(r.kind, MarkdownImageResolvedKind.denied);
    });

    test('ベースがサーバールート（/）のとき相対画像はルート配下として許可する（MEDIUM-2）', () {
      // .md がルート直下（/README.md）: ベースディレクトリ = '/'
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('img.png'),
        mdBaseDirectory: '/',
      );
      expect(r.kind, MarkdownImageResolvedKind.sftp);
      expect(r.sftpPath, '/img.png');
      // サブディレクトリ参照もルート配下として許可される
      final sub = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('assets/logo.png'),
        mdBaseDirectory: '/',
      );
      expect(sub.kind, MarkdownImageResolvedKind.sftp);
      expect(sub.sftpPath, '/assets/logo.png');
    });

    test('ベースディレクトリが不明な相対パスは拒否する', () {
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('img.png'),
        mdBaseDirectory: null,
      );
      expect(r.kind, MarkdownImageResolvedKind.denied);
    });

    test('https/http は許可（ホスト名・パブリック IP）', () {
      for (final src in [
        'https://example.com/logo.png',
        'http://example.com/x.png',
        'https://8.8.8.8/x.png',
      ]) {
        final r = SftpMarkdownImage.resolveImage(
          uri: Uri.parse(src),
          mdBaseDirectory: '/home/user/docs',
        );
        expect(r.kind, MarkdownImageResolvedKind.network, reason: src);
      }
    });

    test('https/http でも localhost / private IP は拒否する', () {
      for (final src in [
        'http://localhost/x.png',
        'http://127.0.0.1/x.png',
        'http://10.1.2.3/x.png',
        'http://172.16.0.1/x.png',
        'http://172.31.255.254/x.png',
        'http://192.168.0.1/x.png',
        // IPv4-mapped IPv6 は IPv6 型として素通りするため明示拒否（MEDIUM-1）
        'http://[::ffff:10.0.0.1]/x.png',
        'http://[::ffff:127.0.0.1]:8080/x.png',
        'http://[::ffff:192.168.1.1]/x.png',
      ]) {
        final r = SftpMarkdownImage.resolveImage(
          uri: Uri.parse(src),
          mdBaseDirectory: '/home/user/docs',
        );
        expect(r.kind, MarkdownImageResolvedKind.denied, reason: src);
      }
    });

    test('data URI・その他スキームは拒否する（本フェーズ外）', () {
      for (final src in [
        'data:image/png;base64,iVBORw0KGgo=',
        'ftp://example.com/x.png',
        'file:///etc/passwd',
        'mailto:a@b.c',
        'javascript:alert(1)',
      ]) {
        final r = SftpMarkdownImage.resolveImage(
          uri: Uri.parse(src),
          mdBaseDirectory: '/home/user/docs',
        );
        expect(r.kind, MarkdownImageResolvedKind.denied, reason: src);
      }
    });
  });

  group('SftpMarkdownImage.isBlockedHost（純関数）', () {
    test('localhost・ループバック・プライベート IP・unspecified をブロックする', () {
      for (final host in [
        'localhost',
        'LOCALHOST',
        '127.0.0.1',
        '127.8.9.10',
        '::1',
        '0.0.0.0',
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.1',
        '::',
        'fc00::1',
        // IPv4-mapped IPv6（IPv6 型で isLoopback/isLinkLocal が効かないため
        // 明示再判定が必要・MEDIUM-1）
        '::ffff:127.0.0.1',
        '::ffff:10.0.0.1',
        '::ffff:172.16.0.1',
        '::ffff:192.168.1.1',
        '::ffff:169.254.1.1',
        '::ffff:0.0.0.0',
      ]) {
        expect(SftpMarkdownImage.isBlockedHost(host), isTrue, reason: host);
      }
    });

    test('パブリック IP・ホスト名は許可する', () {
      for (final host in [
        '8.8.8.8',
        '1.1.1.1',
        'example.com',
        's3.amazonaws.com',
        '172.15.0.1', // 172.16/12 の範囲外
        '172.32.0.1',
        '::ffff:8.8.8.8', // IPv4-mapped でもパブリック IPv4 は許可
        '2001:db8::1',
      ]) {
        expect(SftpMarkdownImage.isBlockedHost(host), isFalse, reason: host);
      }
    });
  });

  group('MarkdownPreviewScreen - 言語別ハイライト（C-2・M-3）', () {
    testWidgets('言語指定フェンスドコードはハイライト（色付きスパン）で表示する', (tester) async {
      await pumpScreen(
        tester,
        sftpClient: FakeSftpClient(
          contentsByPath: {
            '/home/user/docs/readme.md': _bytes(
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
            '/home/user/docs/readme.md': _bytes(
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
            '/home/user/docs/readme.md': _bytes(
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
            '/home/user/docs/readme.md': _bytes(
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

/// Rendered ビュー内の RichText から [linkText] のスパンを探し、
/// その TapGestureRecognizer の onTap を呼び出す（flutter_markdown_plus の
/// 自身のテストと同手法で、実配線した recognizer → onTapLink → ガードを検証）。
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

/// TextSpan 木をフラットなリストへ展開する（テスト用）。
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
