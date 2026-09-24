// P5: downloadProvider テスト（分割・責務: fraction 進捗と speedLabel（注入クロック・間引き））。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';

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
    test('fraction: 既知サイズは部分進捗（0<f<1）・未知（stat 失敗）は null', () async {
      // 既知サイズ（300B・2 チャンクで 100B まで反映された状態）。
      final gate = Completer<void>();
      final sftpKnown = TestSftpClient(
        contentsByPath: {
          '/remote/k.bin': Uint8List.fromList(List.generate(300, (i) => i)),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftpKnown;
      final container = makeDownloadProviderContainer(sshClient: sshClient);
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
        entry('/remote/k.bin', size: 300),
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;

      final mid = container.read(downloadProvider);
      expect(mid.items[0].totalBytes, 300);
      expect(mid.fraction, isNotNull);
      expect(mid.fraction, closeTo(100 / 300, 0.001));
      gate.complete();
      await downloadFuture;
      sub.close();
      expect(container.read(downloadProvider).phase, DownloadPhase.completed);

      // サイズ未知（stat 失敗）: fraction == null（不確定表示）。
      final sftpUnknown = TestSftpClient(
        contentsByPath: {
          '/remote/u.bin': Uint8List.fromList(List.generate(50, (i) => i)),
        },
        failStatFor: {'/remote/u.bin'},
      );
      sshClient.sftpClient = sftpUnknown;
      await notifier.startDownloads([
        entry('/remote/u.bin'),
      ], FakeDownloadDestination(tmp.path));
      final done = container.read(downloadProvider);
      expect(done.items[0].totalBytes, 0); // 未知
      expect(done.fraction, isNull);
      expect(done.items[0].bytesReceived, 50);
      expect(done.phase, DownloadPhase.completed);
    });

    test('speedLabel: 100ms 間引き + TransferSpeedEma（注入クロック）', () async {
      var now = DateTime(2026, 1, 1);
      final gate = Completer<void>();
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
      // 1 回目サンプル: EMA 初回は 0 → '0.0 B/s'。
      expect(container.read(downloadProvider).speedLabel, '0.0 B/s');

      // 200ms 進めて 2 チャンク目を流す → 100B / 0.2s = 500 B/s。
      now = now.add(const Duration(milliseconds: 200));
      gate.complete();
      await downloadFuture;

      final state = container.read(downloadProvider);
      expect(state.speedLabel, '500.0 B/s');
      expect(state.phase, DownloadPhase.completed);
      expect(state.items[0].bytesReceived, 200);
      expect(sftp.closeCalls, 0);
      sub.close();
    });
  });
}
