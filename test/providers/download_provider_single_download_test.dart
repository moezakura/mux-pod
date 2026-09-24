// P5: downloadProvider テスト（分割・責務: startSingleTmpDownload の tmp→Save-As 単一フロー）。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';

import 'helpers/download_provider_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scope = DownloadProviderTmpScope();
  late String appTmp;

  setUp(() {
    scope.setUp();
    appTmp = scope.appTmp;
  });
  tearDown(scope.tearDown);

  group('downloadProvider.single（startSingleTmpDownload・tmp→Save-As）', () {
    test('tmpDL 成功 → export 成功: completed + localPath 更新 + tmp 削除', () async {
      final content = Uint8List.fromList([1, 2, 3]);
      final sftp = TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final exporter = FakeSaveAsExporter(result: 'Download/data.bin');
      final container = makeDownloadProviderContainer(
        sshClient: sshClient,
        exporter: exporter,
      );
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startSingleTmpDownload(entry('/remote/data.bin'));

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.items, hasLength(1));
      expect(state.items[0].isCompleted, isTrue);
      expect(state.items[0].isError, isFalse);
      // Save-As の戻り値パスで localPath が更新される。
      expect(state.items[0].localPath, 'Download/data.bin');
      // export は tmp 実パスで 1 回だけ呼ばれる（tmp 領域は常に `_1` 採番で
      // 残骸を上書きしない仕様・`_firstAvailablePath`）。
      expect(exporter.calls, ['$appTmp/sftp_download/data_1.bin']);
      // export 後は tmp ファイルが削除される。
      expect(File('$appTmp/sftp_download/data_1.bin').existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
    });

    test('export キャンセル（null）: cancelled + tmp 削除', () async {
      final content = Uint8List.fromList([1, 2, 3]);
      final sftp = TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final exporter = FakeSaveAsExporter(result: null); // Save-As キャンセル。
      final container = makeDownloadProviderContainer(
        sshClient: sshClient,
        exporter: exporter,
      );
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startSingleTmpDownload(entry('/remote/data.bin'));

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.cancelled);
      // localPath は tmp パスのまま（転送中断・確定済み）。
      expect(state.items[0].localPath, '$appTmp/sftp_download/data_1.bin');
      expect(File('$appTmp/sftp_download/data_1.bin').existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
    });

    test('export throw: error + tmp 削除', () async {
      final content = Uint8List.fromList([1, 2, 3]);
      final sftp = TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final exporter = FakeSaveAsExporter(
        error: const FileSystemException('save failed'),
      );
      final container = makeDownloadProviderContainer(
        sshClient: sshClient,
        exporter: exporter,
      );
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startSingleTmpDownload(entry('/remote/data.bin'));

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.error);
      expect(state.errorMessage, isNotNull);
      expect(exporter.calls, ['$appTmp/sftp_download/data_1.bin']);
      // 失敗時も tmp 残骸は削除される（ベストエフォート）。
      expect(File('$appTmp/sftp_download/data_1.bin').existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
    });

    test('ダウンロード失敗: export されず tmp 削除', () async {
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/data.bin': Uint8List.fromList([1, 2, 3]),
        },
        failOpenFor: {'/remote/data.bin'}, // 転送自体が失敗。
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final exporter = FakeSaveAsExporter(result: 'Download/data.bin');
      final container = makeDownloadProviderContainer(
        sshClient: sshClient,
        exporter: exporter,
      );
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startSingleTmpDownload(entry('/remote/data.bin'));

      final state = container.read(downloadProvider);
      expect(state.items[0].isError, isTrue);
      // M3: 単一バッチは _runQueue が中間 completed を publish しないため、転送失敗は
      // 最終確定（error）として startSingleTmpDownload が集約する。
      expect(state.phase, DownloadPhase.error);
      expect(state.errorMessage, isNotNull);
      // 失敗時は Save-As エクスポートへ進まない。
      expect(exporter.calls, isEmpty);
      expect(File('$appTmp/sftp_download/data_1.bin').existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
    });

    test('単一: 進捗（100ms 間引き）と完了通知が記録される', () async {
      var now = DateTime(2026, 1, 1);
      final gate = Completer<void>();
      final notification = FakeSshForegroundTaskService();
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/s.bin': Uint8List.fromList(List.generate(200, (i) => i)),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final exporter = FakeSaveAsExporter(result: 'Download/s.bin');
      final container = makeDownloadProviderContainer(
        sshClient: sshClient,
        clock: () => now,
        notificationService: notification,
        exporter: exporter,
      );
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      final reached100 = Completer<void>();
      final sub = container.listen<DownloadState>(downloadProvider, (
        prev,
        next,
      ) {
        if (!reached100.isCompleted &&
            next.items.isNotEmpty &&
            next.items[0].bytesReceived >= 100) {
          reached100.complete();
        }
      });
      final downloadFuture = notifier.startSingleTmpDownload(
        entry('/remote/s.bin', size: 200),
      );
      await reached100.future;
      expect(container.read(downloadProvider).phase, DownloadPhase.downloading);

      now = now.add(const Duration(milliseconds: 200));
      gate.complete();
      await downloadFuture;

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.items[0].localPath, 'Download/s.bin');
      // 完了サマリ通知（成功 1 / 失敗 0 / スキップ 0）が記録される。
      final texts = notification.updateCalls.map((c) => c.text ?? '').toList();
      expect(texts.last, contains('1 succeeded'));
      expect(sftp.closeCalls, 0);
      sub.close();
    });

    test(
      'M3: 単一フローは中間 completed を publish せず downloading→exporting→completed',
      () async {
        final sftp = TestSftpClient(
          contentsByPath: {
            '/remote/data.bin': Uint8List.fromList([1, 2, 3]),
          },
        );
        final sshClient = FakeSshClient()..sftpClient = sftp;
        final notification = FakeSshForegroundTaskService();
        final exporter = GatedSaveAsExporter(
          result: 'Download/data.bin',
          started: Completer<void>(),
          release: Completer<void>(),
        );
        final container = makeDownloadProviderContainer(
          sshClient: sshClient,
          notificationService: notification,
          exporter: exporter,
        );
        addTearDown(container.dispose);
        final notifier = container.read(downloadProvider.notifier);

        final phases = <DownloadPhase>[];
        final sub = container.listen<DownloadState>(downloadProvider, (
          prev,
          next,
        ) {
          if (prev?.phase != next.phase) phases.add(next.phase);
        });
        final downloadFuture = notifier.startSingleTmpDownload(
          entry('/remote/data.bin'),
        );

        // 転送完了後・export 保留中: exporting（Save-As 待ち）であること。
        await exporter.started.future;
        await pumpEventQueue();
        final during = container.read(downloadProvider);
        expect(during.phase, DownloadPhase.exporting);
        // 中間 completed の publish・完了通知は発生していない（M3）。
        expect(phases.contains(DownloadPhase.completed), isFalse);
        expect(
          notification.updateCalls
              .map((c) => c.text ?? '')
              .where((t) => t.contains('succeeded')),
          isEmpty,
        );

        exporter.release.complete();
        await downloadFuture;

        final done = container.read(downloadProvider);
        expect(done.phase, DownloadPhase.completed);
        expect(done.items[0].localPath, 'Download/data.bin');
        // 遷移は downloading → exporting → completed の 1 巡のみ（中間 completed なし）。
        expect(phases, [
          DownloadPhase.downloading,
          DownloadPhase.exporting,
          DownloadPhase.completed,
        ]);
        // 完了通知は 1 回だけ（二重 notifDownloadComplete なし・M3）。
        final texts = notification.updateCalls
            .map((c) => c.text ?? '')
            .toList();
        expect(texts.where((t) => t.contains('succeeded')).length, 1);
        expect(sftp.closeCalls, 0);
        sub.close();
      },
    );
  });
}
