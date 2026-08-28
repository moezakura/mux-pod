import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/sftp/sftp_download_service.dart';
import 'package:flutter_muxpod/services/sftp/transfer_progress.dart';

import '../../helpers/fake_sftp_client.dart';

/// [FakeSftpClient] を継承した download 系テスト用クライアント。
///
/// - `stat`: 対象パスが [failStatFor] なら例外（stat 失敗再現）。contentsByPath に
///   あれば実サイズを返す（totalBytes 検証用）。
/// - `open`: [emitChunkSize] / [beforeEmit] 付きの [FakeSftpFile] を返し、最後の
///   インスタンスを [lastOpened] に記録（ファイル closeCalls 検証用）。
class _TestSftpClient extends FakeSftpClient {
  _TestSftpClient({
    required super.contentsByPath,
    this.emitChunkSize,
    this.beforeEmit,
    this.failStatFor = const {},
  });

  /// チャンク分割 emit サイズ（FakeSftpFile へ引き渡し）。
  final int? emitChunkSize;

  /// 各チャンク emit 前フック（FakeSftpFile へ引き渡し・キャンセル境界テスト用）。
  final Future<void> Function(int chunkIndex)? beforeEmit;

  /// stat 失敗（サイズ未知）を再現するリモートパス集合。
  final Set<String> failStatFor;

  /// open で返した最後の [FakeSftpFile]。
  FakeSftpFile? lastOpened;

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
    final file = FakeSftpFile(
      this,
      contentsByPath[path] ?? Uint8List(0),
      emitChunkSize: emitChunkSize,
      beforeEmit: beforeEmit,
    );
    lastOpened = file;
    return file;
  }
}

/// `open()` を throw してダウンロード開始を失敗させるテスト用クライアント。
class _OpenFailingSftp extends FakeSftpClient {
  _OpenFailingSftp({required super.contentsByPath});

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    throw SftpStatusError(SftpStatusCode.failure, 'boom');
  }
}

/// `close()` が throw する [FakeSftpFile]（finally close 失敗の回帰テスト用）。
class _CloseFailingFile extends FakeSftpFile {
  _CloseFailingFile(
    super.client,
    super.content, {
    super.emitChunkSize,
    super.beforeEmit,
  });

  @override
  Future<void> close() async {
    closeCalls++;
    throw SftpError('close failed');
  }
}

/// `open()` で [_CloseFailingFile] を返すクライアント。
class _CloseFailingSftp extends FakeSftpClient {
  _CloseFailingSftp({
    required super.contentsByPath,
    this.emitChunkSize,
    this.beforeEmit,
  });

