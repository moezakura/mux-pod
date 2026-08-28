import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/sftp/sftp_service.dart';
import 'package:flutter_muxpod/services/sftp/transfer_progress.dart';

import '../../helpers/fake_sftp_client.dart';

/// 非同期イベント（StreamController → SftpFileWriter）を確実に進める。
Future<void> pumpEvents([int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('SftpService', () {
    group('sanitizeFilename', () {
      test('英数字はそのまま通過する', () {
        expect(SftpService.sanitizeFilename('hello123'), 'hello123');
      });

      test('ドット・アンダースコア・ハイフンはそのまま通過する', () {
        expect(SftpService.sanitizeFilename('my-file_v2.0'), 'my-file_v2.0');
      });

      test('スペースはアンダースコアに置換される', () {
        expect(SftpService.sanitizeFilename('my file name'), 'my_file_name');
      });

      test('日本語文字はアンダースコアに置換される', () {
        expect(SftpService.sanitizeFilename('ファイル.png'), '____.png');
      });

      test('特殊文字はアンダースコアに置換される', () {
        expect(SftpService.sanitizeFilename('file@#\$%&.txt'), 'file_____.txt');
      });

      test('パストラバーサル文字はサニタイズされる', () {
        expect(
          SftpService.sanitizeFilename('../../../etc/passwd'),
          '.._.._.._etc_passwd',
        );
      });

      test('空文字列はunnamedを返す', () {
        expect(SftpService.sanitizeFilename(''), 'unnamed');
      });

      test('英数字のみの文字列は変更されない', () {
        expect(SftpService.sanitizeFilename('ABCdef123'), 'ABCdef123');
      });
    });

    group('generateFilename', () {
      test('プレフィックスと拡張子を含むファイル名が生成される', () {
        final result = SftpService.generateFilename('img_', 'png');
        expect(result, startsWith('img_'));
        expect(result, endsWith('.png'));
      });

      test('ドット付き拡張子も正しく処理される', () {
        final result = SftpService.generateFilename('photo', '.jpg');
        expect(result, endsWith('.jpg'));
        expect(result, startsWith('photo'));
      });

      test('生成されるファイル名は一意である', () {
        final results = <String>{};
        for (var i = 0; i < 10; i++) {
          results.add(SftpService.generateFilename('test', 'png'));
        }
        // UUID短縮4桁が含まれるため、高確率で一意
        expect(results.length, greaterThan(1));
      });

      test('タイムスタンプ部分がYYYYMMDD_HHMMSS形式である', () {
        final result = SftpService.generateFilename('img_', 'png');
        // img_YYYYMMDD_HHMMSS_xxxx.png の形式
        final regex = RegExp(r'^img_\d{8}_\d{6}_[a-f0-9]{4}\.png$');
        expect(regex.hasMatch(result), isTrue);
      });

      test('プレフィックスの特殊文字はサニタイズされる', () {
        final result = SftpService.generateFilename('my file', 'txt');
        expect(result, startsWith('my_file'));
        expect(result, endsWith('.txt'));
      });
    });

    group('generateUniqueName（#41）', () {
      test('元名ベース・拡張子保持のユニーク名が生成される', () {
        final result = SftpService.generateUniqueName('report.pdf');
        expect(
          result,
          matches(RegExp(r'^report_\d{8}_\d{6}_[a-f0-9]{4}\.pdf$')),
        );
      });

      test('日本語の元名が保持される', () {
        final result = SftpService.generateUniqueName('ファイル.txt');
        expect(result, startsWith('ファイル_'));
        expect(result, endsWith('.txt'));
      });

      test('拡張子なしのファイル名も処理される', () {
        final result = SftpService.generateUniqueName('README');
        expect(result, matches(RegExp(r'^README_\d{8}_\d{6}_[a-f0-9]{4}$')));
      });

      test('パス区切りを含む名前はベース名のみ使われる', () {
        final result = SftpService.generateUniqueName('/local/dir/画像.png');
        expect(result, startsWith('画像_'));
        expect(result, endsWith('.png'));
      });

      test('生成される名前は一意である', () {
        final results = <String>{
          for (var i = 0; i < 10; i++) SftpService.generateUniqueName('a.txt'),
        };
        expect(results.length, greaterThan(1));
      });
    });

    group('safeRemotePath（#41）', () {
      test('ディレクトリとファイル名を連結する', () {
        expect(
          SftpService.safeRemotePath('/tmp/muxpod', 'a.txt'),
          '/tmp/muxpod/a.txt',
        );
      });

      test('末尾スラッシュ付きディレクトリも正しく連結する', () {
        expect(
          SftpService.safeRemotePath('/tmp/muxpod/', 'a.txt'),
          '/tmp/muxpod/a.txt',
        );
      });

      test('パストラバーサル（../）は basename で除去される', () {
        expect(
          SftpService.safeRemotePath('/remote', '../../../etc/passwd'),
          '/remote/passwd',
        );
      });

      test('絶対パス形式のファイル名もベース名のみ使われる', () {
        expect(
          SftpService.safeRemotePath('/remote', '/etc/shadow'),
          '/remote/shadow',
        );
      });

      test('日本語ファイル名はそのまま保持される', () {
        expect(
          SftpService.safeRemotePath('/remote', 'ファイル.png'),
          '/remote/ファイル.png',
        );
      });

      test('ルートディレクトリへの連結も機能する', () {
        expect(SftpService.safeRemotePath('/', 'a.txt'), '/a.txt');
      });
    });

    group('remoteFileExists（#41）', () {
      test('存在するパスは true', () async {
        final fake = FakeSftpClient();
        expect(await SftpService.remoteFileExists(fake, '/'), isTrue);
      });

      test('存在しないパスは false（SftpStatusError を捕捉）', () async {
        final fake = FakeSftpClient();
        expect(
          await SftpService.remoteFileExists(fake, '/remote/none.txt'),
          isFalse,
        );
      });
    });

    group('uploadStream（#41）', () {
      late SftpService service;
      late FakeSftpClient fake;

      setUp(() {
        service = SftpService();
        fake = FakeSftpClient();
      });

      Uint8List bytes(int length, {int fill = 0x41}) =>
          Uint8List.fromList(List.filled(length, fill));

      test('全チャンクを書き込み結果を返す', () async {
        final result = await service.uploadStream(
          sftp: fake,
          remoteDir: '/remote',
          filename: 'a.bin',
          source: Stream.value(bytes(300)),
          totalBytes: 300,
          chunkSize: 100,
        );

        expect(result.remotePath, '/remote/a.bin');
        expect(result.bytesWritten, 300);
        expect(fake.openedFiles.single.content.length, 300);
        // 成功時は部分削除が行われない
        expect(fake.removeCalls, isEmpty);
      });

      test('進捗（間引きなし）は doneBytes が増加し最終値が総量に一致する', () async {
        final progressList = <TransferProgress>[];
        final result = await service.uploadStream(
          sftp: fake,
          remoteDir: '/remote',
          filename: 'a.bin',
          source: Stream.value(bytes(300)),
          totalBytes: 300,
          chunkSize: 100,
          progressInterval: Duration.zero,
          onProgress: progressList.add,
        );

        expect(result.bytesWritten, 300);
        // 16KB 分割された acked 进捗が複数回通知される
        expect(progressList.length, greaterThan(1));
        var previous = 0;
        for (final p in progressList) {
          expect(p.doneBytes, greaterThanOrEqualTo(previous));
          expect(p.totalBytes, 300);
          previous = p.doneBytes;
        }
        expect(progressList.last.doneBytes, 300);
      });

      test('既定の間引き（100ms）では高速転送時に通知が抑制される', () async {
        final progressList = <TransferProgress>[];
        await service.uploadStream(
          sftp: fake,
          remoteDir: '/remote',
          filename: 'a.bin',
          source: Stream.value(bytes(300)),
          totalBytes: 300,
          chunkSize: 100,
          onProgress: progressList.add,
        );

        // 初回＋最終（強制通知）のみ。中間 16KB 通知は間引きで抑制される。
        expect(progressList.length, lessThanOrEqualTo(3));
        expect(progressList.first.doneBytes, greaterThan(0));
        expect(progressList.last.doneBytes, 300);
        expect(progressList.last.bytesPerSec, greaterThanOrEqualTo(0));
      });

      test('サイズ未知（totalBytes=0）でも転送は完了する', () async {
        final result = await service.uploadStream(
          sftp: fake,
          remoteDir: '/remote',
          filename: 'a.bin',
          source: Stream.value(bytes(50)),
          totalBytes: 0,
          chunkSize: 100,
        );

        expect(result.bytesWritten, 50);
      });

      test('空ファイル（空ストリーム）を処理する', () async {
        final result = await service.uploadStream(
          sftp: fake,
          remoteDir: '/remote',
          filename: 'empty.bin',
          source: const Stream.empty(),
          totalBytes: 0,
          chunkSize: 100,
        );

        expect(result.bytesWritten, 0);
        expect(result.remotePath, '/remote/empty.bin');
        expect(fake.removeCalls, isEmpty);
      });

      test('転送途中のキャンセルは部分ファイルを削除し例外を投げる', () async {
        final controller = StreamController<Uint8List>();
        final token = TransferCancelToken();

        final future = service.uploadStream(
          sftp: fake,
          remoteDir: '/remote',
          filename: 'a.bin',
          source: controller.stream,
          totalBytes: 300,
          chunkSize: 100,
          cancelToken: token,
        );
        final expectation = expectLater(
          future,
          throwsA(isA<TransferCancelledException>()),
        );

        await pumpEvents();
        controller.add(bytes(60));
        await pumpEvents();
        token.cancel();
        controller.add(bytes(240));
        await pumpEvents();
        await controller.close();

        await expectation;
        expect(fake.removeCalls, contains('/remote/a.bin'));
      });

      test('ソースストリームのエラーは rethrow され部分ファイルを削除する', () async {
        final controller = StreamController<Uint8List>();
        final future = service.uploadStream(
          sftp: fake,
          remoteDir: '/remote',
          filename: 'a.bin',
          source: controller.stream,
          totalBytes: 300,
          chunkSize: 100,
        );
        final expectation = expectLater(future, throwsStateError);

        await pumpEvents();
        controller.add(bytes(50));
        controller.addError(StateError('local read failure'));
        await controller.close();
        await pumpEvents();

        await expectation;
        expect(fake.removeCalls, contains('/remote/a.bin'));
      });

      test('日本語ファイル名はサニタイズされず保持される', () async {
        final result = await service.uploadStream(
          sftp: fake,
          remoteDir: '/remote',
          filename: 'ファイル.png',
          source: Stream.value(bytes(10)),
          totalBytes: 10,
          chunkSize: 100,
        );

        expect(result.remotePath, '/remote/ファイル.png');
      });

      test('ファイル名のパストラバーサルは basename で防御される', () async {
        final result = await service.uploadStream(
          sftp: fake,
          remoteDir: '/remote',
          filename: '../../etc/passwd',
          source: Stream.value(bytes(10)),
          totalBytes: 10,
          chunkSize: 100,
        );

        expect(result.remotePath, '/remote/passwd');
      });

      test('SftpClient は close されない（close 禁止契約）', () async {
        await service.uploadStream(
          sftp: fake,
          remoteDir: '/remote',
          filename: 'a.bin',
          source: Stream.value(bytes(10)),
          totalBytes: 10,
          chunkSize: 100,
        );

        expect(fake.closeCalls, 0);
      });
    });

    group('upload（既存API・uploadStream 移譲）', () {
      late SftpService service;
      late FakeSftpClient fake;

      setUp(() {
        service = SftpService();
        fake = FakeSftpClient();
      });

      test('バイト全体をアップロードし進捗は 0.0〜1.0 で通知される', () async {
        final progressList = <double>[];
        final result = await service.upload(
          sftp: fake,
          remoteDir: '/tmp/muxpod',
          filename: 'img_20260403_143025_a3f2.png',
          bytes: Uint8List.fromList(List.filled(300, 1)),
          onProgress: progressList.add,
        );

        expect(result.remotePath, '/tmp/muxpod/img_20260403_143025_a3f2.png');
        expect(result.bytesWritten, 300);
        expect(fake.openedFiles.single.content.length, 300);
        expect(progressList, isNotEmpty);
        expect(progressList.last, 1.0);
        for (final p in progressList) {
          expect(p, inInclusiveRange(0.0, 1.0));
        }
      });
    });
  });
}
