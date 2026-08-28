import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/services/background/foreground_task_service.dart';
import 'package:flutter_muxpod/services/download/download_destination.dart';
import 'package:flutter_muxpod/services/download/file_destination.dart';
import 'package:flutter_muxpod/services/download/save_as_exporter.dart';
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

/// 実ディレクトリベースの [DownloadDestination] テスト fake。
///
/// - `exists` / `open` の**呼び出しを List で記録**する（事前スキャン・
///   overwrite フラグ・dispose 回数の検証用）。
/// - `open` は実 [FileDestination] へ委譲し、端末ファイルへ実際に書込む
///   （既存テストの「実 IO で書込済みファイルを検証する」流儀を維持）。
/// - `openError` を設定すると `open()` が例外を投げる（書込開始失敗の再現）。
class FakeDownloadDestination implements DownloadDestination {
  FakeDownloadDestination(this.directoryPath);

  final String directoryPath;

  /// `exists(name)` の呼び出し記録（事前スキャン順）。
  final List<String> existsCalls = [];

  /// `open(name, overwrite:)` の呼び出し記録（`(name, overwrite)` タプル）。
  final List<(String, bool)> openCalls = [];

  /// open() が throw する例外（未設定なら実 FileDestination へ委譲）。
  Object? openError;

  /// dispose() が呼ばれたか（キュー終了時・reset() 時の 1 回だけ解放の検証用）。
  bool disposeCalled = false;

  @override
  Future<bool> exists(String name) async {
    existsCalls.add(name);
    return File('$directoryPath/$name').exists();
  }

  @override
  Future<DownloadSink> open(String name, {required bool overwrite}) async {
    openCalls.add((name, overwrite));
    if (openError != null) throw openError!;
    return FileDestination(directoryPath).open(name, overwrite: overwrite);
  }

  @override
  Future<void> dispose() async {
    disposeCalled = true;
  }
}

/// [SaveAsExporter] のテスト fake。
///
/// - [result]（null は Save-As キャンセル）をそのまま返し、[error] を設定すると
///   `export()` が throw する。
/// - 呼び出し元ファイルパスを [calls] に記録する（tmp パスで呼ばれる検証用）。
class FakeSaveAsExporter implements SaveAsExporter {
  FakeSaveAsExporter({this.result, this.error});

  final String? result;
  final Object? error;
  final List<String> calls = [];

  @override
  Future<String?> export(String sourceFilePath) async {
    calls.add(sourceFilePath);
    if (error != null) throw error!;
    return result;
  }
}

/// export の解決を保留できる [SaveAsExporter] のテスト fake（M3 観測用）。
///
/// [started] は [export] が呼ばれた時点で完了し、[release] が完了するまで [result] を
/// 返さない（exporting 中の phase・通知を観測できる）。
class _GatedSaveAsExporter implements SaveAsExporter {
  _GatedSaveAsExporter({
    required this.result,
    required this.started,
    required this.release,
  });

  final String? result;
  final Completer<void> started;
  final Completer<void> release;
  final List<String> calls = [];

  @override
  Future<String?> export(String sourceFilePath) async {
    calls.add(sourceFilePath);
    started.complete();
    await release.future;
    return result;
  }
}

FileEntry _entry(String fullPath, {int? size = 123}) => FileEntry(
  name: fullPath.split('/').last,
  fullPath: fullPath,
  isDirectory: false,
  size: size,
);

