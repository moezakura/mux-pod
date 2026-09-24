// P5: downloadProvider テスト（分割・責務: TransferNotificationService 連携（進捗/完了/キャンセル/失敗/未起動/throw））。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import 'helpers/download_provider_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scope = DownloadProviderTmpScope();
  late Directory tmp;

  setUp(() {
    scope.setUp();
    tmp = scope.tmp;
  });
  tearDown(scope.tearDown);

  group('downloadProvider', () {
    test('通知: 進捗（100ms 間引き同期）と完了サマリが updateCalls に記録される', () async {
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
      final container = makeDownloadProviderContainer(
        sshClient: sshClient,
        clock: () => now,
        notificationService: notification,
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
      final downloadFuture = notifier.startDownloads([
        entry('/remote/s.bin', size: 200),
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;
      // 1 回目 publish（進捗通知 1 回目）が記録されている。
      expect(notification.updateCalls, isNotEmpty);
      expect(notification.updateCalls.first.text, contains('Downloading'));

      now = now.add(const Duration(milliseconds: 200));
      gate.complete();
      await downloadFuture;
      await pumpEventQueue();

      final texts = notification.updateCalls.map((c) => c.text ?? '').toList();
      expect(texts.any((t) => t.contains('Downloading')), isTrue);
      // 完了サマリ（成功 a / 失敗 b / スキップ c）が最後に記録される。
      expect(texts.last, contains('Download complete'));
      // 転送中にサービスを停止しない。
      expect(notification.stopCalls, 0);
      expect(sftp.closeCalls, 0);
      sub.close();
    });

    test('通知: キャンセル時にキャンセル文言が記録される', () async {
      final gate = Completer<void>();
      final notification = FakeSshForegroundTaskService();
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList(
            List.generate(300, (i) => i % 256),
          ),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(
        sshClient: sshClient,
        notificationService: notification,
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
      final downloadFuture = notifier.startDownloads([
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;

      notifier.cancel();
      await pumpEventQueue(); // キャンセル通知（fire-and-forget）の反映。
      expect(notification.updateCalls, isNotEmpty);
      expect(
        notification.updateCalls.last.text,
        contains('Download cancelled'),
      );
      gate.complete();
      await downloadFuture;
      expect(notification.stopCalls, 0);
      sub.close();
    });

    test('通知: SSH 切断で失敗文言が記録される', () async {
      final gate = Completer<void>();
      final notification = FakeSshForegroundTaskService();
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList(
            List.generate(300, (i) => i % 256),
          ),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(
        sshClient: sshClient,
        notificationService: notification,
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
      final downloadFuture = notifier.startDownloads([
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;

      sshClient.setConnected(SshConnectionState.disconnected);
      await pumpEventQueue(); // 失敗通知の反映。
      expect(notification.updateCalls, isNotEmpty);
      expect(notification.updateCalls.last.text, contains('Download failed'));

      gate.complete();
      await downloadFuture;
      expect(notification.stopCalls, 0);
      sub.close();
    });

    test('通知: サービス未起動（serviceRunning=false）は no-op・転送は続行', () async {
      final notification = FakeSshForegroundTaskService()
        ..serviceRunning = false;
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(
        sshClient: sshClient,
        notificationService: notification,
      );
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startDownloads([
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed); // 転送は正常完走。
      expect(state.items[0].isCompleted, isTrue);
      expect(File('${tmp.path}/a.bin').readAsBytesSync(), [1, 2, 3]);
      // サービス未起動は通知を記録しない（no-op）。
      expect(notification.updateCalls, isEmpty);
      expect(notification.stopCalls, 0);
      expect(sftp.closeCalls, 0);
    });

    test('通知: 更新 throw（throwOnUpdate）でも転送は正常完走（握りつぶし）', () async {
      final notification = FakeSshForegroundTaskService()..throwOnUpdate = true;
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(
        sshClient: sshClient,
        notificationService: notification,
      );
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      // 例外を UI に投げずに正常完了する（_notify 内部で握りつぶし）。
      await notifier.startDownloads([
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(File('${tmp.path}/a.bin').readAsBytesSync(), [1, 2, 3]);
      expect(notification.updateCalls, isEmpty); // throw 前なので記録なし。
      expect(notification.stopCalls, 0);
      expect(sftp.closeCalls, 0);
    });
  });
}
