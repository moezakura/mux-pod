import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/batch_destination_picker_provider.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/providers/file_browser_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/file_browser/file_browser_screen.dart';
import 'package:flutter_muxpod/services/download/batch_destination_picker.dart';
import 'package:flutter_muxpod/services/download/download_destination.dart';
import 'package:flutter_muxpod/services/download/file_destination.dart';
import 'package:flutter_muxpod/services/sftp/file_entry.dart';

import '../../helpers/fake_file_browser_notifier.dart';
import '../../helpers/fake_settings_notifier.dart';
import '../../helpers/fake_sftp_client.dart';
import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';

/// FakeSftpClient を継承した download 系テスト用クライアント（wave2 の
/// file_browser_download_flow_test と同型）。
class _TestSftpClient extends FakeSftpClient {
  _TestSftpClient({required super.contentsByPath});

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    final content = contentsByPath[path];
    if (content != null) {
      return SftpFileAttrs(
        mode: SftpFileMode.value(0x81A4),
        size: content.length,
        modifyTime: DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000,
      );
    }
    return super.stat(path, followLink: followLink);
  }

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    return FakeSftpFile(this, contentsByPath[path] ?? Uint8List(0));
  }
}

/// 一括ダウンロードの保存先ピッカー fake（ダウンロード導線の検証用）。
///
/// [result]（null は保存先キャンセル）をそのまま返し、pick 呼び出し回数を記録する。
class FakeBatchDestinationPicker implements BatchDestinationPicker {
  FakeBatchDestinationPicker({this.result});

  final DownloadDestination? result;
  int pickCalls = 0;

  @override
  Future<DownloadDestination?> pick() async {
    pickCalls++;
    return result;
  }
}

FileEntry _file(String name) => FileEntry(
  name: name,
  fullPath: '/home/user/$name',
  isDirectory: false,
  size: 300,
);

FileEntry _dir(String name) =>
    FileEntry(name: name, fullPath: '/home/user/$name', isDirectory: true);

