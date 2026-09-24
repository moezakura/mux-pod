// P5: downloadProvider テスト（分割・責務: キャンセル・リセット・転送再開始の冪等性と abort 安全性）。
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
    test('cancel: 冪等・後続キュー未実行・部分削除・sftp.close 不呼', () async {
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
          // a.bin の 2 チャンク目 emit 前で待機（キャンセルまで）。
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeDownloadProviderContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);
      final dest = FakeDownloadDestination(tmp.path);

      // 1 チャンク目（100B）が state 反映されるのを検知。
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

      notifier.cancel();
      expect(container.read(downloadProvider).phase, DownloadPhase.cancelled);
      notifier.cancel(); // 冪等（2 重 no-op・phase 不変）
      expect(container.read(downloadProvider).phase, DownloadPhase.cancelled);
      gate.complete();
      await downloadFuture;

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.cancelled);
      // 後続キュー（b.bin）は未実行: ファイル未作成。
      expect(File('${tmp.path}/b.bin').existsSync(), isFalse);
      // 在途 a.bin の部分ファイルはサービス側で削除済み。
      expect(File('${tmp.path}/a.bin').existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
      sub.close();
    });

    test('キャンセル後の再開始: 新トークンで正常完了（トークン再入バグなし）', () async {
      var holdGate = true;
      final gate = Completer<void>();
      final sftp = TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList(
            List.generate(300, (i) => i % 256),
          ),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (holdGate && i == 1) await gate.future;
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

      // 1 回目: 途中キャンセル。
      final first = notifier.startDownloads([
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;
      notifier.cancel();
      gate.complete();
      await first;
      expect(container.read(downloadProvider).phase, DownloadPhase.cancelled);

      // 2 回目: ゲート解放（新トークンで再開始）→ 正常完了。
      holdGate = false;
      await notifier.startDownloads([
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.items[0].isCompleted, isTrue);
      expect(state.items[0].bytesReceived, 300);
      expect(File('${tmp.path}/a.bin').readAsBytesSync(), hasLength(300));
      expect(sftp.closeCalls, 0);
      sub.close();
    });

    test('reset: completed → idle・items クリア・再開始可能', () async {
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
      await notifier.startDownloads([entry('/remote/a.bin')], dest);
      expect(container.read(downloadProvider).phase, DownloadPhase.completed);

      notifier.reset();
      final idle = container.read(downloadProvider);
      expect(idle.phase, DownloadPhase.idle);
      expect(idle.items, isEmpty);
      expect(idle.speedLabel, '');
      expect(idle.errorMessage, isNull);

      // reset 後に再開始できる（新トークン・新バッチ・別保存先）。
      // 1 回目で書込済みの a.bin が事前スキャン衝突になるのを避けるため別 dir を使用。
      final againDir = '${tmp.path}/again';
      Directory(againDir).createSync();
      await notifier.startDownloads([
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(againDir));
      expect(container.read(downloadProvider).phase, DownloadPhase.completed);
      expect(File('$againDir/a.bin').readAsBytesSync(), [1, 2, 3]);
      expect(sftp.closeCalls, 0);
    });

    test('reset: cancel 直後も idle へ復帰（キャンセル→リセットの妥当フロー）', () async {
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
      final downloadFuture = notifier.startDownloads([
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;

      notifier.cancel();
      expect(container.read(downloadProvider).phase, DownloadPhase.cancelled);
      notifier.reset(); // cancel 直後の reset（UI の妥当フロー）。
      expect(container.read(downloadProvider).phase, DownloadPhase.idle);
      expect(container.read(downloadProvider).items, isEmpty);

      gate.complete();
      await downloadFuture; // 例外なしで安全に完了する。
      expect(container.read(downloadProvider).phase, DownloadPhase.idle);
      expect(sftp.closeCalls, 0);
      sub.close();
    });

    test('転送中の reset: クラッシュせずキューが安全に abort（HIGH#1 回帰）', () async {
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
      final downloadFuture = notifier.startDownloads([
        entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;

      // 転送中に reset（バッチ無効化）→ キューは safe abort。
      notifier.reset();
      expect(container.read(downloadProvider).phase, DownloadPhase.idle);
      expect(container.read(downloadProvider).items, isEmpty);

      gate.complete();
      // 例外（RangeError/TypeError）を投げずに完了する（HIGH#1 回帰）。
      await downloadFuture;
      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.idle);
      expect(state.items, isEmpty);
      // reset がトークン cancel 済みのため在途分は部分削除される。
      expect(File('${tmp.path}/a.bin').existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
      sub.close();
    });
  });
}
