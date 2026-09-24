// P5: downloadProvider テスト（分割・責務: SSH 切断・部分失敗続行・切断×キャンセル競合・openSftp 失敗）。
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
    test('SSH 切断: error + 部分削除 + 後続未実行（cancelled へ上書きしない）', () async {
      final gate = Completer<void>();
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList(
            List.generate(300, (i) => i % 256),
          ),
          '/remote/b.bin': Uint8List.fromList(List.generate(50, (i) => i)),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);
      final dest = FakeDownloadDestination(tmp.path);

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
        entry('/remote/b.bin'),
      ], dest);
      await reached100.future;

      // 転送中に SSH 切断 → トークン cancel + phase=error（broadcast 配送はマイクロタスク）。
      sshClient.setConnected(SshConnectionState.disconnected);
      await pumpEventQueue();
      expect(container.read(downloadProvider).phase, DownloadPhase.error);
      gate.complete();
      await downloadFuture;

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.error);
      // 在途 a.bin の部分削除 + 後続 b.bin 未実行。
      expect(File('${tmp.path}/a.bin').existsSync(), isFalse);
      expect(File('${tmp.path}/b.bin').existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
      sub.close();
    });

    test('順次一括・部分失敗続行 + 集計（failed/completed・closeCalls==0）', () async {
      final contentB = Uint8List.fromList(List.generate(50, (i) => i));
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3, 4]),
          '/remote/b.bin': contentB,
        },
        failOpenFor: {'/remote/a.bin'}, // 1 件目が open 失敗
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);
      final dest = FakeDownloadDestination(tmp.path);

      await notifier.startDownloads([
        entry('/remote/a.bin'),
        entry('/remote/b.bin'),
      ], dest);

      final state = container.read(downloadProvider);
      // 失敗は記録して続行し、最終 phase=completed（errorItems>0）。
      expect(state.phase, DownloadPhase.completed);
      expect(state.items[0].isError, isTrue);
      expect(state.items[0].errorMessage, isNotNull);
      expect(state.items[1].isCompleted, isTrue);
      expect(state.items[1].bytesReceived, 50);
      expect(state.failedCount, 1);
      expect(state.completedCount, 1);
      expect(state.skippedCount, 0);
      expect(state.errorMessage, isNotNull); // 失敗ありの集約報告
      // 2 件目は正常に書込済み・1 件目の残骸なし。
      expect(File('${tmp.path}/b.bin').readAsBytesSync(), contentB);
      expect(File('${tmp.path}/a.bin').existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
    });

    test('切断×キャンセル競合(a): cancel 先行 → cancelled を維持', () async {
      final gate = Completer<void>();
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList(List.generate(300, (i) => i)),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
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
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;

      // cancel 先行 → phase=cancelled。
      notifier.cancel();
      expect(container.read(downloadProvider).phase, DownloadPhase.cancelled);
      // その後に切断イベント → phase ガードで no-op（cancelled へ上書きしない）。
      sshClient.setConnected(SshConnectionState.disconnected);
      gate.complete();
      await downloadFuture;

      expect(container.read(downloadProvider).phase, DownloadPhase.cancelled);
      expect(sftp.closeCalls, 0);
      sub.close();
    });

    test('切断×キャンセル競合(b): 切断先行 → error を維持', () async {
      final gate = Completer<void>();
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList(List.generate(300, (i) => i)),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
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
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;

      // 切断先行 → phase=error + トークン cancel（broadcast 配送はマイクロタスク）。
      sshClient.setConnected(SshConnectionState.disconnected);
      await pumpEventQueue();
      expect(container.read(downloadProvider).phase, DownloadPhase.error);
      // その後に cancel() → phase ガード（downloading 以外）で no-op。
      notifier.cancel();
      gate.complete();
      await downloadFuture;

      expect(container.read(downloadProvider).phase, DownloadPhase.error);
      expect(sftp.closeCalls, 0);
      sub.close();
    });

    test('openSftp 失敗: 例外を投げず phase=error（MEDIUM#2 回帰）', () async {
      final sshClient = OpenSftpFailingSshClient();
      sshClient.sftpClient = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);
      final dest = FakeDownloadDestination(tmp.path);

      // 契約どおり例外を投げない（Future<void> が正常完了）。
      await notifier.startDownloads([entry('/remote/a.bin')], dest);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.error); // 膠着（downloading のまま）しない。
      expect(state.errorMessage, isNotNull); // state へ反映。
      // finally に入る前に return する経路でも保存先は解放される（M2）。
      expect(dest.disposeCalled, isTrue);
      expect(sshClient.sftpClient.closeCalls, 0);
    });
  });
}
