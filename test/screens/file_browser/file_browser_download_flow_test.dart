import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/providers/file_browser_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/file_browser/file_browser_screen.dart';
import 'package:flutter_muxpod/services/sftp/file_entry.dart';

import '../../helpers/fake_file_browser_notifier.dart';
import '../../helpers/fake_settings_notifier.dart';
import '../../helpers/fake_sftp_client.dart';
import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';

/// FakeSftpClient を継承した download 系テスト用クライアント。
///
/// `stat` は contentsByPath にあれば実サイズを返す（totalBytes 算出用）。
/// `open` は contentsByPath の内容で [FakeSftpFile] を返す。
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

/// test/repro 以外で使用する共通エントリ。
FileEntry _entry(String name) => FileEntry(
  name: name,
  fullPath: '/home/user/$name',
  isDirectory: false,
  size: 300,
);

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// ダウンロードの実 IO（端末書込）は FakeAsync ゾーンでは完了しないため、
/// `tester.runAsync` で実イベントループを回しながら完了まで進める。
Future<void> _settleTransfer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  const timeout = Duration(seconds: 10);
  final sw = Stopwatch()..start();
  while (container.read(downloadProvider).phase ==
      DownloadPhase.downloading) {
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
}) async {
  final container = ProviderContainer(
    overrides: [
      fileBrowserProvider.overrideWith(
        () => FakeFileBrowserNotifier(entries: entries),
      ),
      sshProvider.overrideWith(() => FakeSshNotifier(client: sshClient)),
      settingsProvider.overrideWith(
        () => FakeSettingsNotifier(settings: const AppSettings()),
      ),
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

/// メニュー → ダウンロード → 保存先ダイアログ → 保存先確定まで進める。
Future<void> _startDownloadViaUi(WidgetTester tester) async {
  await tester.tap(find.text('report.pdf'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Download'));
  await tester.pumpAndSettle();
  // 保存先ダイアログ（Downloads 直下が既定）
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String appDocs;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('file_browser_dl_');
    appDocs = '${tmp.path}/docs';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return appDocs;
          }
          return null;
        });
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

  group('ファイルブラウザ ダウンロード導線（T9/T10）', () {
    testWidgets('ダウンロード導線: 保存先確定 → 転送完了・ファイル作成（衝突なし）', (tester) async {
      final content = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(
          contentsByPath: {'/home/user/report.pdf': content},
        );
      final container = await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_entry('report.pdf')],
      );

      await _startDownloadViaUi(tester);
      await _settleTransfer(tester, container);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.completedCount, 1);
      expect(state.failedCount, 0);
      // 保存先（Downloads 直下）にファイルが作成されている
      final saved = File('$appDocs/downloads/report.pdf');
      expect(saved.existsSync(), isTrue);
      expect(saved.lengthSync(), 300);
      // SftpClient.close() は呼ばれない（チャネル枯渇防止・closeCalls==0）
      expect(sshClient.sftpClient.closeCalls, 0);
    });

    testWidgets(
      '上書き確認導線: 衝突検出 → 基盤ダイアログ → Overwrite 決定で転送',
      (tester) async {
        // 事前に衝突ファイルを配置（500B の旧内容）
        Directory('$appDocs/downloads').createSync(recursive: true);
        File('$appDocs/downloads/report.pdf').writeAsStringSync(
          List.filled(500, 0x61).map((c) => String.fromCharCode(c)).join(),
        );

        final content = Uint8List.fromList(List.generate(300, (i) => i % 256));
        final sshClient = FakeSshClient()
          ..sftpClient = _TestSftpClient(
            contentsByPath: {'/home/user/report.pdf': content},
          );
        final container = await _pumpScreen(
          tester,
          sshClient: sshClient,
          entries: [_entry('report.pdf')],
        );

        await _startDownloadViaUi(tester);

        // 事前スキャンで衝突検出 → awaitingOverwrite → 基盤ダイアログ表示
        expect(
          container.read(downloadProvider).phase,
          DownloadPhase.awaitingOverwrite,
        );
        expect(find.text('File already exists'), findsOneWidget);

        // Overwrite 決定
        await tester.tap(find.text('Overwrite'));
        await tester.pumpAndSettle();

        await _settleTransfer(tester, container);
        expect(container.read(downloadProvider).phase, DownloadPhase.completed);
        expect(container.read(downloadProvider).completedCount, 1);
        // 上書きされた（新内容 300B）
        final saved = File('$appDocs/downloads/report.pdf');
        expect(saved.existsSync(), isTrue);
        expect(saved.lengthSync(), 300);
        expect(sshClient.sftpClient.closeCalls, 0);
      },
    );

    testWidgets(
      '上書き確認導線: barrier dismiss（null）→ バッチ中断・転送開始しない',
      (tester) async {
        Directory('$appDocs/downloads').createSync(recursive: true);
        final existing = File('$appDocs/downloads/report.pdf')
          ..writeAsStringSync('old-content');

        final sshClient = FakeSshClient()
          ..sftpClient = _TestSftpClient(
            contentsByPath: {
              '/home/user/report.pdf': Uint8List.fromList(
                List.generate(300, (i) => i % 256),
              ),
            },
          );
        final container = await _pumpScreen(
          tester,
          sshClient: sshClient,
          entries: [_entry('report.pdf')],
        );

        await _startDownloadViaUi(tester);
        expect(
          container.read(downloadProvider).phase,
          DownloadPhase.awaitingOverwrite,
        );

        // barrier（ダイアログ外）タップ = dismiss → 戻り値 null → バッチ中断
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        expect(container.read(downloadProvider).phase, DownloadPhase.idle);
        // 転送は開始されていない（既存ファイルが変更されていない）
        expect(existing.readAsStringSync(), 'old-content');
        expect(sshClient.sftpClient.closeCalls, 0);
      },
    );

    testWidgets(
      '上書き確認導線: applyToAll で残りの衝突にも同じ決定を適用（listen 導線）',
      (tester) async {
        // 2 件衝突（a.pdf / b.pdf）
        Directory('$appDocs/downloads').createSync(recursive: true);
        File('$appDocs/downloads/a.pdf').writeAsStringSync('old-a');
        File('$appDocs/downloads/b.pdf').writeAsStringSync('old-b');

        final content = Uint8List.fromList(List.generate(300, (i) => i % 256));
        final sshClient = FakeSshClient()
          ..sftpClient = _TestSftpClient(
            contentsByPath: {
              '/home/user/a.pdf': content,
              '/home/user/b.pdf': content,
            },
          );
        final container = await _pumpScreen(
          tester,
          sshClient: sshClient,
          entries: [_entry('a.pdf'), _entry('b.pdf')],
        );

        // UI のメニューは単一エントリのため、listen 導線（_downloadFlowSub）を
        // 検証する形で startDownloads を直接開始する。
        final started = container.read(downloadProvider.notifier);
        started.startDownloads(
          [_entry('a.pdf'), _entry('b.pdf')],
          '$appDocs/downloads',
        );
        await tester.pumpAndSettle();

        expect(
          container.read(downloadProvider).phase,
          DownloadPhase.awaitingOverwrite,
        );
        expect(find.text('File already exists'), findsOneWidget);

        // Overwrite + 全ファイルに適用
        await tester.tap(find.text('Apply to all'));
        await tester.pump();
        await tester.tap(find.text('Overwrite'));
        await tester.pump();

        await _settleTransfer(tester, container);
        expect(container.read(downloadProvider).phase, DownloadPhase.completed);
        expect(container.read(downloadProvider).completedCount, 2);
        expect(File('$appDocs/downloads/a.pdf').lengthSync(), 300);
        expect(File('$appDocs/downloads/b.pdf').lengthSync(), 300);
        expect(sshClient.sftpClient.closeCalls, 0);
      },
    );
  });
}