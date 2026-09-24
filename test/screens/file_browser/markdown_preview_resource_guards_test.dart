import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/file_browser/widgets/sftp_markdown_image.dart';
import 'helpers/markdown_preview_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('MarkdownPreviewScreen - 画像ガード（構造検証・L-3）', () {
    const mdImages = '''
# Images

![relative](./img.png)
![traversal](../secret.png)
![root](/etc/passwd.png)
![https](https://example.com/logo.png)
![private](http://192.168.1.10/x.png)
![loopback](http://127.0.0.1:8080/x.png)
![data](data:image/png;base64,iVBORw0KGgo=)
![ftp](ftp://example.com/x.png)
''';

    testWidgets('相対は SFTP 解決・拒否群は placeholder・https のみネットワーク（許可時のみ取得）', (
      tester,
    ) async {
      final sftpClient = RecordingSftpClient(
        contentsByPath: {
          '/home/user/docs/readme.md': bytes(mdImages),
          '/home/user/docs/img.png': kTinyPng,
        },
      );
      await pumpScreen(tester, sftpClient: sftpClient);

      // --- SFTP 読込は md 本体 + 許可された相対パス 1 件のみ
      //（denied 群は一切 open されない）---
      expect(sftpClient.openedPaths, [
        '/home/user/docs/readme.md',
        '/home/user/docs/img.png',
      ], reason: 'トラバーサル・ルート・絶対 URL は SFTP を一切呼ばない');
      // 相対成功 → Image.memory（ImageProvider 構造で検証）
      final memoryImages = tester
          .widgetList<Image>(
            find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage),
          )
          .toList();
      expect(memoryImages, hasLength(1));

      // --- https のみネットワーク許可（localhost / private IP は拒否）---
      // 構造検証: imageBuilder が Image.network（NetworkImage）を返したこと自体が
      // 「許可時のみ GET」を表す（テスト環境では HTTP 失敗で errorBuilder が
      // build されるが、Image ウィジェットは木に残るため NetworkImage で判定可）。
      final networkImages = tester
          .widgetList<Image>(
            find.byWidgetPredicate(
              (w) => w is Image && w.image is NetworkImage,
            ),
          )
          .toList();
      expect(networkImages, hasLength(1), reason: 'https://example.com のみ許可');
      expect(
        (networkImages.single.image as NetworkImage).url,
        'https://example.com/logo.png',
      );

      // --- 拒否群（traversal / root / private / loopback / data / ftp）---
      expect(find.byIcon(Icons.broken_image), findsNWidgets(6));
    });
  });

  group('SftpMarkdownImage.resolveImage（純関数・構造検証）', () {
    test('相対パスは .md ディレクトリ基準で SFTP 解決する', () {
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('./img.png'),
        mdBaseDirectory: '/home/user/docs',
      );
      expect(r.kind, MarkdownImageResolvedKind.sftp);
      expect(r.sftpPath, '/home/user/docs/img.png');
    });

    test('サブディレクトリ相対はベース配下なら許可する', () {
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('assets/img.png'),
        mdBaseDirectory: '/home/user/docs',
      );
      expect(r.kind, MarkdownImageResolvedKind.sftp);
      expect(r.sftpPath, '/home/user/docs/assets/img.png');
    });

    test('`../` でベース外へ脱出する相対パスは拒否する（パストラバーサル）', () {
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('../secret.png'),
        mdBaseDirectory: '/home/user/docs',
      );
      expect(r.kind, MarkdownImageResolvedKind.denied);
    });

    test('ルート相対（先頭 /）はベース配下でないため拒否する（D-3）', () {
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('/etc/passwd.png'),
        mdBaseDirectory: '/home/user/docs',
      );
      expect(r.kind, MarkdownImageResolvedKind.denied);
    });

    test('ベースがサーバールート（/）のとき相対画像はルート配下として許可する（MEDIUM-2）', () {
      // .md がルート直下（/README.md）: ベースディレクトリ = '/'
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('img.png'),
        mdBaseDirectory: '/',
      );
      expect(r.kind, MarkdownImageResolvedKind.sftp);
      expect(r.sftpPath, '/img.png');
      // サブディレクトリ参照もルート配下として許可される
      final sub = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('assets/logo.png'),
        mdBaseDirectory: '/',
      );
      expect(sub.kind, MarkdownImageResolvedKind.sftp);
      expect(sub.sftpPath, '/assets/logo.png');
    });

    test('ベースディレクトリが不明な相対パスは拒否する', () {
      final r = SftpMarkdownImage.resolveImage(
        uri: Uri.parse('img.png'),
        mdBaseDirectory: null,
      );
      expect(r.kind, MarkdownImageResolvedKind.denied);
    });

    test('https/http は許可（ホスト名・パブリック IP）', () {
      for (final src in [
        'https://example.com/logo.png',
        'http://example.com/x.png',
        'https://8.8.8.8/x.png',
      ]) {
        final r = SftpMarkdownImage.resolveImage(
          uri: Uri.parse(src),
          mdBaseDirectory: '/home/user/docs',
        );
        expect(r.kind, MarkdownImageResolvedKind.network, reason: src);
      }
    });

    test('https/http でも localhost / private IP は拒否する', () {
      for (final src in [
        'http://localhost/x.png',
        'http://127.0.0.1/x.png',
        'http://10.1.2.3/x.png',
        'http://172.16.0.1/x.png',
        'http://172.31.255.254/x.png',
        'http://192.168.0.1/x.png',
        // IPv4-mapped IPv6 は IPv6 型として素通りするため明示拒否（MEDIUM-1）
        'http://[::ffff:10.0.0.1]/x.png',
        'http://[::ffff:127.0.0.1]:8080/x.png',
        'http://[::ffff:192.168.1.1]/x.png',
      ]) {
        final r = SftpMarkdownImage.resolveImage(
          uri: Uri.parse(src),
          mdBaseDirectory: '/home/user/docs',
        );
        expect(r.kind, MarkdownImageResolvedKind.denied, reason: src);
      }
    });

    test('data URI・その他スキームは拒否する（本フェーズ外）', () {
      for (final src in [
        'data:image/png;base64,iVBORw0KGgo=',
        'ftp://example.com/x.png',
        'file:///etc/passwd',
        'mailto:a@b.c',
        'javascript:alert(1)',
      ]) {
        final r = SftpMarkdownImage.resolveImage(
          uri: Uri.parse(src),
          mdBaseDirectory: '/home/user/docs',
        );
        expect(r.kind, MarkdownImageResolvedKind.denied, reason: src);
      }
    });
  });

  group('SftpMarkdownImage.isBlockedHost（純関数）', () {
    test('localhost・ループバック・プライベート IP・unspecified をブロックする', () {
      for (final host in [
        'localhost',
        'LOCALHOST',
        '127.0.0.1',
        '127.8.9.10',
        '::1',
        '0.0.0.0',
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.1',
        '::',
        'fc00::1',
        // IPv4-mapped IPv6（IPv6 型で isLoopback/isLinkLocal が効かないため
        // 明示再判定が必要・MEDIUM-1）
        '::ffff:127.0.0.1',
        '::ffff:10.0.0.1',
        '::ffff:172.16.0.1',
        '::ffff:192.168.1.1',
        '::ffff:169.254.1.1',
        '::ffff:0.0.0.0',
      ]) {
        expect(SftpMarkdownImage.isBlockedHost(host), isTrue, reason: host);
      }
    });

    test('パブリック IP・ホスト名は許可する', () {
      for (final host in [
        '8.8.8.8',
        '1.1.1.1',
        'example.com',
        's3.amazonaws.com',
        '172.15.0.1', // 172.16/12 の範囲外
        '172.32.0.1',
        '::ffff:8.8.8.8', // IPv4-mapped でもパブリック IPv4 は許可
        '2001:db8::1',
      ]) {
        expect(SftpMarkdownImage.isBlockedHost(host), isFalse, reason: host);
      }
    });
  });
}
