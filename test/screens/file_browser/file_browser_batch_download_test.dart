import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/services/download/file_destination.dart';
import '../../helpers/fake_ssh_client.dart';
import 'helpers/download_flow_harness.dart';

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
    registerPathProviderChannel(appDocs, appTmp);
  });

  tearDown(() {
    unregisterPathProviderChannel();
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // 削除失敗は検証対象外。
    }
  });

  group('ファイルブラウザ 一括ダウンロード導線（OS フォルダピッカー）', () {
    testWidgets('一括DL: FakePicker の保存先へ順次転送完了・ファイル 2 件生成', (tester) async {
      Directory('$appDocs/downloads').createSync(recursive: true);
      final content = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final sshClient = FakeSshClient()
        ..sftpClient = TestDownloadSftpClient(
          contentsByPath: {
            '/home/user/a.pdf': content,
            '/home/user/b.pdf': content,
          },
        );
      final picker = FakeBatchDestinationPicker(
        result: FileDestination('$appDocs/downloads'),
      );
      final container = await pumpDownloadScreen(
        tester,
        sshClient: sshClient,
        entries: [downloadEntry('a.pdf'), downloadEntry('b.pdf')],
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
      await settleTransfer(tester, container);
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
        ..sftpClient = TestDownloadSftpClient(
          contentsByPath: {
            '/home/user/a.pdf': Uint8List.fromList([1, 2, 3]),
            '/home/user/b.pdf': Uint8List.fromList([4, 5, 6]),
          },
        );
      final picker = FakeBatchDestinationPicker(result: null); // キャンセル。
      final container = await pumpDownloadScreen(
        tester,
        sshClient: sshClient,
        entries: [downloadEntry('a.pdf'), downloadEntry('b.pdf')],
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
        ..sftpClient = TestDownloadSftpClient(
          contentsByPath: {'/home/user/a.pdf': content},
        );
      final picker = FakeBatchDestinationPicker(
        result: FileDestination('$appDocs/downloads'),
      );
      final container = await pumpDownloadScreen(
        tester,
        sshClient: sshClient,
        entries: [downloadEntry('a.pdf')],
        appDocs: appDocs,
        picker: picker,
      );

      await tester.longPress(find.text('a.pdf'));
      await tester.pump();
      await tester.tap(find.byTooltip('Batch download'));
      await tester.pump();

      // 事前スキャン（destination.exists）が実 IO のため runAsync で進め、
      // awaitingOverwrite → 基盤ダイアログ表示まで待つ。
      await waitUntil(
        tester,
        container,
        () =>
            container.read(downloadProvider).phase ==
            DownloadPhase.awaitingOverwrite,
      );
      await waitForText(tester, 'File already exists');

      // Overwrite 決定（転送開始・進捗シートがアニメーションするため
      // pumpAndSettle は使わず、pump + runAsync で完了まで進める）。
      await tester.tap(find.text('Overwrite'));
      await tester.pump();

      await settleTransfer(tester, container);
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
        ..sftpClient = TestDownloadSftpClient(
          contentsByPath: {
            '/home/user/a.pdf': content,
            '/home/user/b.pdf': content,
          },
        );
      final container = await pumpDownloadScreen(
        tester,
        sshClient: sshClient,
        entries: [downloadEntry('a.pdf'), downloadEntry('b.pdf')],
        appDocs: appDocs,
      );

      // UI のメニューは単一エントリのため、listen 導線（_downloadFlowSub）を
      // 検証する形で startDownloads（一括）を直接開始する。
      final started = container.read(downloadProvider.notifier);
      started.startDownloads([
        downloadEntry('a.pdf'),
        downloadEntry('b.pdf'),
      ], FileDestination('$appDocs/downloads'));

      // 事前スキャン（destination.exists）が実 IO のため runAsync で進め、
      // awaitingOverwrite → 基盤ダイアログ表示まで待つ。
      await waitUntil(
        tester,
        container,
        () =>
            container.read(downloadProvider).phase ==
            DownloadPhase.awaitingOverwrite,
      );
      await waitForText(tester, 'File already exists');

      // Overwrite + 全ファイルに適用
      await tester.tap(find.text('Apply to all'));
      await tester.pump();
      await tester.tap(find.text('Overwrite'));
      await tester.pump();

      await settleTransfer(tester, container);
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
        ..sftpClient = TestDownloadSftpClient(
          contentsByPath: {
            '/home/user/a.pdf': Uint8List.fromList(
              List.generate(300, (i) => i % 256),
            ),
          },
        );
      final picker = FakeBatchDestinationPicker(
        result: FileDestination('$appDocs/downloads'),
      );
      final container = await pumpDownloadScreen(
        tester,
        sshClient: sshClient,
        entries: [downloadEntry('a.pdf')],
        appDocs: appDocs,
        picker: picker,
      );

      await tester.longPress(find.text('a.pdf'));
      await tester.pump();
      await tester.tap(find.byTooltip('Batch download'));
      await tester.pump();

      await waitUntil(
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
