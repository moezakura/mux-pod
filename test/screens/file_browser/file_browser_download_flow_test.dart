import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_save_as_exporter.dart';
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

  group('ファイルブラウザ 単一ダウンロード導線（tmp→Save-As）', () {
    testWidgets('単一DL: メニュー → 一時DL → Save-As 確定 → completed', (tester) async {
      final content = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final sshClient = FakeSshClient()
        ..sftpClient = TestDownloadSftpClient(
          contentsByPath: {'/home/user/report.pdf': content},
        );
      final exporter = FakeSaveAsExporter(result: 'Download/report.pdf');
      final container = await pumpDownloadScreen(
        tester,
        sshClient: sshClient,
        entries: [downloadEntry('report.pdf')],
        appDocs: appDocs,
        appTmp: appTmp,
        exporter: exporter,
      );

      // メニュー → Download（保存先選択は OS Save-As が担うためダイアログなし）。
      await tester.tap(find.text('report.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pump();
      await settleTransfer(tester, container);

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
        ..sftpClient = TestDownloadSftpClient(
          contentsByPath: {'/home/user/report.pdf': content},
        );
      final exporter = FakeSaveAsExporter(result: null); // Save-As キャンセル。
      final container = await pumpDownloadScreen(
        tester,
        sshClient: sshClient,
        entries: [downloadEntry('report.pdf')],
        appDocs: appDocs,
        appTmp: appTmp,
        exporter: exporter,
      );

      await tester.tap(find.text('report.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pump();
      await settleTransfer(tester, container);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.cancelled);
      // tmp 残骸は削除される。
      expect(File('$appTmp/sftp_download/report_1.pdf').existsSync(), isFalse);
      expect(sshClient.sftpClient.closeCalls, 0);
    });
  });
}
