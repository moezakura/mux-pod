import 'dart:async';

import 'package:dartssh2/dartssh2.dart'
    show SftpName, SftpFileAttrs, SftpFileMode;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/file_transfer_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
// XFile は cross_file の正規クラス（file_picker 経由では再エクポートされないため、
// 直接依存のある image_picker 経由で参照する）。
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_sftp_client.dart';
import '../helpers/fake_ssh_client.dart';
import '../helpers/fake_ssh_notifier.dart';

/// テスト用の [PlatformFile] 実装（内容をメモリで保持）。
base class FakePlatformFile extends PlatformFile {
  @override
  final String name;

  @override
  final Uri uri;

  final Uint8List content;

  FakePlatformFile(this.name, {List<int>? content, Uri? uri})
    : content = Uint8List.fromList(content ?? const []),
      uri = uri ?? Uri.file('/local/$name');

  @override
  XFile get xFile => XFile.fromData(content, name: name);

  @override
  Future<int> length() async => content.length;

  @override
  Future<Uint8List> readAsBytes() async => content;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(content);
}

/// 読み込みストリームを外部制御する [PlatformFile]（キャンセル試験用）。
base class ControlledPlatformFile extends FakePlatformFile {
  final StreamController<Uint8List> controller = StreamController();

  ControlledPlatformFile(super.name, {super.content});

  @override
  Stream<Uint8List> readAsByteStream() => controller.stream;
}

/// 読み込みが必ず失敗する [PlatformFile]。
base class ThrowingPlatformFile extends FakePlatformFile {
  ThrowingPlatformFile(super.name);

  @override
  Stream<Uint8List> readAsByteStream() =>
      Stream.error(StateError('local read failure'));
}

