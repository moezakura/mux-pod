import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/services/connection/proxy_config.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/services/ssh/ssh_proxy_connection_error.dart';
import 'package:flutter_muxpod/services/ssh/ssh_proxy_options_resolver.dart';

void main() {
  AppLocalizations l10n() => lookupAppLocalizations(const Locale('en'));

  setUp(() => SecureStorageService.setTestValues({}));

  tearDown(() {
    SecureStorageService.setTestValues(null);
    SecureStorageService.setTestThrowKeys(null);
  });

  const resolver = SshProxyOptionsResolver();

  group('SshProxyOptionsResolver MR-8 contract', () {
    test('proxy == null returns null (the only null case)', () async {
      final options = await resolver.resolve(
        null,
        connectionId: 'conn1',
        targetHost: 'target.example.com',
        targetPort: 2222,
        l10n: l10n(),
      );

      expect(options, isNull);
    });

    test('missing hop password throws fail-fast with hop coordinates', () async {
      const proxy = ProxyConfig(
        hops: [
          ProxyHop(host: 'jump1', port: 2200, username: 'u1'),
          ProxyHop(host: 'jump2', username: 'u2'),
        ],
      );

      await expectLater(
        resolver.resolve(
          proxy,
          connectionId: 'conn1',
          targetHost: 'target.example.com',
          targetPort: 22,
          l10n: l10n(),
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having((e) => e.hopIndex, 'hopIndex', 0)
              .having((e) => e.hopHost, 'hopHost', 'jump1')
              .having((e) => e.hopPort, 'hopPort', 2200)
              .having(
                (e) => e.message,
                'message',
                contains('jump1'),
              ),
        ),
      );
    });

    test('empty stored password throws fail-fast', () async {
      SecureStorageService.setTestValues({'proxy_password_conn1_0': ''});
      const proxy = ProxyConfig(hops: [ProxyHop(host: 'jump1', username: 'u1')]);

      await expectLater(
        resolver.resolve(
          proxy,
          connectionId: 'conn1',
          targetHost: 'target.example.com',
          targetPort: 22,
          l10n: l10n(),
        ),
        throwsA(isA<SshProxyConnectionError>()),
      );
    });

    test('key hop with unreadable key throws with hop coordinates', () async {
      SecureStorageService.setTestValues({'privatekey_k1': 'PEM'});
      SecureStorageService.setTestThrowKeys({'privatekey_k1'});
      const proxy = ProxyConfig(
        hops: [
          ProxyHop(
            host: 'jump1',
            port: 2222,
            username: 'u1',
            authMethod: 'key',
            keyId: 'k1',
          ),
        ],
      );

      await expectLater(
        resolver.resolve(
          proxy,
          connectionId: 'conn1',
          targetHost: 'target.example.com',
          targetPort: 22,
          l10n: l10n(),
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having((e) => e.hopIndex, 'hopIndex', 0)
              .having((e) => e.hopHost, 'hopHost', 'jump1')
              .having((e) => e.hopPort, 'hopPort', 2222),
        ),
      );
    });

    test('key hop without keyId throws', () async {
      const proxy = ProxyConfig(
        hops: [
          ProxyHop(host: 'jump1', username: 'u1', authMethod: 'key'),
        ],
      );

      await expectLater(
        resolver.resolve(
          proxy,
          connectionId: 'conn1',
          targetHost: 'target.example.com',
          targetPort: 22,
          l10n: l10n(),
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having((e) => e.hopIndex, 'hopIndex', 0)
              .having((e) => e.hopHost, 'hopHost', 'jump1'),
        ),
      );
    });
  });

  group('SshProxyOptionsResolver resolution', () {
    test('resolves password and key hops in chain order (M3 forward)', () async {
      SecureStorageService.setTestValues({
        'proxy_password_conn1_0': 'pw0',
        'privatekey_k1': 'PEM',
        'passphrase_k1': 'phrase',
      });
      const proxy = ProxyConfig(
        hops: [
          ProxyHop(host: 'jump1', username: 'u1'),
          ProxyHop(
            host: 'jump2',
            port: 2222,
            username: 'u2',
            authMethod: 'key',
            keyId: 'k1',
          ),
        ],
      );

      final options = await resolver.resolve(
        proxy,
        connectionId: 'conn1',
        targetHost: 'target.example.com',
        targetPort: 22,
        l10n: l10n(),
      );

      expect(options, isNotNull);
      expect(options!.hops.length, 2);
      expect(options.hops[0].host, 'jump1');
      expect(options.hops[0].password, 'pw0');
      expect(options.hops[0].privateKey, isNull);
      expect(options.hops[1].host, 'jump2');
      expect(options.hops[1].port, 2222);
      expect(options.hops[1].privateKey, 'PEM');
      expect(options.hops[1].passphrase, 'phrase');
      // M3: 転送先は target 座標で解決済み非 null。
      expect(options.forwardHost, 'target.example.com');
      expect(options.forwardPort, 22);
    });

    test('explicit forward target wins over target coordinates', () async {
      SecureStorageService.setTestValues({'proxy_password_conn1_0': 'pw0'});
      const proxy = ProxyConfig(
        hops: [ProxyHop(host: 'jump1', username: 'u1')],
        forwardHost: 'inner.example.com',
        forwardPort: 8080,
      );

      final options = await resolver.resolve(
        proxy,
        connectionId: 'conn1',
        targetHost: 'target.example.com',
        targetPort: 22,
        l10n: l10n(),
      );

      expect(options!.forwardHost, 'inner.example.com');
      expect(options.forwardPort, 8080);
    });

    test('forwardPort only (blank forwardHost) falls back to target (M6)', () async {
      SecureStorageService.setTestValues({'proxy_password_conn1_0': 'pw0'});
      const proxy = ProxyConfig(
        hops: [ProxyHop(host: 'jump1', username: 'u1')],
        forwardHost: '   ',
        forwardPort: 9090,
      );

      final options = await resolver.resolve(
        proxy,
        connectionId: 'conn1',
        targetHost: 'target.example.com',
        targetPort: 22,
        l10n: l10n(),
      );

      expect(options!.forwardHost, 'target.example.com');
      expect(options.forwardPort, 22);
    });

    test('explicit forwardHost with unset forwardPort uses target port', () async {
      SecureStorageService.setTestValues({'proxy_password_conn1_0': 'pw0'});
      const proxy = ProxyConfig(
        hops: [ProxyHop(host: 'jump1', username: 'u1')],
        forwardHost: 'inner.example.com',
      );

      final options = await resolver.resolve(
        proxy,
        connectionId: 'conn1',
        targetHost: 'target.example.com',
        targetPort: 22,
        l10n: l10n(),
      );

      expect(options!.forwardHost, 'inner.example.com');
      expect(options.forwardPort, 22);
    });
  });
}