  final int? emitChunkSize;
  final Future<void> Function(int chunkIndex)? beforeEmit;

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    return _CloseFailingFile(
      this,
      contentsByPath[path] ?? Uint8List(0),
      emitChunkSize: emitChunkSize,
      beforeEmit: beforeEmit,
    );
  }
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sftp_dl_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // 削除失敗はテスト環境の問題として無視（検証対象外）。
    }
  });

  Uint8List content300() =>
      Uint8List.fromList(List.generate(300, (i) => i % 256));

  group('SftpDownloadService.download', () {
    test('全チャンクを書込・進捗は累積バイトで通知・sftp.close は呼ばれない', () async {
      final content = content300();
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/data.bin': content},
        emitChunkSize: 100,
      );
      final localPath = '${tmp.path}/data.bin';
      final progress = <(int, int)>[];

      final result = await SftpDownloadService().download(
        sftp: sftp,
        remotePath: '/remote/data.bin',
        localPath: localPath,
        cancellation: TransferCancelToken(),
        onProgress: (done, total) => progress.add((done, total)),
      );

      expect(result.remotePath, '/remote/data.bin');
      expect(result.localPath, localPath);
      expect(result.bytesDownloaded, 300);
      // 端末ファイルへ 300B が逐次書込されている。
      expect(File(localPath).readAsBytesSync(), content);
      // 100B チャンク × 3 で累積バイト通知（totalBytes は stat 由来の 300）。
      expect(progress, [(100, 300), (200, 300), (300, 300)]);
      // sftp.close() 禁止契約: クライアント close は 0 回。
      expect(sftp.closeCalls, 0);
      // ファイルハンドル close は finally で 1 回。
      expect(sftp.lastOpened, isNotNull);
      expect(sftp.lastOpened!.closeCalls, 1);
    });

    test('キャンセル: 部分削除 + TransferCancelledException + sftp.close 不呼', () async {
      final gate = Completer<void>();
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/data.bin': content300()},
        emitChunkSize: 100,
        beforeEmit: (i) async {
          // 2 チャンク目 emit 前で待機（テストがキャンセルするまで）。
          if (i == 1) await gate.future;
        },
      );
      final localPath = '${tmp.path}/data.bin';
      final token = TransferCancelToken();

      final downloadFuture = SftpDownloadService().download(
        sftp: sftp,
        remotePath: '/remote/data.bin',
        localPath: localPath,
        cancellation: token,
        onProgress: (done, total) {
          // 1 チャンク目（100B）書込完了時にキャンセル + ゲート解放。
          if (done == 100) {
            token.cancel();
            gate.complete();
          }
        },
      );

      await expectLater(
        downloadFuture,
        throwsA(isA<TransferCancelledException>()),
      );
      // 部分ファイルは「sink.close（flush）→ File.delete」で削除済み。
      expect(File(localPath).existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
      expect(sftp.lastOpened, isNotNull);
      expect(sftp.lastOpened!.closeCalls, 1);
    });

    test('キャンセル済みトークンでの開始: 例外・ローカルファイル未作成・open 未実行', () async {
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/data.bin': content300()},
      );
      final localPath = '${tmp.path}/never.bin';
      final token = TransferCancelToken()..cancel();

      await expectLater(
        SftpDownloadService().download(
          sftp: sftp,
          remotePath: '/remote/data.bin',
          localPath: localPath,
          cancellation: token,
        ),
        throwsA(isA<TransferCancelledException>()),
      );

      // 書込前のトークン検査で空ファイルの残骸を残さない。
      expect(File(localPath).existsSync(), isFalse);
      expect(sftp.lastOpened, isNull); // open は実行されない。
      expect(sftp.closeCalls, 0);
    });

    test('open 失敗: 例外 rethrow・ローカル残骸なし・closeCalls==0', () async {
      final sftp = _OpenFailingSftp(
        contentsByPath: {'/remote/data.bin': content300()},
      );
      final localPath = '${tmp.path}/data.bin';

      await expectLater(
        SftpDownloadService().download(
          sftp: sftp,
          remotePath: '/remote/data.bin',
          localPath: localPath,
          cancellation: TransferCancelToken(),
        ),
        throwsA(isA<SftpStatusError>()),
      );

      // open 前に出来た（可能性のある）空ファイルは部分削除される。
      expect(File(localPath).existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
    });

    test(
      'ストリーム throw: rethrow + 部分削除 + closeCalls==0 + ファイル closeCalls==1',
      () async {
        final sftp = _TestSftpClient(
          contentsByPath: {'/remote/data.bin': content300()},
          emitChunkSize: 100,
          beforeEmit: (i) async {
            // 2 チャンク目 emit 前にストリームを失敗させる。
            if (i == 1) throw SftpError('remote read failed');
          },
        );
        final localPath = '${tmp.path}/data.bin';

        await expectLater(
          SftpDownloadService().download(
            sftp: sftp,
            remotePath: '/remote/data.bin',
            localPath: localPath,
            cancellation: TransferCancelToken(),
          ),
          throwsA(isA<SftpError>()),
        );

        // 1 チャンク目（100B）まで書込済みの部分ファイルは削除される。
        expect(File(localPath).existsSync(), isFalse);
        expect(sftp.closeCalls, 0);
        expect(sftp.lastOpened, isNotNull);
        expect(sftp.lastOpened!.closeCalls, 1);
      },
    );

    test('書込 I/O エラー（ディスクフル相当）: rethrow + 残骸なし', () async {
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/data.bin': content300()},
      );
      // 存在しない親ディレクトリ配下を書込先に指定 → FileSystemException（ディスクフル相当）。
      final localPath = '${tmp.path}/missing_dir/data.bin';

      await expectLater(
        SftpDownloadService().download(
          sftp: sftp,
          remotePath: '/remote/data.bin',
          localPath: localPath,
          cancellation: TransferCancelToken(),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(File(localPath).existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
      expect(sftp.lastOpened, isNotNull);
      expect(sftp.lastOpened!.closeCalls, 1);
    });

    test('stat 失敗: totalBytes=0（未知）でも全チャンク転送', () async {
      final content = content300();
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/unknown.bin': content},
        emitChunkSize: 100,
        failStatFor: {'/remote/unknown.bin'},
      );
      final progress = <(int, int)>[];

      final result = await SftpDownloadService().download(
        sftp: sftp,
        remotePath: '/remote/unknown.bin',
        localPath: '${tmp.path}/unknown.bin',
        cancellation: TransferCancelToken(),
        onProgress: (done, total) => progress.add((done, total)),
      );

      expect(result.bytesDownloaded, 300);
      expect(File('${tmp.path}/unknown.bin').readAsBytesSync(), content);
      // stat 失敗はベストエフォートで握りつぶし totalBytes=0（サイズ未知）。
      expect(progress, [(100, 0), (200, 0), (300, 0)]);
      expect(sftp.closeCalls, 0);
      expect(sftp.lastOpened!.closeCalls, 1);
    });

    test('0 バイトファイル: 成功（bytesDownloaded==0・空ファイル作成）', () async {
      final sftp = _TestSftpClient(
        contentsByPath: {'/remote/empty.bin': Uint8List(0)},
      );
      final localPath = '${tmp.path}/empty.bin';

      final result = await SftpDownloadService().download(
        sftp: sftp,
        remotePath: '/remote/empty.bin',
        localPath: localPath,
        cancellation: TransferCancelToken(),
      );

      expect(result.bytesDownloaded, 0);
      expect(File(localPath).readAsBytesSync(), isEmpty);
      expect(sftp.closeCalls, 0);
      expect(sftp.lastOpened!.closeCalls, 1);
    });

    test('finally の close 失敗でも rethrow 元の例外（キャンセル）が維持される（LOW#1）', () async {
      final gate = Completer<void>();
      final sftp = _CloseFailingSftp(
        contentsByPath: {'/remote/data.bin': content300()},
        emitChunkSize: 100,
        beforeEmit: (i) async {
          if (i == 1) await gate.future;
        },
      );
      final localPath = '${tmp.path}/data.bin';
      final token = TransferCancelToken();

      final downloadFuture = SftpDownloadService().download(
        sftp: sftp,
        remotePath: '/remote/data.bin',
        localPath: localPath,
        cancellation: token,
        onProgress: (done, total) {
          if (done == 100) {
            token.cancel();
            gate.complete();
          }
        },
      );

      // finally の close() が throw しても、rethrow 元は TransferCancelledException のまま。
      await expectLater(
        downloadFuture,
        throwsA(isA<TransferCancelledException>()),
      );
      expect(File(localPath).existsSync(), isFalse);
      expect(sftp.closeCalls, 0);
    });

    test(
      'finally の close 失敗でも rethrow 元の例外（書込 I/O エラー）が維持される（LOW#1）',
      () async {
        final sftp = _CloseFailingSftp(
          contentsByPath: {'/remote/data.bin': content300()},
        );
        // 存在しない親ディレクトリ配下 → 書込 I/O エラー（FileSystemException）。
        final localPath = '${tmp.path}/missing_dir/data.bin';

        // finally の close() が throw しても、rethrow 元は FileSystemException のまま。
        await expectLater(
          SftpDownloadService().download(
            sftp: sftp,
            remotePath: '/remote/data.bin',
            localPath: localPath,
            cancellation: TransferCancelToken(),
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(sftp.closeCalls, 0);
      },
    );
  });

  group('SftpDownloadService.sanitizeLocalName', () {
    test('basename を抽出する（パストラバーサルを含む）', () {
      expect(
        SftpDownloadService.sanitizeLocalName('/home/user/music/song.mp3'),
        'song.mp3',
      );
      expect(SftpDownloadService.sanitizeLocalName('file.txt'), 'file.txt');
      expect(SftpDownloadService.sanitizeLocalName('/a/b/c'), 'c');
      expect(SftpDownloadService.sanitizeLocalName('/a/../b'), 'b');
      expect(
        SftpDownloadService.sanitizeLocalName(r'..\..\evil.sh'),
        'evil.sh',
      );
    });

    test('非 ASCII 名は保持される（サーバー向け sanitizeFilename は流用しない）', () {
      expect(SftpDownloadService.sanitizeLocalName('/remote/音楽.mp3'), '音楽.mp3');
    });

    test('危険文字（\\・制御文字）を除去する', () {
      expect(SftpDownloadService.sanitizeLocalName(r'a\b.txt'), 'b.txt');
      expect(
        SftpDownloadService.sanitizeLocalName('name\u0000ctrl.txt'),
        'namectrl.txt',
      );
      expect(SftpDownloadService.sanitizeLocalName('tab\u0009.txt'), 'tab.txt');
    });

    test('空・.・.. は download_<timestamp> に補完される（throw しない）', () {
      for (final input in ['', '/', '.', '..']) {
        final name = SftpDownloadService.sanitizeLocalName(input);
        expect(name, matches(RegExp(r'^download_\d{8}_\d{6}$')));
      }
    });
  });
}