/// 非同期イベントを確実に進める。
Future<void> pumpEvents([int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  ProviderContainer makeContainer(FakeSshClient sshClient) {
    final container = ProviderContainer(
      overrides: [
        sshProvider.overrideWith(() => FakeSshNotifier(client: sshClient)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('FileTransferNotifier', () {
    test('初期状態は idle', () {
      final container = makeContainer(FakeSshClient());
      final state = container.read(fileTransferProvider);
      expect(state.phase, FileTransferPhase.idle);
      expect(state.items, isEmpty);
    });

    test('prepare: 衝突なしで confirming になる', () async {
      final ssh = FakeSshClient();
      final container = makeContainer(ssh);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(
            files: [FakePlatformFile('a.txt', content: List.filled(10, 1))],
            remoteDir: '/remote',
          );

      final state = container.read(fileTransferProvider);
      expect(state.phase, FileTransferPhase.confirming);
      expect(state.remoteDir, '/remote');
      expect(state.items, hasLength(1));
      expect(state.items.first.fileName, 'a.txt');
      expect(state.items.first.totalBytes, 10);
      expect(state.items.first.conflict, isFalse);
      expect(state.hasConflicts, isFalse);
    });

    test('prepare: リモート既存ファイルを衝突として検出する', () async {
      final ssh = FakeSshClient();
      ssh.sftpClient = FakeSftpClient(
        entriesByPath: {
          '/remote/a.txt': [SftpNameFactory.file('a.txt')],
        },
      );
      final container = makeContainer(ssh);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(files: [FakePlatformFile('a.txt')], remoteDir: '/remote');

      final state = container.read(fileTransferProvider);
      expect(state.items.first.conflict, isTrue);
      expect(state.hasConflicts, isTrue);
      expect(state.conflictIndexes, [0]);
    });

    test('prepare: SSH 未接続では error になる', () async {
      final container = ProviderContainer(
        overrides: [sshProvider.overrideWith(() => FakeSshNotifier())],
      );
      addTearDown(container.dispose);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(files: [FakePlatformFile('a.txt')], remoteDir: '/remote');

      final state = container.read(fileTransferProvider);
      expect(state.phase, FileTransferPhase.error);
      expect(state.errorMessage, 'ssh-not-available');
    });

    test('prepare: 空リストでは状態を変えない', () async {
      final container = makeContainer(FakeSshClient());

      await container
          .read(fileTransferProvider.notifier)
          .prepare(files: [], remoteDir: '/remote');

      expect(
        container.read(fileTransferProvider).phase,
        FileTransferPhase.idle,
      );
    });

    test('start: 単一ファイルを転送して completed になる', () async {
      final ssh = FakeSshClient();
      final container = makeContainer(ssh);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(
            files: [FakePlatformFile('a.bin', content: List.filled(300, 7))],
            remoteDir: '/remote',
          );
      await container.read(fileTransferProvider.notifier).start();

      final state = container.read(fileTransferProvider);
      expect(state.phase, FileTransferPhase.completed);
      expect(state.items.first.status, FileTransferItemStatus.done);
      expect(state.items.first.remotePath, '/remote/a.bin');
      expect(ssh.sftpClient.openedFiles.single.content.length, 300);
      expect(state.doneCount, 1);
    });

    test('start: 衝突 + overwrite は元名で上書き転送する', () async {
      final ssh = FakeSshClient();
      ssh.sftpClient = FakeSftpClient(
        entriesByPath: {
          '/remote/a.txt': [SftpNameFactory.file('a.txt')],
        },
      );
      final container = makeContainer(ssh);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(files: [FakePlatformFile('a.txt')], remoteDir: '/remote');
      container
          .read(fileTransferProvider.notifier)
          .setConflictResolution(0, ConflictResolution.overwrite);
      await container.read(fileTransferProvider.notifier).start();

      final state = container.read(fileTransferProvider);
      expect(state.items.first.status, FileTransferItemStatus.done);
      expect(state.items.first.remotePath, '/remote/a.txt');
    });

    test('start: 衝突 + rename はユニーク名で転送する', () async {
      final ssh = FakeSshClient();
      ssh.sftpClient = FakeSftpClient(
        entriesByPath: {
          '/remote/a.txt': [SftpNameFactory.file('a.txt')],
        },
      );
      final container = makeContainer(ssh);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(files: [FakePlatformFile('a.txt')], remoteDir: '/remote');
      container
          .read(fileTransferProvider.notifier)
          .setConflictResolution(0, ConflictResolution.rename);
      await container.read(fileTransferProvider.notifier).start();

      final state = container.read(fileTransferProvider);
      expect(state.items.first.status, FileTransferItemStatus.done);
      expect(
        state.items.first.remotePath,
        matches(RegExp(r'^/remote/a_\d{8}_\d{6}_[a-f0-9]{4}\.txt$')),
      );
    });

    test('start: 衝突未解決（prompt 既定）はそのファイルをスキップする', () async {
      final ssh = FakeSshClient();
      ssh.sftpClient = FakeSftpClient(
        entriesByPath: {
          '/remote/a.txt': [SftpNameFactory.file('a.txt')],
        },
      );
      final container = makeContainer(ssh);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(
            files: [FakePlatformFile('a.txt'), FakePlatformFile('b.txt')],
            remoteDir: '/remote',
          );
      await container.read(fileTransferProvider.notifier).start();

      final state = container.read(fileTransferProvider);
      expect(state.phase, FileTransferPhase.completed);
      expect(state.items[0].status, FileTransferItemStatus.skipped);
      expect(state.items[1].status, FileTransferItemStatus.done);
    });

    test('start: autoRename 設定では衝突を確認なしでリネームする', () async {
      final ssh = FakeSshClient();
      ssh.sftpClient = FakeSftpClient(
        entriesByPath: {
          '/remote/a.txt': [SftpNameFactory.file('a.txt')],
        },
      );
      final container = makeContainer(ssh);

      await container
          .read(settingsProvider.notifier)
          .setUploadConflictPolicy(TransferConflictPolicy.autoRename);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(files: [FakePlatformFile('a.txt')], remoteDir: '/remote');
      await container.read(fileTransferProvider.notifier).start();

      final state = container.read(fileTransferProvider);
      expect(state.items.first.status, FileTransferItemStatus.done);
      expect(state.items.first.remotePath, isNot('/remote/a.txt'));
      expect(
        state.items.first.remotePath,
        matches(RegExp(r'^/remote/a_\d{8}_\d{6}_[a-f0-9]{4}\.txt$')),
      );
    });

    test('start: 複数ファイル（並列数2）を全て転送する', () async {
      final ssh = FakeSshClient();
      final container = makeContainer(ssh);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(
            files: [
              FakePlatformFile('a.bin', content: List.filled(50, 1)),
              FakePlatformFile('b.bin', content: List.filled(60, 2)),
              FakePlatformFile('c.bin', content: List.filled(70, 3)),
            ],
            remoteDir: '/remote',
          );
      await container.read(fileTransferProvider.notifier).start();

      final state = container.read(fileTransferProvider);
      expect(state.phase, FileTransferPhase.completed);
      expect(state.doneCount, 3);
      expect(ssh.sftpClient.openedFiles, hasLength(3));
    });

    test('start: バッチ内の重複名は後続を自動リネームする', () async {
      final ssh = FakeSshClient();
      final container = makeContainer(ssh);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(
            files: [FakePlatformFile('dup.txt'), FakePlatformFile('dup.txt')],
            remoteDir: '/remote',
          );
      await container.read(fileTransferProvider.notifier).start();

      final state = container.read(fileTransferProvider);
      expect(state.doneCount, 2);
      expect(state.items[0].remotePath, '/remote/dup.txt');
      expect(state.items[1].remotePath, isNot('/remote/dup.txt'));
    });

    test('start: ソースエラーはそのファイルのみ failed にする', () async {
      final ssh = FakeSshClient();
      final container = makeContainer(ssh);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(
            files: [
              ThrowingPlatformFile('bad.txt'),
              FakePlatformFile('ok.txt'),
            ],
            remoteDir: '/remote',
          );
      await container.read(fileTransferProvider.notifier).start();

      final state = container.read(fileTransferProvider);
      expect(state.phase, FileTransferPhase.completed);
      expect(state.items[0].status, FileTransferItemStatus.failed);
      expect(state.items[0].error, isStateError);
      expect(state.items[1].status, FileTransferItemStatus.done);
    });

    test('cancelFile: 指定ファイルのみキャンセル（skipped）する', () async {
      final ssh = FakeSshClient();
      final container = makeContainer(ssh);
      final controlled = ControlledPlatformFile('big.bin');

      await container
          .read(fileTransferProvider.notifier)
          .prepare(
            files: [controlled, FakePlatformFile('ok.txt')],
            remoteDir: '/remote',
          );
      final startFuture = container.read(fileTransferProvider.notifier).start();
      await pumpEvents();

      // 制御側ストリームの初回チャンク到着後にキャンセル要求 → 次チャンクで中断
      controlled.controller.add(Uint8List.fromList(List.filled(10, 1)));
      await pumpEvents();
      container.read(fileTransferProvider.notifier).cancelFile(0);
      controlled.controller.add(Uint8List.fromList(List.filled(100, 2)));
      await pumpEvents();
      await controlled.controller.close();
      await startFuture;

      final state = container.read(fileTransferProvider);
      expect(state.phase, FileTransferPhase.completed);
      expect(state.items[0].status, FileTransferItemStatus.skipped);
      expect(state.items[1].status, FileTransferItemStatus.done);
      // キャンセルされたファイルの部分ファイルは削除される
      expect(ssh.sftpClient.removeCalls, contains('/remote/big.bin'));
    });

    test('cancelAll: 転送全体をキャンセルする', () async {
      final ssh = FakeSshClient();
      final container = makeContainer(ssh);
      final controlled = ControlledPlatformFile('big.bin');

      await container
          .read(fileTransferProvider.notifier)
          .prepare(files: [controlled], remoteDir: '/remote');
      final startFuture = container.read(fileTransferProvider.notifier).start();
      await pumpEvents();

      controlled.controller.add(Uint8List.fromList(List.filled(10, 1)));
      await pumpEvents();
      container.read(fileTransferProvider.notifier).cancelAll();
      controlled.controller.add(Uint8List.fromList(List.filled(100, 2)));
      await pumpEvents();
      await controlled.controller.close();
      await startFuture;

      final state = container.read(fileTransferProvider);
      expect(state.phase, FileTransferPhase.cancelled);
      expect(state.items.first.status, FileTransferItemStatus.skipped);
      expect(ssh.sftpClient.removeCalls, contains('/remote/big.bin'));
    });

    test('reset: 状態を idle に戻す', () async {
      final ssh = FakeSshClient();
      final container = makeContainer(ssh);

      await container
          .read(fileTransferProvider.notifier)
          .prepare(files: [FakePlatformFile('a.txt')], remoteDir: '/remote');
      await container.read(fileTransferProvider.notifier).start();
      container.read(fileTransferProvider.notifier).reset();

      final state = container.read(fileTransferProvider);
      expect(state.phase, FileTransferPhase.idle);
      expect(state.items, isEmpty);
    });
  });
}

/// テスト用 [SftpName] ファクトリ。
class SftpNameFactory {
  static SftpName file(String name) => SftpName(
    filename: name,
    longname: '-rw-r--r--',
    attr: SftpFileAttrs(mode: SftpFileMode.value(0x81A4)),
  );
}
