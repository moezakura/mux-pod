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
import 'package:flutter_muxpod/services/download/save_as_exporter.dart';
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

/// 一括ダウンロードの保存先ピッカー fake。
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

/// 単一ダウンロードの Save-As エクスポーター fake。
///
/// [result]（null は Save-As キャンセル）を返し、呼び出し元パスを [calls] に記録する。
class FakeSaveAsExporter implements SaveAsExporter {
  FakeSaveAsExporter({this.result});

  final String? result;
  final List<String> calls = [];

  @override
  Future<String?> export(String sourceFilePath) async {
    calls.add(sourceFilePath);
    return result;
  }
}

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// 転送の実 IO（端末書込）は FakeAsync ゾーンでは完了しないため、
/// `tester.runAsync` で実イベントループを回しながら完了まで進める。
///
/// 単一（tmp→Save-As）は downloading → exporting → completed/cancelled と遷移する
/// （M3: 中間 completed は publish されない）。export の解決は runAsync（実ゾーン）中の
/// マイクロタスクに依存するため、終了確認前に実イベントループを数回空回しして確定させる。
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
    DownloadPhase.exporting,
  }.contains(container.read(downloadProvider).phase)) {
    if (sw.elapsed > timeout) {
      fail(
        'transfer did not settle: ${container.read(downloadProvider).phase}',
      );
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  // 中間 completed の後に走る export（単一）やシートの自動クローズを確定させる。
  // export の継続は FakeAsync 外（runAsync 実ゾーン）で解決されるため複数回空回し。
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  required FakeSshClient sshClient,
  required List<FileEntry> entries,
  required String appDocs,
  String? appTmp,
  BatchDestinationPicker? picker,
  SaveAsExporter? exporter,
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return appDocs;
        }
        if (call.method == 'getTemporaryDirectory') {
          return appTmp;
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
      if (exporter != null)
        downloadProvider.overrideWith(
          () => DownloadNotifier(exporter: exporter),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String appDocs;

  /// 単一（tmp→Save-As）フローで使う getTemporaryDirectory の戻り値。
  late String appTmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('file_browser_dl_');
    appDocs = '${tmp.path}/docs';
    appTmp = '${tmp.path}/app_tmp';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return appDocs;
          }
          if (call.method == 'getTemporaryDirectory') {
            return appTmp;
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

  group('ファイルブラウザ 単一ダウンロード導線（tmp→Save-As）', () {
    testWidgets('単一DL: メニュー → 一時DL → Save-As 確定 → completed', (tester) async {
      final content = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(
          contentsByPath: {'/home/user/report.pdf': content},
        );
      final exporter = FakeSaveAsExporter(result: 'Download/report.pdf');
      final container = await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_entry('report.pdf')],
        appDocs: appDocs,
        appTmp: appTmp,
        exporter: exporter,
      );

      // メニュー → Download（保存先選択は OS Save-As が担うためダイアログなし）。
      await tester.tap(find.text('report.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pump();
      await _settleTransfer(tester, container);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.completedCount, 1);
      expect(state.failedCount, 0);
      // Save-As の戻り値パスで localPath が更新される。
      expect(state.items[0].localPath, 'Download/report.pdf');
      // export は tmp 実パス（`_1` 採番）で 1 回だけ呼ばれる。
      expect(exporter.calls, ['$appTmp/sftp_download/report_1.pdf']);
      // export 後は tmp ファイルが削除される。
      expect(File('$appTmp/sftp_download/report_1.pdf').existsSync(), isFalse);
      // SftpClient.close() は呼ばれない（チャネル枯渇防止・closeCalls==0）
      expect(sshClient.sftpClient.closeCalls, 0);
    });

    testWidgets('単一DL: Save-As キャンセル（null）→ cancelled + tmp 削除', (
      tester,
    ) async {
      final content = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(
          contentsByPath: {'/home/user/report.pdf': content},
        );
      final exporter = FakeSaveAsExporter(result: null); // Save-As キャンセル。
      final container = await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_entry('report.pdf')],
        appDocs: appDocs,
        appTmp: appTmp,
        exporter: exporter,
      );

      await tester.tap(find.text('report.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pump();
      await _settleTransfer(tester, container);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.cancelled);
      // tmp 残骸は削除される。
      expect(File('$appTmp/sftp_download/report_1.pdf').existsSync(), isFalse);
      expect(sshClient.sftpClient.closeCalls, 0);
    });
  });

  group('ファイルブラウザ 一括ダウンロード導線（OS フォルダピッカー）', () {
    testWidgets('一括DL: FakePicker の保存先へ順次転送完了・ファイル 2 件生成', (tester) async {
      Directory('$appDocs/downloads').createSync(recursive: true);
      final content = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(
          contentsByPath: {
            '/home/user/a.pdf': content,
            '/home/user/b.pdf': content,
          },
        );
      final picker = FakeBatchDestinationPicker(
        result: FileDestination('$appDocs/downloads'),
      );
      final container = await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_entry('a.pdf'), _entry('b.pdf')],
        appDocs: appDocs,
        picker: picker,
      );

      // 選択モード → 2 件選択 → 一括DL。
      await tester.longPress(find.text('a.pdf'));
      await tester.pump();
      await tester.tap(find.text('b.pdf'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Batch download'));
      await tester.pump();
      await _settleTransfer(tester, container);
      await tester.pumpAndSettle(); // 進捗シートの自動クローズ後を確定

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.completedCount, 2);
      expect(state.failedCount, 0);
      // ピッカーは 1 回だけ呼ばれ、選択した保存先へ書込まれる。
      expect(picker.pickCalls, 1);
      expect(File('$appDocs/downloads/a.pdf').existsSync(), isTrue);
      expect(File('$appDocs/downloads/b.pdf').existsSync(), isTrue);
      // SftpClient.close() は呼ばれない（チャネル枯渇防止・closeCalls==0）
      expect(sshClient.sftpClient.closeCalls, 0);
    });

    testWidgets('一括DL: 保存先ピッカーキャンセル（null）→ idle 維持・転送未開始', (tester) async {
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(
          contentsByPath: {
            '/home/user/a.pdf': Uint8List.fromList([1, 2, 3]),
            '/home/user/b.pdf': Uint8List.fromList([4, 5, 6]),
          },
        );
      final picker = FakeBatchDestinationPicker(result: null); // キャンセル。
      final container = await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_entry('a.pdf'), _entry('b.pdf')],
        appDocs: appDocs,
        picker: picker,
      );

      await tester.longPress(find.text('a.pdf'));
      await tester.pump();
      await tester.tap(find.text('b.pdf'));
      await tester.pump();

      await tester.tap(find.byTooltip('Batch download'));
      await tester.pumpAndSettle();

      // 保存先キャンセルは idle 維持（転送は開始されない）。
      expect(picker.pickCalls, 1);
      expect(container.read(downloadProvider).phase, DownloadPhase.idle);
      expect(sshClient.sftpClient.closeCalls, 0);
    });

    testWidgets('一括DL: 衝突検出 → 基盤ダイアログ → Overwrite 決定で転送', (tester) async {
      // 事前に衝突ファイルを配置（500B の旧内容）。
      Directory('$appDocs/downloads').createSync(recursive: true);
      File('$appDocs/downloads/a.pdf').writeAsStringSync('old-content');

      final content = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(
          contentsByPath: {'/home/user/a.pdf': content},
        );
      final picker = FakeBatchDestinationPicker(
        result: FileDestination('$appDocs/downloads'),
      );
      final container = await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_entry('a.pdf')],
        appDocs: appDocs,
        picker: picker,
      );

      await tester.longPress(find.text('a.pdf'));
      await tester.pump();
      await tester.tap(find.byTooltip('Batch download'));
      await tester.pump();

      // 事前スキャン（destination.exists）が実 IO のため runAsync で進め、
      // awaitingOverwrite → 基盤ダイアログ表示まで待つ。
      await _waitUntil(
        tester,
        container,
        () =>
            container.read(downloadProvider).phase ==
            DownloadPhase.awaitingOverwrite,
      );
      await _waitForText(tester, 'File already exists');

      // Overwrite 決定（転送開始・進捗シートがアニメーションするため
      // pumpAndSettle は使わず、pump + runAsync で完了まで進める）。
      await tester.tap(find.text('Overwrite'));
      await tester.pump();

      await _settleTransfer(tester, container);
      expect(container.read(downloadProvider).phase, DownloadPhase.completed);
      expect(container.read(downloadProvider).completedCount, 1);
      // 上書きされた（新内容 300B）。
      final saved = File('$appDocs/downloads/a.pdf');
      expect(saved.existsSync(), isTrue);
      expect(saved.lengthSync(), 300);
      expect(sshClient.sftpClient.closeCalls, 0);
    });

    testWidgets('一括DL: applyToAll で残りの衝突にも同じ決定を適用（listen 導線）', (tester) async {
      // 2 件衝突（a.pdf / b.pdf）。
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
        appDocs: appDocs,
      );

      // UI のメニューは単一エントリのため、listen 導線（_downloadFlowSub）を
      // 検証する形で startDownloads（一括）を直接開始する。
      final started = container.read(downloadProvider.notifier);
      started.startDownloads([
        _entry('a.pdf'),
        _entry('b.pdf'),
      ], FileDestination('$appDocs/downloads'));

      // 事前スキャン（destination.exists）が実 IO のため runAsync で進め、
      // awaitingOverwrite → 基盤ダイアログ表示まで待つ。
      await _waitUntil(
        tester,
        container,
        () =>
            container.read(downloadProvider).phase ==
            DownloadPhase.awaitingOverwrite,
      );
      await _waitForText(tester, 'File already exists');

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
    });

    testWidgets('一括DL: 上書き確認の barrier dismiss（null）→ バッチ中断・転送開始しない', (
      tester,
    ) async {
      Directory('$appDocs/downloads').createSync(recursive: true);
      final existing = File('$appDocs/downloads/a.pdf')
        ..writeAsStringSync('old-content');

      final sshClient = FakeSshClient()
        ..sftpClient = _TestSftpClient(
          contentsByPath: {
            '/home/user/a.pdf': Uint8List.fromList(
              List.generate(300, (i) => i % 256),
            ),
          },
        );
      final picker = FakeBatchDestinationPicker(
        result: FileDestination('$appDocs/downloads'),
      );
      final container = await _pumpScreen(
        tester,
        sshClient: sshClient,
        entries: [_entry('a.pdf')],
        appDocs: appDocs,
        picker: picker,
      );

      await tester.longPress(find.text('a.pdf'));
      await tester.pump();
      await tester.tap(find.byTooltip('Batch download'));
      await tester.pump();

      await _waitUntil(
        tester,
        container,
        () =>
            container.read(downloadProvider).phase ==
            DownloadPhase.awaitingOverwrite,
      );

      // barrier（ダイアログ外）タップ = dismiss → 戻り値 null → バッチ中断。
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(container.read(downloadProvider).phase, DownloadPhase.idle);
      // 転送は開始されていない（既存ファイルが変更されていない）。
      expect(existing.readAsStringSync(), 'old-content');
      expect(sshClient.sftpClient.closeCalls, 0);
    });
  });
}

/// 条件成立まで runAsync で実イベントループを回しながら待つ（実 IO 依存フェーズ用）。
Future<void> _waitUntil(
  WidgetTester tester,
  ProviderContainer container,
  bool Function() condition,
) async {
  const timeout = Duration(seconds: 10);
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      fail(
        'condition did not become true: ${container.read(downloadProvider).phase}',
      );
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// 指定テキストが画面に現れるまで runAsync + pump で待つ（ダイアログ表示待ち用）。
Future<void> _waitForText(WidgetTester tester, String text) async {
  const timeout = Duration(seconds: 10);
  final sw = Stopwatch()..start();
  while (find.text(text).evaluate().isEmpty) {
    if (sw.elapsed > timeout) {
      fail('text "$text" did not appear');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}
