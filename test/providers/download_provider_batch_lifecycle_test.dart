// P5: downloadProvider テスト（分割・責務: 新旧バッチ並走時の保存先 dispose・切断リスナー境界（M1/M2/M4））。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/services/sftp/overwrite_choice.dart';
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
    test('M1: 旧バッチの finally は新バッチの保存先を dispose しない', () async {
      // バッチA 転送中に cancel → 直ちにバッチB 開始（新保存先 destB）。この窓で
      // バッチA の in-flight download が TransferCancelledException になり finally が
      // 走っても、フィールドではなくスナップショットを対象にするため destB は
      // 破棄されない（M1: クロスバッチ誤破棄の構造的排除）。
      final gate = Completer<void>();
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
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      final destA = FakeDownloadDestination(tmp.path);
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

      // バッチA: 転送中（chunk1 でゲート待ち）。
      final batchA = notifier.startDownloads([entry('/remote/a.bin')], destA);
      await reached100.future;

      // キャンセル → 直ちにバッチB 開始（新保存先 destB）。
      notifier.cancel();
      final destBDir = '${tmp.path}/b';
      Directory(destBDir).createSync();
      final destB = FakeDownloadDestination(destBDir);
      final batchB = notifier.startDownloads([entry('/remote/a.bin')], destB);

      // バッチB が sink を開いて書込を始めるまで待つ（同一ゲートで chunk1 待ち）。
      final opened = Stopwatch()..start();
      while (destB.openCalls.isEmpty) {
        if (opened.elapsed > const Duration(seconds: 5)) {
          fail('batch B did not open its destination');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await pumpEventQueue();
      // 旧バッチA の finally はまだ未実行だが、もし destB を誤破棄していたら
      // disposeCalled が立つ（M1 の中核アサーション）。
      expect(destB.disposeCalled, isFalse);

      // ゲート解放 → A はキャンセル検知で finally（自身の destA を破棄）。
      gate.complete();
      await batchA;
      await batchB;

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed); // B は正常完走。
      // B の保存先へは全量書込済み（A の finally が B の保存先に触れていない証）。
      expect(File('$destBDir/a.bin').lengthSync(), 300);
      // A の保存先は A 自身の finally で破棄される（dispose は 1 回ずつ）。
      expect(destA.disposeCalled, isTrue);
      expect(sftp.closeCalls, 0);
      sub.close();
    });

    test('M4: 旧バッチの切断リスナーは新バッチの state を error にしない', () async {
      // キャンセル〜旧バッチ finally（sub.cancel 前）の窓に新バッチが downloading へ
      // 達した状態で切断イベントが届くケース。旧バッチA のリスナー（batch 不一致）は
      // 世代ガードで無視され、新バッチB のリスナーのみが phase=error + トークン
      // cancel する（M4）。旧バグでは A のリスナーが phase=error を書くだけで B の
      // トークンは生きており、B が完走して completed に回復していた。
      final gate = Completer<void>();
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

      // バッチA: 転送中（chunk1 でゲート待ち）。
      final batchA = notifier.startDownloads([
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;
      notifier.cancel();

      // バッチB 開始（downloading 到達・sink オープン済み）。
      final destBDir = '${tmp.path}/b';
      Directory(destBDir).createSync();
      final destB = FakeDownloadDestination(destBDir);
      final batchB = notifier.startDownloads([entry('/remote/a.bin')], destB);

      final opened = Stopwatch()..start();
      while (container.read(downloadProvider).phase !=
              DownloadPhase.downloading ||
          destB.openCalls.isEmpty) {
        if (opened.elapsed > const Duration(seconds: 5)) {
          fail('batch B did not reach downloading');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // この窓に切断イベント → 新旧両リスナーが発火するが、A は世代ガードで無視。
      sshClient.setConnected(SshConnectionState.disconnected);
      await pumpEventQueue();
      expect(container.read(downloadProvider).phase, DownloadPhase.error);

      gate.complete();
      await batchA;
      await batchB;

      final state = container.read(downloadProvider);
      // B のリスナーが B トークンを cancel 済みのため error のまま確定する
      // （旧バグでは A の誤 error 上書き後に B が完走し completed へ回復していた）。
      expect(state.phase, DownloadPhase.error);
      expect(state.items[0].isError, isFalse); // 転送完了していない（邪魔されない）。
      // B の部分ファイルはサービス層の deletePartial で削除済み。
      expect(File('$destBDir/a.bin').existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
      sub.close();
    });

    test('M2: SSH 非接続の error return でも保存先が dispose される', () async {
      final sshClient = FakeSshClient()
        ..state = SshConnectionState.disconnected; // 非接続（isConnected false）。
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);
      final dest = FakeDownloadDestination(tmp.path);

      await notifier.startDownloads([entry('/remote/a.bin')], dest);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.error);
      // ピッカーが iOS startScope 済みでも early return 経路でスコープ解放される（M2）。
      expect(dest.disposeCalled, isTrue);
      expect(sshClient.sftpClient.closeCalls, 0);
    });

    test('M2: awaitingOverwrite 中の SSH 切断 → error + 保存先 dispose', () async {
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);
      final dest = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/a.bin').writeAsBytesSync([9, 9, 9, 9]); // 衝突あり。

      await notifier.startDownloads([entry('/remote/a.bin')], dest);
      expect(
        container.read(downloadProvider).phase,
        DownloadPhase.awaitingOverwrite,
      );

      // 切断（isConnected false）→ applyOverwriteDecisions は error return。
      sshClient.setConnected(SshConnectionState.disconnected);
      await notifier.applyOverwriteDecisions({
        'a.bin': OverwriteChoice.overwrite,
      });

      expect(container.read(downloadProvider).phase, DownloadPhase.error);
      // 設定済みの保存先（iOS スコープ）が解放される（M2）。
      expect(dest.disposeCalled, isTrue);
      // 転送は開始されない（既存ファイルは未変更）。
      expect(File('${tmp.path}/a.bin').readAsBytesSync(), [9, 9, 9, 9]);
      expect(sftp.closeCalls, 0);
    });

    test('M2: awaitingOverwrite 中の新バッチ開始は旧保存先を dispose して置換', () async {
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);
      final destOld = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/a.bin').writeAsBytesSync([9, 9, 9, 9]); // 衝突あり。

      await notifier.startDownloads([entry('/remote/a.bin')], destOld);
      expect(
        container.read(downloadProvider).phase,
        DownloadPhase.awaitingOverwrite,
      );

      // awaitingOverwrite のまま新バッチ開始 → 旧保存先を dispose して置換（M2）。
      final destNewDir = '${tmp.path}/new';
      Directory(destNewDir).createSync();
      final destNew = FakeDownloadDestination(destNewDir);
      await notifier.startDownloads([entry('/remote/a.bin')], destNew);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      // 旧保存先（iOS スコープ等）は解放済み・新バッチは正常に終了（新側も dispose）。
      expect(destOld.disposeCalled, isTrue);
      expect(destNew.disposeCalled, isTrue);
      expect(File('$destNewDir/a.bin').readAsBytesSync(), [1, 2, 3]);
      expect(sftp.closeCalls, 0);
    });
  });
}