FileEntry _symlink(String name) => FileEntry(
  name: name,
  fullPath: '/home/user/$name',
  isDirectory: false,
  isSymlink: true,
  size: 300,
);

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// ダウンロードの実 IO（端末書込・事前スキャンの exists）は FakeAsync ゾーンでは
/// 完了しないため、`tester.runAsync` で実イベントループを回しながら完了まで進める。
/// 選択開始（selecting・事前スキャン）〜転送（downloading）までを対象にする。
Future<void> _settleTransfer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  const timeout = Duration(seconds: 10);
  final sw = Stopwatch()..start();
  while (const {
    DownloadPhase.idle,
    DownloadPhase.selecting,
    DownloadPhase.downloading,
  }.contains(container.read(downloadProvider).phase)) {
    if (sw.elapsed > timeout) {
      fail(
        'transfer did not settle: ${container.read(downloadProvider).phase}',
      );
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  required FakeSshClient sshClient,
  required List<FileEntry> entries,
  required String appDocs,
  BatchDestinationPicker? picker,
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return appDocs;
        }
        return null;
      });

  final container = ProviderContainer(
    overrides: [
      fileBrowserProvider.overrideWith(
        () => FakeFileBrowserNotifier(entries: entries),
      ),
      sshProvider.overrideWith(() => FakeSshNotifier(client: sshClient)),
      settingsProvider.overrideWith(
        () => FakeSettingsNotifier(settings: const AppSettings()),
      ),
      if (picker != null)
        batchDestinationPickerProvider.overrideWithValue(picker),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FileBrowserScreen(connectionId: 'test-conn'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// AppBar の一括DL IconButton を tooltip で取得する。
IconButton _batchDownloadButton(WidgetTester tester) =>
    tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Batch download'),
        matching: find.byType(IconButton),
      ),
    );

/// 選択モード中のチェックボックス値を一覧で返す（entries の表示順）。
List<bool?> _checkboxValues(WidgetTester tester) => tester
    .widgetList<Checkbox>(find.byType(Checkbox))
    .map((c) => c.value)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String appDocs;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('file_browser_ms_');
    appDocs = '${tmp.path}/docs';
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // 削除失敗は検証対象外。
    }
  });

  group('複数選択モード（T15・受入⑧）', () {
    testWidgets('通常モードは全エントリの右端に more_vert メニューを表示する', (tester) async {
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(contentsByPath: {});
      await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_dir('docs'), _file('a.txt'), _symlink('lnk')],
        appDocs: appDocs,
      );

      expect(find.byIcon(Icons.more_vert), findsNWidgets(3));
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      final moreTooltip = MaterialLocalizations.of(
        tester.element(find.byType(FileBrowserScreen)),
      ).moreButtonTooltip;
      expect(find.byTooltip(moreTooltip), findsNWidgets(3));
    });

    testWidgets('ファイル長押しで選択モード突入・件数表示・チェックボックス表示', (tester) async {
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(contentsByPath: {});
      await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_file('a.txt'), _file('b.txt')],
        appDocs: appDocs,
      );

      await tester.longPress(find.text('a.txt'));
      await tester.pumpAndSettle();

      // AppBar に選択件数（1 selected）とチェックボックス（選択可能な 2 ファイル）。
      expect(find.text('1 selected'), findsOneWidget);
      final values = _checkboxValues(tester);
      expect(values, [true, false]);
    });

    testWidgets('タップでトグル・件数が更新される', (tester) async {
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(contentsByPath: {});
      await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_file('a.txt'), _file('b.txt')],
        appDocs: appDocs,
      );

      await tester.longPress(find.text('a.txt'));
      await tester.pump();
      await tester.tap(find.text('b.txt'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.text('a.txt'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(_checkboxValues(tester), [false, true]);
    });

    testWidgets('選択モードはファイルのみ Checkbox、directory/symlink は右端操作なし', (
      tester,
    ) async {
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(contentsByPath: {});
      await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_dir('docs'), _file('a.txt'), _symlink('lnk')],
        appDocs: appDocs,
      );

      await tester.longPress(find.text('a.txt'));
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);

      await tester.longPress(find.text('lnk'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Rename'), findsNothing);
    });

    testWidgets('選択 0 件では一括DL ボタンが無効', (tester) async {
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(contentsByPath: {});
      await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_file('a.txt'), _file('b.txt')],
        appDocs: appDocs,
      );

      await tester.longPress(find.text('a.txt'));
      await tester.pump();
      // 選択を全て解除 → 0 件
      await tester.tap(find.text('a.txt'));
      await tester.pump();

      expect(find.text('0 selected'), findsOneWidget);
      expect(_batchDownloadButton(tester).onPressed, isNull);
    });

    testWidgets('解除ボタンで選択モード終了（選択クリア・通常 AppBar へ復帰）', (tester) async {
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(contentsByPath: {});
      await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_file('a.txt'), _file('b.txt')],
        appDocs: appDocs,
      );

      await tester.longPress(find.text('a.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear selection'));
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('1 selected'), findsNothing);
      // 通常 AppBar の並び替えメニューが復帰
      expect(find.byTooltip('Sort'), findsOneWidget);
    });

    testWidgets('ディレクトリ長押しは選択モードに入らず従来のアクションメニュー（download 非表示）', (
      tester,
    ) async {
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(contentsByPath: {});
      await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_dir('docs'), _file('a.txt')],
        appDocs: appDocs,
      );

      await tester.longPress(find.text('docs'));
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing); // 選択モードに入らない
      expect(find.text('Open'), findsOneWidget); // ディレクトリメニュー
      expect(find.text('Download'), findsNothing); // ファイルのみ
    });

    testWidgets('シンボリックリンク長押しは選択不可・アクションメニュー（download 非表示）', (tester) async {
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(contentsByPath: {});
      await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_symlink('lnk'), _file('a.txt')],
        appDocs: appDocs,
      );

      await tester.longPress(find.text('lnk'));
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Download'), findsNothing); // シンボリックリンクは対象外
      expect(find.text('Rename'), findsOneWidget);
    });

    testWidgets('一括DL: 選択 2 件 → 保存先 1 回 → 順次転送完了・ファイル 2 件生成', (tester) async {
      // ピッカーが返す保存先ディレクトリを事前生成（FileDestination 書込先）。
      Directory('$appDocs/downloads').createSync(recursive: true);
      final content = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(
          contentsByPath: {
            '/home/user/a.txt': content,
            '/home/user/b.txt': content,
          },
        );
      final picker = FakeBatchDestinationPicker(
        result: FileDestination('$appDocs/downloads'),
      );
      final container = await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_file('a.txt'), _file('b.txt')],
        appDocs: appDocs,
        picker: picker,
      );

      await tester.longPress(find.text('a.txt'));
      await tester.pump();
      await tester.tap(find.text('b.txt'));
      await tester.pump();

      await tester.tap(find.byTooltip('Batch download'));
      await tester.pump();
      // OS フォルダピッカー（FakePicker）は 1 回だけ呼ばれ、転送は直後に開始される。
      // 転送中の進捗シートは未開始アイテムの不定プログレスがアニメーションするため
      // pumpAndSettle は使わず、pump + runAsync（実 IO）で完了まで進める。
      await _settleTransfer(tester, container);
      await tester.pumpAndSettle(); // 進捗シートの自動クローズ後を確定

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.completedCount, 2);
      expect(state.failedCount, 0);
      // 保存先ピッカーは 1 回だけ（選択 2 件を 1 ディレクトリへ順次書込）。
      expect(picker.pickCalls, 1);
      expect(File('$appDocs/downloads/a.txt').existsSync(), isTrue);
      expect(File('$appDocs/downloads/b.txt').existsSync(), isTrue);
      // SftpClient.close() は呼ばれない（チャネル枯渇防止・closeCalls==0）
      expect(sshClient.sftpClient.closeCalls, 0);
    });

    testWidgets('選択モード中のディレクトリタップはナビゲート + 選択解除', (tester) async {
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(contentsByPath: {});
      final container = await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_dir('docs'), _file('a.txt')],
        appDocs: appDocs,
      );

      await tester.longPress(find.text('a.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();

      final notifier =
          container.read(fileBrowserProvider.notifier)
              as FakeFileBrowserNotifier;
      expect(notifier.navigatedPaths, ['/home/user/docs']);
      expect(find.byType(Checkbox), findsNothing); // 選択解除
    });
  });
}
