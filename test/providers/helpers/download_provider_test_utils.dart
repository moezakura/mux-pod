// download provider テストの共有 fake とスコープ。
//
// P5 で download_provider_test.dart から抽出した共通要素を集約する。
// `_` 接頭辞の private 名は公開名へ rename（BRIEF 5 項・private 共有禁止）。
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
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../../helpers/fake_settings_notifier.dart';
import '../../helpers/fake_sftp_client.dart';
import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';

// テスト本文が直接参照する fake 型を再 export（二重定義なし・共通 1 本化）。
export '../../helpers/fake_ssh_client.dart' show FakeSshClient;
export '../../helpers/fake_ssh_foreground_task_service.dart'
    show FakeSshForegroundTaskService;
export '../../helpers/fake_save_as_exporter.dart' show FakeSaveAsExporter;

/// `openSftp()` が throw するクライアント（MEDIUM#2 の回帰テスト用）。
class OpenSftpFailingSshClient extends FakeSshClient {
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
class TestSftpClient extends FakeSftpClient {
  TestSftpClient({
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

/// export の解決を保留できる [SaveAsExporter] のテスト fake（M3 観測用）。
///
/// [started] は [export] が呼ばれた時点で完了し、[release] が完了するまで [result] を
/// 返さない（exporting 中の phase・通知を観測できる）。
class GatedSaveAsExporter implements SaveAsExporter {
  GatedSaveAsExporter({
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

FileEntry entry(String fullPath, {int? size = 123}) => FileEntry(
  name: fullPath.split('/').last,
  fullPath: fullPath,
  isDirectory: false,
  size: size,
);

/// path_provider のプラットフォーム channel と tmp/appTmp を管理するスコープ。
///
/// 各テストファイルの `main()` で生成し、`setUp`/`tearDown` に登録する。
/// テスト本文は `late Directory tmp; late String appTmp;`（main 直下）に
/// 再代入された値をそのまま参照する（変数参照方式・critique §2-3）。
class DownloadProviderTmpScope {
  static const _pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory tmp;

  /// startSingleTmpDownload が `getTemporaryDirectory()` から得る tmp 領域。
  late String appTmp;

  void setUp() {
    tmp = Directory.systemTemp.createTempSync('download_provider_test_');
    appTmp = '${tmp.path}/app_tmp';
    // 単一（tmp→Save-As）フローで必要な getTemporaryDirectory をモックする。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getTemporaryDirectory') return appTmp;
          return null;
        });
  }

  void tearDown() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // 削除失敗は検証対象外。
    }
  }
}

/// downloadProvider をオーバーライドした新しい [ProviderContainer]。
ProviderContainer makeDownloadProviderContainer({
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
