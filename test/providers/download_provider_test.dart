import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/services/background/foreground_task_service.dart';
import 'package:flutter_muxpod/services/sftp/file_entry.dart';
import 'package:flutter_muxpod/services/sftp/overwrite_choice.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../helpers/fake_settings_notifier.dart';
import '../helpers/fake_sftp_client.dart';
import '../helpers/fake_ssh_client.dart';
import '../helpers/fake_ssh_foreground_task_service.dart';
import '../helpers/fake_ssh_notifier.dart';

/// `openSftp()` が throw するクライアント（MEDIUM#2 の回帰テスト用）。
class _OpenSftpFailingSshClient extends FakeSshClient {
  @override
  Future<SftpClient> openSftp() async {
    throw SshConnectionError('sftp unavailable');
  }
}

/// [FakeSftpClient] を継承した download 系テスト用クライアント。
///
/// - `stat`: [failStatFor] のパスは例外（サイズ未知再現）・contentsByPath にあれば
///   実サイズを返す。
/// - `open`: [failOpenFor] のパスは例外（アイテム単位失敗再現）・それ以外は
///   [emitChunkSize] / [beforeEmit] 付き [FakeSftpFile] を返す。
class _TestSftpClient extends FakeSftpClient {
  _TestSftpClient({
    required super.contentsByPath,
    this.emitChunkSize,
    this.beforeEmit,
    this.failOpenFor = const {},
    this.failStatFor = const {},
  });

  final int? emitChunkSize;
  final Future<void> Function(int chunkIndex)? beforeEmit;
  final Set<String> failOpenFor;
  final Set<String> failStatFor;

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    if (failStatFor.contains(path)) {
      throw SftpStatusError(SftpStatusCode.noSuchFile, 'No such file');
    }
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
    if (failOpenFor.contains(path)) {
      throw SftpStatusError(SftpStatusCode.failure, 'open boom');
    }
    return FakeSftpFile(
      this,
      contentsByPath[path] ?? Uint8List(0),
      emitChunkSize: emitChunkSize,
      beforeEmit: beforeEmit,
    );
  }
}

