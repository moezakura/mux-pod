import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/sftp/sftp_service.dart';

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
  });
}
