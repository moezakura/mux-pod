// P5: downloadProvider テスト（分割・責務: 初期状態・衝突検出・overwrite/rename/skip・重複宛先の自動リネーム）。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/services/sftp/overwrite_choice.dart';

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
    test('初期状態: idle・items 空・派生値は 0/null', () {
      final container = makeDownloadProviderContainer(
        sshClient: FakeSshClient(),
      );
      addTearDown(container.dispose);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.idle);
      expect(state.items, isEmpty);
      expect(state.collidingItems, isEmpty);
      expect(state.receivedBytes, 0);
      expect(state.totalBytes, 0);
      expect(state.completedCount, 0);
      expect(state.failedCount, 0);
      expect(state.skippedCount, 0);
      expect(state.fraction, isNull);
      expect(state.speedLabel, '');
    });

    test(
      '衝突なし: downloading → completed・bytesReceived==size・sftp.close 不呼',
      () async {
        final content = Uint8List.fromList(List.generate(300, (i) => i % 256));
        final sftp = TestSftpClient(
          contentsByPath: {'/remote/data.bin': content},
          emitChunkSize: 100,
        );
        final sshClient = FakeSshClient()..sftpClient = sftp;
        final container = makeDownloadProviderContainer(sshClient: sshClient);
        addTearDown(container.dispose);
        final notifier = container.read(downloadProvider.notifier);
        final dest = FakeDownloadDestination(tmp.path);

        await notifier.startDownloads([
          entry('/remote/data.bin', size: 300),
        ], dest);

        final state = container.read(downloadProvider);
        expect(state.phase, DownloadPhase.completed);
        expect(state.items, hasLength(1));
        expect(state.items[0].remotePath, '/remote/data.bin');
        // 一括の localPath は表示用 name（実パスは destination が管理）。
        expect(state.items[0].localPath, 'data.bin');
        expect(state.items[0].bytesReceived, 300);
        expect(state.items[0].isCompleted, isTrue);
        expect(state.items[0].isError, isFalse);
        expect(state.completedCount, 1);
        expect(state.failedCount, 0);
        expect(state.totalBytes, 300);
        expect(state.receivedBytes, 300);
        // 端末ファイルへ逐次書込済み。
        expect(File('${tmp.path}/data.bin').readAsBytesSync(), content);
        // 事前スキャンが destination.exists を呼ぶ（衝突なし）。
        expect(dest.existsCalls, ['data.bin']);
        // open は overwrite:false（新規作成）で 1 回だけ。
        expect(dest.openCalls, [('data.bin', false)]);
        // キュー終了時に保存先は 1 回だけ dispose される。
        expect(dest.disposeCalled, isTrue);
        // sftp.close() 禁止契約。
        expect(sftp.closeCalls, 0);
      },
    );

    test('衝突検出: awaitingOverwrite + collidingItems 公開・転送未開始', () async {
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/data.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      // 同名ファイルを事前作成（事前スキャンで検出される）。
      final dest = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);

      await container.read(downloadProvider.notifier).startDownloads([
        entry('/remote/data.bin'),
      ], dest);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.awaitingOverwrite);
      expect(state.collidingItems, hasLength(1));
      expect(state.collidingItems[0].localPath, 'data.bin');
      // 事前スキャンが destination.exists を呼ぶ（衝突あり・転送は開始されない）。
      expect(dest.existsCalls, ['data.bin']);
      expect(dest.openCalls, isEmpty);
      // 転送は開始されない（既存ファイルは未変更）。
      expect(File('${tmp.path}/data.bin').readAsBytesSync(), [9, 9, 9, 9]);
      expect(sftp.closeCalls, 0);
    });

    test('overwrite 決定: 既存ファイルを明示上書きして completed', () async {
      final content = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sftp = TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final dest = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);

      final notifier = container.read(downloadProvider.notifier);
      await notifier.startDownloads([entry('/remote/data.bin')], dest);
      expect(
        container.read(downloadProvider).phase,
        DownloadPhase.awaitingOverwrite,
      );

      await notifier.applyOverwriteDecisions({
        'data.bin': OverwriteChoice.overwrite,
      });

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.items[0].localPath, 'data.bin');
      // overwrite 決定 → open へ overwrite:true が伝搬される（overwrite フラグ検証）。
      expect(state.items[0].overwrite, isTrue);
      expect(dest.openCalls, [('data.bin', true)]);
      // ユーザー明示の上書きで内容が置き換わる。
      expect(File('${tmp.path}/data.bin').readAsBytesSync(), content);
      expect(state.completedCount, 1);
      expect(sftp.closeCalls, 0);
    });

    test('rename 決定: _1 接尾辞で空き名を採番して completed', () async {
      final content = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sftp = TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final dest = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);
      // data_1.bin も既に存在 → data_2.bin に採番される。
      File('${tmp.path}/data_1.bin').writeAsBytesSync([1]);

      final notifier = container.read(downloadProvider.notifier);
      await notifier.startDownloads([entry('/remote/data.bin')], dest);
      expect(
        container.read(downloadProvider).phase,
        DownloadPhase.awaitingOverwrite,
      );

      await notifier.applyOverwriteDecisions({
        'data.bin': OverwriteChoice.rename,
      });

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.items[0].localPath, 'data_2.bin');
      // rename 決定 → _firstAvailableName が destination.exists で空き名を探す
      // （data.bin: 事前スキャン → data_1.bin: 存在 → data_2.bin: 空き）。
      expect(dest.existsCalls, ['data.bin', 'data_1.bin', 'data_2.bin']);
      // 決定した名前を確実に使うため overwrite:true で open される。
      expect(state.items[0].overwrite, isTrue);
      expect(dest.openCalls, [('data_2.bin', true)]);
      expect(File('${tmp.path}/data_2.bin').readAsBytesSync(), content);
      // 元ファイルは変更されない。
      expect(File('${tmp.path}/data.bin').readAsBytesSync(), [9, 9, 9, 9]);
      expect(sftp.closeCalls, 0);
    });

    test('skip 決定: isSkipped・skippedCount==1・キューから除外（ファイル未作成）', () async {
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/data.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final dest = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);

      final notifier = container.read(downloadProvider.notifier);
      await notifier.startDownloads([entry('/remote/data.bin')], dest);
      expect(
        container.read(downloadProvider).phase,
        DownloadPhase.awaitingOverwrite,
      );

      await notifier.applyOverwriteDecisions({
        'data.bin': OverwriteChoice.skip,
      });

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.items[0].isSkipped, isTrue);
      expect(state.skippedCount, 1);
      expect(state.completedCount, 0);
      // スキップは open されない（キューから除外）。
      expect(dest.openCalls, isEmpty);
      // 既存ファイルは未変更（ダウンロードは実行されない）。
      expect(File('${tmp.path}/data.bin').readAsBytesSync(), [9, 9, 9, 9]);
      expect(sftp.closeCalls, 0);
    });

    test('同一バッチ内の重複宛先: 自動リネームで安全側（LOW#3）', () async {
      final sftp = TestSftpClient(
        contentsByPath: {
          '/dir1/x.bin': Uint8List.fromList([1, 2, 3]),
          '/dir2/x.bin': Uint8List.fromList([4, 5, 6]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);
      final dest = FakeDownloadDestination(tmp.path);

      await notifier.startDownloads([
        entry('/dir1/x.bin'),
        entry('/dir2/x.bin'),
      ], dest);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      // 2 つ目は _1 接尾辞で自動リネーム（無言の last-writer-wins 防止）。
      expect(state.items[0].localPath, 'x.bin');
      expect(state.items[1].localPath, 'x_1.bin');
      expect(File('${tmp.path}/x.bin').readAsBytesSync(), [1, 2, 3]);
      expect(File('${tmp.path}/x_1.bin').readAsBytesSync(), [4, 5, 6]);
      expect(state.completedCount, 2);
      // open は x.bin / x_1.bin の順（どちらも新規作成 overwrite:false）。
      expect(dest.openCalls, [('x.bin', false), ('x_1.bin', false)]);
      expect(sftp.closeCalls, 0);
    });
  });
}
