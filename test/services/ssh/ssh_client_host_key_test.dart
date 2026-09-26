import 'dart:convert';

import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_muxpod/services/ssh/ssh_connector.dart';
import 'package:flutter_muxpod/services/ssh/ssh_proxy_tunneler.dart';
import 'helpers/ssh_client_fakes.dart' show FakeRawSshClient, FakeSocket;
import 'helpers/ssh_proxy_fakes.dart';

void main() {
  group('SshClient lifecycle contracts', () {
    setUp(() => SecureStorageService.setTestValues({}));
    tearDown(() => SecureStorageService.setTestValues(null));

    test(
      'SSH-LIFE-017: host-key callback implements TOFU and rejects changes',
      () async {
        // dartssh2 2.18.0+ は OpenSSH 形式 "SHA256:<base64>" の UTF-8 バイトを渡す
        var fingerprint = Uint8List.fromList(
          utf8.encode('SHA256:testfingerprint123'),
        );
        Future<({SSHSocket socket, SSHClient client})> factory(
          String host,
          int port,
          String username,
          SshConnectOptions options,
          void Function() onAuthenticated,
          Future<bool> Function(String, Uint8List) verify,
        ) async {
          final accepted = await verify('ssh-ed25519', fingerprint);
          if (!accepted) throw SSHAuthFailError('host key rejected');
          final raw = FakeRawSshClient();
          onAuthenticated();
          raw.authentication.complete();
          return (socket: FakeSocket(), client: raw);
        }

        final first = SshClient(connectionFactory: factory);
        await first.connect(
          host: 'example.test',
          port: 2222,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        );
        expect(
          await SecureStorageService().getHostKeyFingerprint(
            'example.test',
            2222,
            'ssh-ed25519',
          ),
          'SHA256:testfingerprint123',
        );
        await first.disconnect();

        fingerprint = Uint8List.fromList(
          utf8.encode('SHA256:changedfingerprint456'),
        );
        final changed = SshClient(connectionFactory: factory);
        await expectLater(
          changed.connect(
            host: 'example.test',
            port: 2222,
            username: 'user',
            options: SshConnectOptions(password: 'pw'),
            lightweight: true,
          ),
          throwsA(isA<SshAuthenticationError>()),
        );
        expect(changed.lastError, contains('Authentication failed'));
      },
    );

    test('SSH-LIFE-017b: 旧形式（MD5 hex）保存値は認証成功後に SHA256 形式へ移行する', () async {
      // 旧 dartssh2（<= 2.17）で保存された MD5 hex 形式の値をシード
      SecureStorageService.setTestValues({
        'hostkey_example.test_2222_ssh-ed25519': '66:5d:56:0b:41:6a:22:c5',
      });
      final fingerprint = Uint8List.fromList(
        utf8.encode('SHA256:newformatvalue789'),
      );
      Future<({SSHSocket socket, SSHClient client})> factory(
        String host,
        int port,
        String username,
        SshConnectOptions options,
        void Function() onAuthenticated,
        Future<bool> Function(String, Uint8List) verify,
      ) async {
        final accepted = await verify('ssh-ed25519', fingerprint);
        if (!accepted) throw SSHAuthFailError('host key rejected');
        final raw = FakeRawSshClient();
        onAuthenticated();
        raw.authentication.complete();
        return (socket: FakeSocket(), client: raw);
      }

      final client = SshClient(connectionFactory: factory);
      await client.connect(
        host: 'example.test',
        port: 2222,
        username: 'user',
        options: SshConnectOptions(password: 'pw'),
        lightweight: true,
      );
      expect(client.isConnected, isTrue);
      // 認証成功後に正規形式へ更新されている
      expect(
        await SecureStorageService().getHostKeyFingerprint(
          'example.test',
          2222,
          'ssh-ed25519',
        ),
        'SHA256:newformatvalue789',
      );
      await client.disconnect();
    });

    test('SSH-LIFE-017c: 旧形式保存値は認証失敗時には更新されない', () async {
      SecureStorageService.setTestValues({
        'hostkey_example.test_2222_ssh-ed25519': '66:5d:56:0b:41:6a:22:c5',
      });
      final fingerprint = Uint8List.fromList(
        utf8.encode('SHA256:newformatvalue789'),
      );
      Future<({SSHSocket socket, SSHClient client})> factory(
        String host,
        int port,
        String username,
        SshConnectOptions options,
        void Function() onAuthenticated,
        Future<bool> Function(String, Uint8List) verify,
      ) async {
        final accepted = await verify('ssh-ed25519', fingerprint);
        if (!accepted) throw SSHAuthFailError('host key rejected');
        // 認証失敗: ホスト鍵検証は通るがユーザー認証が失敗する
        throw SSHAuthFailError('auth failed');
      }

      final client = SshClient(connectionFactory: factory);
      await expectLater(
        client.connect(
          host: 'example.test',
          port: 2222,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        ),
        throwsA(isA<SshAuthenticationError>()),
      );
      // 認証失敗時は保存値が更新されない（旧形式のまま）
      expect(
        await SecureStorageService().getHostKeyFingerprint(
          'example.test',
          2222,
          'ssh-ed25519',
        ),
        '66:5d:56:0b:41:6a:22:c5',
      );
    });

    test(
      'SSH-LIFE-017d: 旧形式移行保留は複数件（jump 2 hop）同時に適用される（List 化）',
      () async {
        // jump hop0 / hop1 の両方が旧形式（MD5 hex）で保存されている状態をシード
        SecureStorageService.setTestValues({
          'hostkey_hop0.test_2222_ssh-ed25519': '66:5d:56:0b:41:6a:22:c5',
          'hostkey_hop1.test_2200_ssh-ed25519': 'aa:bb:cc:dd:ee:ff:00:11',
        });

        final tunneler = SshProxyTunneler(
          l10n: () => null,
          socketDialer: (host, port, {timeout}) async => FakeSocket(),
          hopClientFactory: (
            socket,
            hop, {
            required handshakeTimeout,
            required onAuthenticated,
            required onVerifyHostKey,
          }) async {
            final client = FakeProxyHopClient();
            // hop 座標で配線された検証コールバックを呼ぶ（本物のハンドシェイク相当）
            await onVerifyHostKey(
              'ssh-ed25519',
              Uint8List.fromList(
                utf8.encode('SHA256:newformat-${hop.host}'),
              ),
            );
            client.completeAuthentication();
            return client;
          },
        );
        final connector = SshConnector(
          connectionFactory: null,
          l10n: () => null,
          setLastError: (_) {},
          tunneler: tunneler,
        );

        final result = await connector.connect(
          host: 'target.test',
          port: 22,
          username: 'user',
          options: SshConnectOptions(
            password: 'pw',
            timeout: 5,
            proxy: SshProxyOptions(
              hops: const [
                SshProxyHop(host: 'hop0.test', port: 2222, username: 'j0'),
                SshProxyHop(host: 'hop1.test', port: 2200, username: 'j1'),
              ],
              forwardHost: 'target.test',
              forwardPort: 22,
            ),
          ),
          onAuthenticated: () {},
        );
        expect(result.jumpClients, hasLength(2));

        // facade は target 認証成功後に applyPendingMigrationOnAuthenticated を
        // 呼ぶ — 2 件とも正規形式で保存される
        await connector.applyPendingMigrationOnAuthenticated();
        expect(
          await SecureStorageService().getHostKeyFingerprint(
            'hop0.test',
            2222,
            'ssh-ed25519',
          ),
          'SHA256:newformat-hop0.test',
        );
        expect(
          await SecureStorageService().getHostKeyFingerprint(
            'hop1.test',
            2200,
            'ssh-ed25519',
          ),
          'SHA256:newformat-hop1.test',
        );
      },
    );
  });
}