FileEntry _entry(String fullPath, {int? size = 123}) => FileEntry(
  name: fullPath.split('/').last,
  fullPath: fullPath,
  isDirectory: false,
  size: size,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('download_provider_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // 削除失敗は検証対象外。
    }
  });

  ProviderContainer makeContainer({
    required FakeSshClient sshClient,
    DateTime Function()? clock,
    TransferNotificationService? notificationService,
  }) {
    return ProviderContainer(
      overrides: [
        sshProvider.overrideWith(() => FakeSshNotifier(client: sshClient)),
        settingsProvider.overrideWith(FakeSettingsNotifier.new),
        if (clock != null || notificationService != null)
          downloadProvider.overrideWith(
            () => DownloadNotifier(
              clock: clock,
              notificationService: notificationService,
            ),
          ),
      ],
    );
  }

  group('downloadProvider', () {
    test('初期状態: idle・items 空・派生値は 0/null', () {
      final container = makeContainer(sshClient: FakeSshClient());
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
        final sftp = _TestSftpClient(
          contentsByPath: {'/remote/data.bin': content},
          emitChunkSize: 100,
        );
        final sshClient = FakeSshClient()..sftpClient = sftp;
        final container = makeContainer(sshClient: sshClient);
        addTearDown(container.dispose);
        final notifier = container.read(downloadProvider.notifier);

        await notifier.startDownloads([
          _entry('/remote/data.bin', size: 300),
        ], tmp.path);

        final state = container.read(downloadProvider);
        expect(state.phase, DownloadPhase.completed);
        expect(state.items, hasLength(1));
        expect(state.items[0].remotePath, '/remote/data.bin');
        expect(state.items[0].localPath, '${tmp.path}/data.bin');
        expect(state.items[0].bytesReceived, 300);
        expect(state.items[0].isCompleted, isTrue);
        expect(state.items[0].isError, isFalse);
        expect(state.completedCount, 1);
        expect(state.failedCount, 0);
        expect(state.totalBytes, 300);
        expect(state.receivedBytes, 300);
        // 端末ファイルへ逐次書込済み。
        expect(File('${tmp.path}/data.bin').readAsBytesSync(), content);
        // sftp.close() 禁止契約。
        expect(sftp.closeCalls, 0);
      },
    );

    test('衝突検出: awaitingOverwrite + collidingItems 公開・転送未開始', () async {
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/data.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      // 同名ファイルを事前作成（事前スキャンで検出される）。
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);

      await container.read(downloadProvider.notifier).startDownloads([
        _entry('/remote/data.bin'),
      ], tmp.path);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.awaitingOverwrite);
      expect(state.collidingItems, hasLength(1));
      expect(state.collidingItems[0].localPath, '${tmp.path}/data.bin');
      // 転送は開始されない（既存ファイルは未変更）。
      expect(File('${tmp.path}/data.bin').readAsBytesSync(), [9, 9, 9, 9]);
      expect(sftp.closeCalls, 0);
    });

    test('overwrite 決定: 既存ファイルを明示上書きして completed', () async {
      final content = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);

      final notifier = container.read(downloadProvider.notifier);
      await notifier.startDownloads([_entry('/remote/data.bin')], tmp.path);
      expect(
        container.read(downloadProvider).phase,
        DownloadPhase.awaitingOverwrite,
      );

      await notifier.applyOverwriteDecisions({
        '${tmp.path}/data.bin': OverwriteChoice.overwrite,
      });

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.items[0].localPath, '${tmp.path}/data.bin');
      // ユーザー明示の上書きで内容が置き換わる。
      expect(File('${tmp.path}/data.bin').readAsBytesSync(), content);
      expect(state.completedCount, 1);
      expect(sftp.closeCalls, 0);
    });

    test('rename 決定: _1 接尾辞で空き名を採番して completed', () async {
      final content = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);
      // data_1.bin も既に存在 → data_2.bin に採番される。
      File('${tmp.path}/data_1.bin').writeAsBytesSync([1]);

      final notifier = container.read(downloadProvider.notifier);
      await notifier.startDownloads([_entry('/remote/data.bin')], tmp.path);
      expect(
        container.read(downloadProvider).phase,
        DownloadPhase.awaitingOverwrite,
      );

      await notifier.applyOverwriteDecisions({
        '${tmp.path}/data.bin': OverwriteChoice.rename,
      });

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.items[0].localPath, '${tmp.path}/data_2.bin');
      expect(File('${tmp.path}/data_2.bin').readAsBytesSync(), content);
      // 元ファイルは変更されない。
      expect(File('${tmp.path}/data.bin').readAsBytesSync(), [9, 9, 9, 9]);
      expect(sftp.closeCalls, 0);
    });

    test('skip 決定: isSkipped・skippedCount==1・キューから除外（ファイル未作成）', () async {
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/data.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);

      final notifier = container.read(downloadProvider.notifier);
      await notifier.startDownloads([_entry('/remote/data.bin')], tmp.path);
      expect(
        container.read(downloadProvider).phase,
        DownloadPhase.awaitingOverwrite,
      );

      await notifier.applyOverwriteDecisions({
        '${tmp.path}/data.bin': OverwriteChoice.skip,
      });

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.items[0].isSkipped, isTrue);
      expect(state.skippedCount, 1);
      expect(state.completedCount, 0);
      // 既存ファイルは未変更（ダウンロードは実行されない）。
      expect(File('${tmp.path}/data.bin').readAsBytesSync(), [9, 9, 9, 9]);
      expect(sftp.closeCalls, 0);
    });

    test('cancel: 冪等・後続キュー未実行・部分削除・sftp.close 不呼', () async {
      final gate = Completer<void>();
      final sftp = _TestSftpClient(
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
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

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
        _entry('/remote/a.bin'),
        _entry('/remote/b.bin'),
      ], tmp.path);
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
      final sftp = _TestSftpClient(
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
      final container = makeContainer(sshClient: sshClient);
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
        _entry('/remote/a.bin'),
      ], tmp.path);
      await reached100.future;
      notifier.cancel();
      gate.complete();
      await first;
      expect(container.read(downloadProvider).phase, DownloadPhase.cancelled);

      // 2 回目: ゲート解放（新トークンで再開始）→ 正常完了。
      holdGate = false;
      await notifier.startDownloads([_entry('/remote/a.bin')], tmp.path);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(state.items[0].isCompleted, isTrue);
      expect(state.items[0].bytesReceived, 300);
      expect(File('${tmp.path}/a.bin').readAsBytesSync(), hasLength(300));
      expect(sftp.closeCalls, 0);
      sub.close();
    });

    test('SSH 切断: error + 部分削除 + 後続未実行（cancelled へ上書きしない）', () async {
      final gate = Completer<void>();
      final sftp = _TestSftpClient(
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
      final container = makeContainer(sshClient: sshClient);
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
        _entry('/remote/a.bin'),
        _entry('/remote/b.bin'),
      ], tmp.path);
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
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3, 4]),
          '/remote/b.bin': contentB,
        },
        failOpenFor: {'/remote/a.bin'}, // 1 件目が open 失敗
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startDownloads([
        _entry('/remote/a.bin'),
        _entry('/remote/b.bin'),
      ], tmp.path);

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
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList(List.generate(300, (i) => i)),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
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
        _entry('/remote/a.bin'),
      ], tmp.path);
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
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList(List.generate(300, (i) => i)),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
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
        _entry('/remote/a.bin'),
      ], tmp.path);
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

    test('fraction: 既知サイズは部分進捗（0<f<1）・未知（stat 失敗）は null', () async {
      // 既知サイズ（300B・2 チャンクで 100B まで反映された状態）。
      final gate = Completer<void>();
      final sftpKnown = _TestSftpClient(
        contentsByPath: {
          '/remote/k.bin': Uint8List.fromList(List.generate(300, (i) => i)),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftpKnown;
      final container = makeContainer(sshClient: sshClient);
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
        _entry('/remote/k.bin', size: 300),
      ], tmp.path);
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
      final sftpUnknown = _TestSftpClient(
        contentsByPath: {
          '/remote/u.bin': Uint8List.fromList(List.generate(50, (i) => i)),
        },
        failStatFor: {'/remote/u.bin'},
      );
      sshClient.sftpClient = sftpUnknown;
      await notifier.startDownloads([_entry('/remote/u.bin')], tmp.path);
      final done = container.read(downloadProvider);
      expect(done.items[0].totalBytes, 0); // 未知
      expect(done.fraction, isNull);
      expect(done.items[0].bytesReceived, 50);
      expect(done.phase, DownloadPhase.completed);
    });

    test('speedLabel: 100ms 間引き + TransferSpeedEma（注入クロック）', () async {
      var now = DateTime(2026, 1, 1);
      final gate = Completer<void>();
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/s.bin': Uint8List.fromList(List.generate(200, (i) => i)),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient, clock: () => now);
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
        _entry('/remote/s.bin', size: 200),
      ], tmp.path);
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

    test('reset: completed → idle・items クリア・再開始可能', () async {
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startDownloads([_entry('/remote/a.bin')], tmp.path);
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
      await notifier.startDownloads([_entry('/remote/a.bin')], againDir);
      expect(container.read(downloadProvider).phase, DownloadPhase.completed);
      expect(File('$againDir/a.bin').readAsBytesSync(), [1, 2, 3]);
      expect(sftp.closeCalls, 0);
    });

    test('reset: cancel 直後も idle へ復帰（キャンセル→リセットの妥当フロー）', () async {
      final gate = Completer<void>();
      final sftp = _TestSftpClient(
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
      final container = makeContainer(sshClient: sshClient);
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
        _entry('/remote/a.bin'),
      ], tmp.path);
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
      final sftp = _TestSftpClient(
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
      final container = makeContainer(sshClient: sshClient);
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
        _entry('/remote/a.bin'),
      ], tmp.path);
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

    test('openSftp 失敗: 例外を投げず phase=error（MEDIUM#2 回帰）', () async {
      final sshClient = _OpenSftpFailingSshClient();
      sshClient.sftpClient = _TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      // 契約どおり例外を投げない（Future<void> が正常完了）。
      await notifier.startDownloads([_entry('/remote/a.bin')], tmp.path);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.error); // 膠着（downloading のまま）しない。
      expect(state.errorMessage, isNotNull); // state へ反映。
      expect(sshClient.sftpClient.closeCalls, 0);
    });

    test('同一バッチ内の重複宛先: 自動リネームで安全側（LOW#3）', () async {
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/dir1/x.bin': Uint8List.fromList([1, 2, 3]),
          '/dir2/x.bin': Uint8List.fromList([4, 5, 6]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startDownloads([
        _entry('/dir1/x.bin'),
        _entry('/dir2/x.bin'),
      ], tmp.path);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      // 2 つ目は _1 接尾辞で自動リネーム（無言の last-writer-wins 防止）。
      expect(state.items[0].localPath, '${tmp.path}/x.bin');
      expect(state.items[1].localPath, '${tmp.path}/x_1.bin');
      expect(File('${tmp.path}/x.bin').readAsBytesSync(), [1, 2, 3]);
      expect(File('${tmp.path}/x_1.bin').readAsBytesSync(), [4, 5, 6]);
      expect(state.completedCount, 2);
      expect(sftp.closeCalls, 0);
    });

    test('通知: 進捗（100ms 間引き同期）と完了サマリが updateCalls に記録される', () async {
      var now = DateTime(2026, 1, 1);
      final gate = Completer<void>();
      final notification = FakeSshForegroundTaskService();
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/s.bin': Uint8List.fromList(List.generate(200, (i) => i)),
        },
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(
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
        _entry('/remote/s.bin', size: 200),
      ], tmp.path);
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
      final sftp = _TestSftpClient(
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
      final container = makeContainer(
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
        _entry('/remote/a.bin'),
      ], tmp.path);
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
      final sftp = _TestSftpClient(
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
      final container = makeContainer(
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
        _entry('/remote/a.bin'),
      ], tmp.path);
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
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(
        sshClient: sshClient,
        notificationService: notification,
      );
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startDownloads([_entry('/remote/a.bin')], tmp.path);

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
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(
        sshClient: sshClient,
        notificationService: notification,
      );
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      // 例外を UI に投げずに正常完了する（_notify 内部で握りつぶし）。
      await notifier.startDownloads([_entry('/remote/a.bin')], tmp.path);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(File('${tmp.path}/a.bin').readAsBytesSync(), [1, 2, 3]);
      expect(notification.updateCalls, isEmpty); // throw 前なので記録なし。
      expect(notification.stopCalls, 0);
      expect(sftp.closeCalls, 0);
    });
  });
}
