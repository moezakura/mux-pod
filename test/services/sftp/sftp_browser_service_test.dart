import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/sftp/preview_too_large_exception.dart';
import 'package:flutter_muxpod/services/sftp/sftp_browser_service.dart';

import '../../helpers/fake_sftp_client.dart';

/// readBytes 呼び出し回数・stat サイズ・readBytes 例外を注入できる
/// [FakeSftpFile] のテスト用サブクラス（基盤 helper は不変のまま拡張）。
class _CountingFakeSftpFile extends FakeSftpFile {
  final Object? _readError;

  int readBytesCalls = 0;

  _CountingFakeSftpFile(
    super.client,
    super.content, {
    int? statSize,
    Object? readError,
  }) : _readError = readError,
       super(size: statSize);

  @override
  Future<Uint8List> readBytes({int? length, int offset = 0}) async {
    readBytesCalls++;
    final error = _readError;
    if (error != null) throw error;
    return super.readBytes(length: length, offset: offset);
  }
}

/// open で [_CountingFakeSftpFile] を生成・記録するテスト用クライアント。
///
/// image_transfer_provider_test の _RecordingSftpClient と同系のパターンで、
/// 基盤 [FakeSftpClient] は変更しない。
class _CountingSftpClient extends FakeSftpClient {
  _CountingSftpClient({
    super.contentsByPath,
    this.sizesByPath = const {},
    this.readErrorsByPath = const {},
  });

  /// パスごとの stat サイズ（未指定は内容長）。
  final Map<String, int> sizesByPath;

  /// パスごとの readBytes 例外（IO 失敗伝播の検証用）。
  final Map<String, Object> readErrorsByPath;

  /// open() に渡された（validatePath 済みの）パス記録。
  final List<String> openPaths = [];

  _CountingFakeSftpFile? lastOpened;

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    openPaths.add(path);
    final file = _CountingFakeSftpFile(
      this,
      contentsByPath[path] ?? Uint8List(0),
      statSize: sizesByPath[path],
      readError: readErrorsByPath[path],
    );
    lastOpened = file;
    return file;
  }
}

