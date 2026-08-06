import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/deep_link/deep_link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.muxpod.app/deeplink');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('DeepLinkData', () {
    test('toString', () {
      const data = DeepLinkData(
        server: 'my-server',
        session: 'main',
        window: 'shell',
        pane: 0,
      );
      expect(
        data.toString(),
        'DeepLinkData(server: my-server, session: main, window: shell, pane: 0)',
      );
    });

    test('hasTarget is true when server is set', () {
      const data = DeepLinkData(server: 'my-server');
      expect(data.hasTarget, isTrue);
    });

    test('hasTarget is false when server is null', () {
      const data = DeepLinkData(session: 'main');
      expect(data.hasTarget, isFalse);
    });
  });

  group('parseUri', () {
    test('parses valid muxpod URI', () {
      final data = DeepLinkService.parseUri(
        'muxpod://connect?server=my-server&session=main&window=shell&pane=0',
      );
      expect(data.server, 'my-server');
      expect(data.session, 'main');
      expect(data.window, 'shell');
      expect(data.pane, 0);
      expect(data.hasTarget, isTrue);
    });

    test('returns empty data for non-muxpod scheme', () {
      final data = DeepLinkService.parseUri('https://example.com');
      expect(data.hasTarget, isFalse);
      expect(data.server, isNull);
    });

    test('returns empty data for invalid URI', () {
      final data = DeepLinkService.parseUri('not a uri');
      expect(data.hasTarget, isFalse);
    });

    test('returns null pane for non-numeric pane', () {
      final data = DeepLinkService.parseUri(
        'muxpod://connect?server=s&pane=abc',
      );
      expect(data.server, 's');
      expect(data.pane, isNull);
    });

    test('returns missing fields as null', () {
      final data = DeepLinkService.parseUri(
        'muxpod://connect?server=my-server',
      );
      expect(data.server, 'my-server');
      expect(data.session, isNull);
      expect(data.window, isNull);
      expect(data.pane, isNull);
    });

    test('decodes escaped query values and accepts a negative pane index', () {
      final data = DeepLinkService.parseUri(
        'muxpod://connect?server=prod%20host&session=main%2Fapi&pane=-1',
      );

      expect(data.server, 'prod host');
      expect(data.session, 'main/api');
      expect(data.pane, -1);
    });
  });

  group('DeepLinkService', () {
    test('initialize reads initial link', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getInitialLink') {
              return 'muxpod://connect?server=my-server&session=main';
            }
            return null;
          });

      final service = DeepLinkService();
      await service.initialize();

      expect(service.initialLink?.server, 'my-server');
      expect(service.initialLink?.session, 'main');
      service.dispose();
    });

    test('initialize handles missing plugin', () async {
      final service = DeepLinkService();
      await service.initialize();
      expect(service.initialLink, isNull);
      service.dispose();
    });

    test(
      'forwards valid hot links and ignores links without a server',
      () async {
        final service = DeepLinkService();
        await service.initialize();
        final received = <DeepLinkData>[];
        final subscription = service.linkStream.listen(received.add);

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'com.muxpod.app/deeplink',
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall(
                  'onDeepLink',
                  'muxpod://connect?server=s&pane=2',
                ),
              ),
              (_) {},
            );
        await Future<void>.delayed(Duration.zero);
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'com.muxpod.app/deeplink',
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('onDeepLink', 'muxpod://connect?session=main'),
              ),
              (_) {},
            );
        await Future<void>.delayed(Duration.zero);

        expect(received, hasLength(1));
        expect(received.single.server, 's');
        expect(received.single.pane, 2);
        await subscription.cancel();
        service.dispose();
      },
    );

    test('dispose does not throw', () {
      final service = DeepLinkService();
      service.dispose();
      expect(service.linkStream.isBroadcast, isTrue);
    });
  });
}