/// path_provider の platform channel（getTemporaryDirectory のモック用）。
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  /// startSingleTmpDownload が `getTemporaryDirectory()` から得る tmp 領域。
  late String appTmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('download_provider_test_');
    appTmp = '${tmp.path}/app_tmp';
    // 単一（tmp→Save-As）フローで必要な getTemporaryDirectory をモックする。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getTemporaryDirectory') return appTmp;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
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
    SaveAsExporter? exporter,
  }) {
    return ProviderContainer(
      overrides: [
        sshProvider.overrideWith(() => FakeSshNotifier(client: sshClient)),
        settingsProvider.overrideWith(FakeSettingsNotifier.new),
        if (clock != null || notificationService != null || exporter != null)
          downloadProvider.overrideWith(
            () => DownloadNotifier(
              clock: clock,
              notificationService: notificationService,
              exporter: exporter,
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
        final dest = FakeDownloadDestination(tmp.path);

        await notifier.startDownloads([
          _entry('/remote/data.bin', size: 300),
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
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/data.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      // 同名ファイルを事前作成（事前スキャンで検出される）。
      final dest = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);

      await container.read(downloadProvider.notifier).startDownloads([
        _entry('/remote/data.bin'),
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
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final dest = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);

      final notifier = container.read(downloadProvider.notifier);
      await notifier.startDownloads([_entry('/remote/data.bin')], dest);
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
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final dest = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);
      // data_1.bin も既に存在 → data_2.bin に採番される。
      File('${tmp.path}/data_1.bin').writeAsBytesSync([1]);

      final notifier = container.read(downloadProvider.notifier);
      await notifier.startDownloads([_entry('/remote/data.bin')], dest);
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
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/data.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final dest = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/data.bin').writeAsBytesSync([9, 9, 9, 9]);

      final notifier = container.read(downloadProvider.notifier);
      await notifier.startDownloads([_entry('/remote/data.bin')], dest);
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
        _entry('/remote/a.bin'),
        _entry('/remote/b.bin'),
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
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;
      notifier.cancel();
      gate.complete();
      await first;
      expect(container.read(downloadProvider).phase, DownloadPhase.cancelled);

      // 2 回目: ゲート解放（新トークンで再開始）→ 正常完了。
      holdGate = false;
      await notifier.startDownloads([
        _entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));

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
        _entry('/remote/a.bin'),
        _entry('/remote/b.bin'),
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
      final dest = FakeDownloadDestination(tmp.path);

      await notifier.startDownloads([
        _entry('/remote/a.bin'),
        _entry('/remote/b.bin'),
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
      final sftpUnknown = _TestSftpClient(
        contentsByPath: {
          '/remote/u.bin': Uint8List.fromList(List.generate(50, (i) => i)),
        },
        failStatFor: {'/remote/u.bin'},
      );
      sshClient.sftpClient = sftpUnknown;
      await notifier.startDownloads([
        _entry('/remote/u.bin'),
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

      final dest = FakeDownloadDestination(tmp.path);
      await notifier.startDownloads([_entry('/remote/a.bin')], dest);
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
        _entry('/remote/a.bin'),
      ], FakeDownloadDestination(againDir));
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
      final dest = FakeDownloadDestination(tmp.path);

      // 契約どおり例外を投げない（Future<void> が正常完了）。
      await notifier.startDownloads([_entry('/remote/a.bin')], dest);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.error); // 膠着（downloading のまま）しない。
      expect(state.errorMessage, isNotNull); // state へ反映。
      // finally に入る前に return する経路でも保存先は解放される（M2）。
      expect(dest.disposeCalled, isTrue);
      expect(sshClient.sftpClient.closeCalls, 0);
    });

    test('M1: 旧バッチの finally は新バッチの保存先を dispose しない', () async {
      // バッチA 転送中に cancel → 直ちにバッチB 開始（新保存先 destB）。この窓で
      // バッチA の in-flight download が TransferCancelledException になり finally が
      // 走っても、フィールドではなくスナップショットを対象にするため destB は
      // 破棄されない（M1: クロスバッチ誤破棄の構造的排除）。
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
      final batchA = notifier.startDownloads([_entry('/remote/a.bin')], destA);
      await reached100.future;

      // キャンセル → 直ちにバッチB 開始（新保存先 destB）。
      notifier.cancel();
      final destBDir = '${tmp.path}/b';
      Directory(destBDir).createSync();
      final destB = FakeDownloadDestination(destBDir);
      final batchB = notifier.startDownloads([_entry('/remote/a.bin')], destB);

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

      // バッチA: 転送中（chunk1 でゲート待ち）。
      final batchA = notifier.startDownloads([
        _entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));
      await reached100.future;
      notifier.cancel();

      // バッチB 開始（downloading 到達・sink オープン済み）。
      final destBDir = '${tmp.path}/b';
      Directory(destBDir).createSync();
      final destB = FakeDownloadDestination(destBDir);
      final batchB = notifier.startDownloads([_entry('/remote/a.bin')], destB);

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
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);
      final dest = FakeDownloadDestination(tmp.path);

      await notifier.startDownloads([_entry('/remote/a.bin')], dest);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.error);
      // ピッカーが iOS startScope 済みでも early return 経路でスコープ解放される（M2）。
      expect(dest.disposeCalled, isTrue);
      expect(sshClient.sftpClient.closeCalls, 0);
    });

    test('M2: awaitingOverwrite 中の SSH 切断 → error + 保存先 dispose', () async {
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);
      final dest = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/a.bin').writeAsBytesSync([9, 9, 9, 9]); // 衝突あり。

      await notifier.startDownloads([_entry('/remote/a.bin')], dest);
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
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/a.bin': Uint8List.fromList([1, 2, 3]),
        },
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);
      final destOld = FakeDownloadDestination(tmp.path);
      File('${tmp.path}/a.bin').writeAsBytesSync([9, 9, 9, 9]); // 衝突あり。

      await notifier.startDownloads([_entry('/remote/a.bin')], destOld);
      expect(
        container.read(downloadProvider).phase,
        DownloadPhase.awaitingOverwrite,
      );

      // awaitingOverwrite のまま新バッチ開始 → 旧保存先を dispose して置換（M2）。
      final destNewDir = '${tmp.path}/new';
      Directory(destNewDir).createSync();
      final destNew = FakeDownloadDestination(destNewDir);
      await notifier.startDownloads([_entry('/remote/a.bin')], destNew);

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      // 旧保存先（iOS スコープ等）は解放済み・新バッチは正常に終了（新側も dispose）。
      expect(destOld.disposeCalled, isTrue);
      expect(destNew.disposeCalled, isTrue);
      expect(File('$destNewDir/a.bin').readAsBytesSync(), [1, 2, 3]);
      expect(sftp.closeCalls, 0);
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
      final dest = FakeDownloadDestination(tmp.path);

      await notifier.startDownloads([
        _entry('/dir1/x.bin'),
        _entry('/dir2/x.bin'),
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

      await notifier.startDownloads([
        _entry('/remote/a.bin'),
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
      await notifier.startDownloads([
        _entry('/remote/a.bin'),
      ], FakeDownloadDestination(tmp.path));

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed);
      expect(File('${tmp.path}/a.bin').readAsBytesSync(), [1, 2, 3]);
      expect(notification.updateCalls, isEmpty); // throw 前なので記録なし。
      expect(notification.stopCalls, 0);
      expect(sftp.closeCalls, 0);
    });
  });

  group('downloadProvider.single（startSingleTmpDownload・tmp→Save-As）', () {
    test('tmpDL 成功 → export 成功: completed + localPath 更新 + tmp 削除', () async {
      final content = Uint8List.fromList([1, 2, 3]);
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final exporter = FakeSaveAsExporter(result: 'Download/data.bin');
      final container = makeContainer(sshClient: sshClient, exporter: exporter);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startSingleTmpDownload(_entry('/remote/data.bin'));

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
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final exporter = FakeSaveAsExporter(result: null); // Save-As キャンセル。
      final container = makeContainer(sshClient: sshClient, exporter: exporter);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startSingleTmpDownload(_entry('/remote/data.bin'));

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.cancelled);
      // localPath は tmp パスのまま（転送中断・確定済み）。
      expect(state.items[0].localPath, '$appTmp/sftp_download/data_1.bin');
      expect(File('$appTmp/sftp_download/data_1.bin').existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
    });

    test('export throw: error + tmp 削除', () async {
      final content = Uint8List.fromList([1, 2, 3]);
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final exporter = FakeSaveAsExporter(
        error: const FileSystemException('save failed'),
      );
      final container = makeContainer(sshClient: sshClient, exporter: exporter);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startSingleTmpDownload(_entry('/remote/data.bin'));

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.error);
      expect(state.errorMessage, isNotNull);
      expect(exporter.calls, ['$appTmp/sftp_download/data_1.bin']);
      // 失敗時も tmp 残骸は削除される（ベストエフォート）。
      expect(File('$appTmp/sftp_download/data_1.bin').existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
    });

    test('ダウンロード失敗: export されず tmp 削除', () async {
      final sftp = _TestSftpClient(
        contentsByPath: {
          '/remote/data.bin': Uint8List.fromList([1, 2, 3]),
        },
        failOpenFor: {'/remote/data.bin'}, // 転送自体が失敗。
      );
      final sshClient = FakeSshClient()..sftpClient = sftp;
      final exporter = FakeSaveAsExporter(result: 'Download/data.bin');
      final container = makeContainer(sshClient: sshClient, exporter: exporter);
      addTearDown(container.dispose);
      final notifier = container.read(downloadProvider.notifier);

      await notifier.startSingleTmpDownload(_entry('/remote/data.bin'));

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
      final exporter = FakeSaveAsExporter(result: 'Download/s.bin');
      final container = makeContainer(
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
        _entry('/remote/s.bin', size: 200),
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
        final sftp = _TestSftpClient(
          contentsByPath: {
            '/remote/data.bin': Uint8List.fromList([1, 2, 3]),
          },
        );
        final sshClient = FakeSshClient()..sftpClient = sftp;
        final notification = FakeSshForegroundTaskService();
        final exporter = _GatedSaveAsExporter(
          result: 'Download/data.bin',
          started: Completer<void>(),
          release: Completer<void>(),
        );
        final container = makeContainer(
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
          _entry('/remote/data.bin'),
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