void main() {
  group('SftpBrowserService.readFileAsBytes', () {
    test('stat 超過時は読取前に PreviewTooLargeException・readBytes は呼ばれない', () async {
      // content は 3 バイトだが stat サイズだけ 100 → maxBytes=10 を超過
      final sftp = _CountingSftpClient(
        contentsByPath: {'/docs/README.md': Uint8List.fromList([65, 66, 67])},
        sizesByPath: {'/docs/README.md': 100},
      );

      await expectLater(
        SftpBrowserService.readFileAsBytes(
          sftp,
          '/docs/README.md',
          maxBytes: 10,
        ),
        throwsA(isA<PreviewTooLargeException>()),
      );
      // 読取前 throw の証明
      expect(sftp.lastOpened!.readBytesCalls, 0);
    });

    test('成功: bytes が返り file.close は呼ばれ sftp.close は呼ばれない', () async {
      final content = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sftp = _CountingSftpClient(
        contentsByPath: {'/docs/README.md': content},
      );

      final result = await SftpBrowserService.readFileAsBytes(
        sftp,
        '/docs/README.md',
        maxBytes: 20,
      );

      expect(result.bytes, [1, 2, 3, 4, 5]);
      expect(result.isTruncated, isFalse);
      // ファイルハンドルは finally で必ず close
      expect(sftp.lastOpened!.closeCalls, 1);
      // SftpClient は close しない（キャッシュ契約・939a298）
      expect(sftp.closeCalls, 0);
    });

    test('maxBytes+1 で切詰めを検知し isTruncated=true（size が実サイズより小さい伸長ケース）', () async {
      // stat.size=4（maxBytes=4 以下）だが実内容は 10 バイト
      final sftp = _CountingSftpClient(
        contentsByPath: {
          '/docs/README.md':
              Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        },
        sizesByPath: {'/docs/README.md': 4},
      );

      final result = await SftpBrowserService.readFileAsBytes(
        sftp,
        '/docs/README.md',
        maxBytes: 4,
      );

      // readBytes(length: maxBytes+1 = 5) により 5 バイト読まれる
      expect(result.bytes.length, 5);
      expect(result.isTruncated, isTrue);
    });

    test('size 指定で stat 超過 → PreviewTooLargeException・readBytes 非呼出', () async {
      final sftp = _CountingSftpClient(
        contentsByPath: {'/docs/large.md': Uint8List.fromList([65])},
        sizesByPath: {'/docs/large.md': 100},
      );

      await expectLater(
        SftpBrowserService.readFileAsBytes(
          sftp,
          '/docs/large.md',
          maxBytes: 10,
        ),
        throwsA(isA<PreviewTooLargeException>()),
      );
      expect(sftp.lastOpened!.readBytesCalls, 0);
    });

    test('非 UTF-8 バイトはデコードされずそのまま返る', () async {
      final content = Uint8List.fromList([0xE9, 0xE8, 0x8B, 0xE7]); // 非 UTF-8 列
      final sftp = _CountingSftpClient(
        contentsByPath: {'/docs/bin.md': content},
      );

      final result = await SftpBrowserService.readFileAsBytes(
        sftp,
        '/docs/bin.md',
        maxBytes: 10,
      );

      expect(result.bytes, content);
      expect(result.isTruncated, isFalse);
    });

    test('空ファイル: 空 bytes・isTruncated=false・file.close される', () async {
      final sftp = _CountingSftpClient(
        contentsByPath: {'/docs/empty.md': Uint8List(0)},
      );

      final result = await SftpBrowserService.readFileAsBytes(
        sftp,
        '/docs/empty.md',
        maxBytes: 10,
      );

      expect(result.bytes, isEmpty);
      expect(result.isTruncated, isFalse);
      expect(sftp.lastOpened!.closeCalls, 1);
    });

    test('validatePath: 絶対パスが正規化されて open に渡る', () async {
      final sftp = _CountingSftpClient(contentsByPath: const {});

      await SftpBrowserService.readFileAsBytes(
        sftp,
        '/home/user/docs/../README.md',
        maxBytes: 10,
      );

      expect(sftp.openPaths, ['/home/user/README.md']);
    });

    test('validatePath: 相対パスは拒否されず絶対化される（実コードの挙動を固定）', () async {
      // 実コード確認（検証コマンド `dart run` で確認済み）: validatePath は
      // 相対パスを例外で拒否せず、`p.posix.normalize` の結果が '/' で始まら
      // ない場合にのみ '/' を付与して絶対化する。コメント「絶対パスのみ許可」
      // は仕様記述であり、実装上は絶対化で吸収されることをテストで固定する
      // （計画 §L3 のパストラバーサル拒否は呼び出し側・画像ビルダの責務）。
      final sftp = _CountingSftpClient(contentsByPath: const {});

      await SftpBrowserService.readFileAsBytes(
        sftp,
        'docs/../README.md',
        maxBytes: 10,
      );

      expect(sftp.openPaths, ['/README.md']);
    });

    test('readBytes 失敗時は例外が伝播し file.close が保証される（IO 失敗）', () async {
      // リーダー指示: 計画の「タイムアウト」項目を「IO 失敗の伝播」に置換
      final sftp = _CountingSftpClient(
        contentsByPath: {'/docs/README.md': Uint8List.fromList([1, 2, 3])},
        readErrorsByPath: {
          '/docs/README.md': SftpStatusError(SftpStatusCode.failure, 'boom'),
        },
      );

      await expectLater(
        SftpBrowserService.readFileAsBytes(
          sftp,
          '/docs/README.md',
          maxBytes: 10,
        ),
        throwsA(isA<SftpStatusError>()),
      );
      // finally によるハンドル close が保証される
      expect(sftp.lastOpened!.closeCalls, 1);
    });
  });

  group('SftpBrowserService.isLikelyBinary', () {
    test('NUL バイトを含む先頭ブロックはバイナリ判定', () {
      // "he\x00llo"（8KB 以内に NUL）
      expect(
        SftpBrowserService.isLikelyBinary(
          Uint8List.fromList([104, 101, 0, 108, 108, 111]),
        ),
        isTrue,
      );
    });

    test('日本語 UTF-8 テキストは誤検知されない', () {
      final text = 'README: MuxPod の日本語ドキュメントです。\n'
          'これは Markdown の本文であり、バイナリではありません。\n' * 5;
      expect(
        SftpBrowserService.isLikelyBinary(
          Uint8List.fromList(utf8.encode(text)),
        ),
        isFalse,
      );
    });

    test('NUL なしの非 UTF-8 バイト列は置換文字比率でバイナリ判定', () {
      // UTF-16LE BOM 相当（NUL のない無効 UTF-8 列）。
      // allowMalformed デコードで U+FFFD が多発し、比率がしきい値を超える。
      expect(
        SftpBrowserService.isLikelyBinary(
          Uint8List.fromList([0xFF, 0xFE, 0xFF, 0xFE, 0xFD, 0xFC]),
        ),
        isTrue,
      );
    });

    test('空バイト列はバイナリではない', () {
      expect(SftpBrowserService.isLikelyBinary(Uint8List(0)), isFalse);
    });
  });
}