import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/markdown_preview_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/file_browser/file_browser_screen.dart';
import 'package:flutter_muxpod/screens/file_browser/markdown_preview_screen.dart';

import '../../helpers/fake_sftp_client.dart';
import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/fake_tmux_notifier.dart';

/// open の呼び出しパスを記録する FakeSftpClient。
///
/// H-3（サイズ超過時は load を呼ばない = SFTP 読込が発生しない）の検証用。
class _RecordingSftpClient extends FakeSftpClient {
  final List<String> openedPaths = [];

  _RecordingSftpClient({
    super.entriesByPath,
    super.contentsByPath,
    super.homeDirectory,
  });

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    openedPaths.add(path);
    return super.open(path, mode: mode);
  }
}

SftpName _file(String name, {required int size}) => SftpName(
  filename: name,
  longname: '-rw-r--r--',
  attr: SftpFileAttrs(mode: SftpFileMode.value(0x81A4), size: size),
);

SftpName _dir(String name) => SftpName(
  filename: name,
  longname: 'drwxr-xr-x',
  attr: SftpFileAttrs(mode: SftpFileMode.value(0x41ED)),
);

/// 適正サイズ（20MB 以下）の .md/.markdown と対象外ファイル・ディレクトリを
/// 含む一覧 fixture。big.md は [size] 引数で 20MB 超に差し替え可能。
_RecordingSftpClient _defaultSftp() {
  return _RecordingSftpClient(
    homeDirectory: '/home/user',
    entriesByPath: {
      '/home/user': [
        _dir('docs'),
        _file('readme.md', size: 2048),
        _file('notes.markdown', size: 1024),
        _file('data.txt', size: 512),
        _file('big.md', size: maxPreviewBytes + 1),
      ],
    },
    contentsByPath: {
      '/home/user/readme.md': utf8.encode('# Hello\n\nMarkdown body'),
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// ファイルブラウザ画面を起動する（SFTP fixture は [sftpClient]）。
  ///
  /// paneId '%0' は tmuxState に存在しないため SFTP home へフォールバックし、
  /// ['/home/user'] の一覧が表示される（file_browser_provider_test と同型）。
  Future<_RecordingSftpClient> pumpScreen(
    WidgetTester tester, {
    required _RecordingSftpClient sftpClient,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final sshClient = FakeSshClient()..sftpClient = sftpClient;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sshProvider.overrideWith(() => FakeSshNotifier(client: sshClient)),
          tmuxProvider.overrideWith(
            () => FakeTmuxNotifier(initialState: const TmuxState()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FileBrowserScreen(connectionId: 'conn1', paneId: '%0'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sftpClient;
  }

  /// SnackBar の自動 dismiss タイマーを消化してクリーンアップする。
  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(FileBrowserScreen)));

  group('FileBrowserScreen - .md/.markdown タップ分岐（合意#2/#3）', () {
    testWidgets('適正サイズの .md タップでプレビュー画面へ遷移する', (tester) async {
      final sftp = await pumpScreen(tester, sftpClient: _defaultSftp());

      await tester.tap(find.text('readme.md'));
      await tester.pumpAndSettle();

      // プレビュー画面へ push される
      expect(find.byType(MarkdownPreviewScreen), findsOneWidget);
      // プレビュー画面が実読込を開始する（H-3: 画面側 load・SFTP open 発生）
      expect(sftp.openedPaths, contains('/home/user/readme.md'));
      // 本文がレンダリングされる
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('20MB 超の .md タップで警告のみ表示・遷移せず・SFTP 読込なし', (tester) async {
      final sftp = await pumpScreen(tester, sftpClient: _defaultSftp());
      final l10n = l10nOf(tester);

      await tester.tap(find.text('big.md'));
      await tester.pump();

      // 警告 SnackBar のみ（mdFileTooLargeTitle + 実サイズ MB・ceil）
      final mb = (entrySizeMb(maxPreviewBytes + 1));
      expect(
        find.text(
          '${l10n.mdFileTooLargeTitle}: ${l10n.mdFileTooLargeMessage(mb)}',
        ),
        findsOneWidget,
      );
      // プレビュー画面へ遷移しない
      expect(find.byType(MarkdownPreviewScreen), findsNothing);
      // H-3: load は呼ばない（SFTP open が発生しない）
      expect(sftp.openedPaths, isEmpty);

      await drainSnackBar(tester);
    });

    testWidgets('非 .md ファイルのタップは従来どおりメニュー表示（遷移しない）', (tester) async {
      await pumpScreen(tester, sftpClient: _defaultSftp());

      await tester.tap(find.text('data.txt'));
      await tester.pumpAndSettle();

      // アクションメニュー（BottomSheet）が開く。プレビュー遷移はしない
      expect(find.byType(MarkdownPreviewScreen), findsNothing);
      expect(find.byIcon(Icons.edit), findsOneWidget); // rename
      expect(find.byIcon(Icons.delete_outline), findsOneWidget); // delete
    });

    testWidgets('非 .md ファイルのメニューに open は表示されない（ディレクトリ専用化）', (tester) async {
      await pumpScreen(tester, sftpClient: _defaultSftp());

      await tester.longPress(find.text('data.txt'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.folder_open), findsNothing); // open 非表示
      expect(find.byIcon(Icons.edit), findsOneWidget); // rename は従来どおり
    });

    testWidgets('ディレクトリのメニューには従来どおり open が表示される', (tester) async {
      await pumpScreen(tester, sftpClient: _defaultSftp());

      await tester.longPress(find.text('docs'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('.md 長押しメニューの open でプレビュー画面へ遷移する（合意#2）', (tester) async {
      final sftp = await pumpScreen(tester, sftpClient: _defaultSftp());

      await tester.longPress(find.text('readme.md'));
      await tester.pumpAndSettle();

      // .md のメニューには open が表示される（タップと同義の入口）
      expect(find.byIcon(Icons.folder_open), findsOneWidget);

      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownPreviewScreen), findsOneWidget);
      expect(sftp.openedPaths, contains('/home/user/readme.md'));
    });

    testWidgets('.markdown 拡張子のタップでもプレビュー画面へ遷移する（合意#3）', (tester) async {
      final sftp = await pumpScreen(tester, sftpClient: _defaultSftp());

      await tester.tap(find.text('notes.markdown'));
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownPreviewScreen), findsOneWidget);
      // notes.markdown の内容が未提供のため SFTP 読込は空になるが遷移は成立する
      expect(sftp.openedPaths, contains('/home/user/notes.markdown'));
    });
  });
}

/// バイト数を実サイズの MB に切り上げる（mdFileTooLargeMessage の size と同式）。
int entrySizeMb(int bytes) => (bytes / (1024 * 1024)).ceil();
