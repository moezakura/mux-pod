import 'dart:convert';

import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'helpers/ssh_client_fakes.dart';

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
  });
}
