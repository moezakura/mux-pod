import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/utils/external_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tryParseExternalHttpUri（scheme ガード・純関数）', () {
    test('https / http を受理する', () {
      expect(tryParseExternalHttpUri('https://example.com/'), isNotNull);
      expect(tryParseExternalHttpUri('http://example.com/'), isNotNull);
    });

    test(
      'C1: scheme の大文字表記ゆれ（HTTPS: / Http:）は正規化により受理される',
      () {
        // Uri.tryParse は scheme を小文字正規化するため fail-closed ではなく
        // 「許可 scheme の大文字表記」として受理する（dart 実測値）。
        final httpsUpper = tryParseExternalHttpUri('HTTPS://EXAMPLE.com/PATH');
        expect(httpsUpper, isNotNull);
        expect(httpsUpper!.scheme, 'https');

        final httpMixed = tryParseExternalHttpUri('Http://example.com');
        expect(httpMixed, isNotNull);
        expect(httpMixed!.scheme, 'http');
      },
    );

    test('危険 scheme・非対応 scheme は null（タップ無視）', () {
      expect(tryParseExternalHttpUri('javascript:alert(1)'), isNull);
      expect(tryParseExternalHttpUri('mailto:a@b.c'), isNull);
      expect(tryParseExternalHttpUri('data:text/html,hi'), isNull);
      expect(tryParseExternalHttpUri('file:///etc/passwd'), isNull);
      // scheme 無し（#anchor・相対参照）
      expect(tryParseExternalHttpUri('#anchor'), isNull);
      expect(tryParseExternalHttpUri('example.com/path'), isNull);
    });

    test('空文字・空白のみは scheme 無しとして null（dart 実測: parse 自体は成功）', () {
      expect(tryParseExternalHttpUri(''), isNull);
      expect(tryParseExternalHttpUri('   '), isNull);
    });

    test('制御文字で開始する文字列はパース失敗で null（dart 実測）', () {
      // BEL / ESC で始まる生の OSC 8 シーケンス文字列は Uri.tryParse が
      // null を返す（例外は投げない）。
      expect(tryParseExternalHttpUri('\x07https://example.com'), isNull);
      expect(tryParseExternalHttpUri('\x1b]8;;https://example.com\x07'), isNull);
      expect(tryParseExternalHttpUri('\x00'), isNull);
    });

    test('URL 構造が有効ならパス途中の制御文字でも scheme 判定で受理される（dart 実測）', () {
      // scheme ガードは scheme 単位の判定のため、パス中の制御文字は
      // reject 条件にならない（fail-closed 拡張は一字不変契約に含めない）。
      expect(
        tryParseExternalHttpUri('https://example.com/\x00'),
        isNotNull,
      );
    });

    test('極長 URI も受理する（URL 長上限なし・critic 同意）', () {
      final longUrl = 'https://example.com/${'a' * 100000}';
      expect(tryParseExternalHttpUri(longUrl), isNotNull);
    });
  });

  group('launchExternalUri（url_launcher 委譲）', () {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');

    /// url_launcher プラットフォームチャンネルをモックし呼び出しを記録する
    /// （markdown_preview_link_guard_test.dart と同一手法）。
    List<MethodCall> mockUrlLauncher(WidgetTester tester, bool canLaunch) {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return canLaunch;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      return calls;
    }

    testWidgets('canLaunch 成功時は外部ブラウザ起動を 1 回依頼する', (tester) async {
      final calls = mockUrlLauncher(tester, true);

      await launchExternalUri(Uri.parse('https://example.com/page'));
      await tester.pump();

      expect(calls.where((c) => c.method == 'canLaunch'), hasLength(1));
      final launches = calls.where((c) => c.method == 'launch').toList();
      expect(launches, hasLength(1));
      expect(
        (launches.single.arguments as Map)['url'],
        'https://example.com/page',
      );
    });

    testWidgets('canLaunch false の場合は launch を呼ばず握りつぶす', (tester) async {
      final calls = mockUrlLauncher(tester, false);

      await launchExternalUri(Uri.parse('https://example.com/page'));
      await tester.pump();

      expect(calls.where((c) => c.method == 'canLaunch'), hasLength(1));
      expect(calls.where((c) => c.method == 'launch'), isEmpty);
    });
  });
}
