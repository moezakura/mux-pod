import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';

void main() {
  setUp(() => SecureStorageService.setTestValues({}));

  tearDown(() {
    SecureStorageService.setTestValues(null);
    SecureStorageService.setTestThrowKeys(null);
  });

  group('SecureStorageService.getPrivateKey', () {
    test('returns null when key is not stored', () async {
      SecureStorageService.setTestValues({});
      final storage = SecureStorageService();

      expect(await storage.getPrivateKey('missing-id'), isNull);
    });

    test('returns stored private key', () async {
      SecureStorageService.setTestValues({'privatekey_k1': 'PRIVATE_KEY'});
      final storage = SecureStorageService();

      expect(await storage.getPrivateKey('k1'), 'PRIVATE_KEY');
    });

    test(
      'returns null when read throws PlatformException (unreadable key)',
      () async {
        // 復号不能（Keystore キー欠如）をシミュレート
        SecureStorageService.setTestValues({'privatekey_k1': 'X'});
        SecureStorageService.setTestThrowKeys({'privatekey_k1'});
        final storage = SecureStorageService();

        expect(await storage.getPrivateKey('k1'), isNull);
      },
    );

    test('returns stored key when not in throw keys', () async {
      SecureStorageService.setTestValues({'privatekey_k1': 'PRIVATE_KEY'});
      SecureStorageService.setTestThrowKeys({'privatekey_other'});
      final storage = SecureStorageService();

      expect(await storage.getPrivateKey('k1'), 'PRIVATE_KEY');
    });
  });

  group('SecureStorageService host keys', () {
    test(
      'deleteAllHostKeyFingerprints removes only hostkey_* entries',
      () async {
        SecureStorageService.setTestValues({
          'hostkey_192.168.1.3_22_ssh-ed25519': 'aa:bb:cc',
          'hostkey_example.test_2222_ssh-rsa': 'dd:ee:ff',
          'password_conn1': 'secret',
          'privatekey_k1': 'pem',
        });
        final service = SecureStorageService();
        await service.deleteAllHostKeyFingerprints();

        expect(
          await service.getHostKeyFingerprint('192.168.1.3', 22, 'ssh-ed25519'),
          isNull,
        );
        expect(
          await service.getHostKeyFingerprint('example.test', 2222, 'ssh-rsa'),
          isNull,
        );
        // 認証情報は消えない
        expect(await service.getPassword('conn1'), 'secret');
        expect(await service.getPrivateKey('k1'), 'pem');
      },
    );

    test('deleteAllHostKeyFingerprints reports how many it removed', () async {
      final service = SecureStorageService();
      await service.saveHostKeyFingerprint('a.test', 22, 'ssh-ed25519', 'aa');
      await service.saveHostKeyFingerprint('b.test', 22, 'ssh-rsa', 'bb');

      expect(await service.deleteAllHostKeyFingerprints(), 2);
      expect(await service.deleteAllHostKeyFingerprints(), 0);
    });

    test(
      'deleteAllHostKeyFingerprints is a no-op when nothing is stored',
      () async {
        final service = SecureStorageService();
        expect(await service.deleteAllHostKeyFingerprints(), 0);
        expect(
          await service.getHostKeyFingerprint('192.168.1.3', 22, 'ssh-ed25519'),
          isNull,
        );
      },
    );

    test('saved fingerprints are indexed by key name', () async {
      final service = SecureStorageService();
      await service.saveHostKeyFingerprint('a.test', 22, 'ssh-ed25519', 'aa');

      expect(
        await service.readValue('hostkey_index'),
        'hostkey_a.test_22_ssh-ed25519',
      );

      await service.deleteHostKeyFingerprint('a.test', 22, 'ssh-ed25519');
      expect(await service.readValue('hostkey_index'), '');
    });

    test('a clear removes an indexed pin whose value is unreadable', () async {
      // 索引には載っているが、読み取ると復号不能で落ちるエントリ。個別削除は
      // 復号を伴わないので、それでも消えなければならない（本機能の本来の用途）。
      SecureStorageService.setTestValues({
        'hostkey_index': 'hostkey_broken.test_22_ssh-ed25519',
        'hostkey_broken.test_22_ssh-ed25519': 'corrupt',
        'password_conn1': 'secret',
      });
      SecureStorageService.setTestThrowKeys({
        'hostkey_broken.test_22_ssh-ed25519',
      });
      final service = SecureStorageService();

      expect(await service.deleteAllHostKeyFingerprints(), 1);
      SecureStorageService.setTestThrowKeys(null);
      expect(
        await service.getHostKeyFingerprint('broken.test', 22, 'ssh-ed25519'),
        isNull,
      );
      expect(await service.readValue('hostkey_index'), isNull);
      expect(await service.getPassword('conn1'), 'secret');
    });
  });

  group('SecureStorageService proxy passwords', () {
    test('save, get and delete a single hop password', () async {
      final service = SecureStorageService();

      expect(await service.getProxyPassword('conn1', 0), isNull);

      await service.saveProxyPassword('conn1', 0, 'hop0secret');
      await service.saveProxyPassword('conn1', 1, 'hop1secret');

      expect(await service.getProxyPassword('conn1', 0), 'hop0secret');
      expect(await service.getProxyPassword('conn1', 1), 'hop1secret');

      await service.deleteProxyPassword('conn1', hopIndex: 0);

      expect(await service.getProxyPassword('conn1', 0), isNull);
      // 別 hop は消えない
      expect(await service.getProxyPassword('conn1', 1), 'hop1secret');
    });

    test('deleteProxyPassword without hopIndex removes all hops', () async {
      final service = SecureStorageService();
      await service.saveProxyPassword('conn1', 0, 'a');
      await service.saveProxyPassword('conn1', 2, 'b');
      await service.saveProxyPassword('conn2', 0, 'c');
      // 直接キー書き込みで orphan（上限外 index）も用意する
      await service.writeValue('proxy_password_conn1_7', 'orphan');

      await service.deleteProxyPassword('conn1');

      expect(await service.getProxyPassword('conn1', 0), isNull);
      expect(await service.getProxyPassword('conn1', 2), isNull);
      expect(await service.readValue('proxy_password_conn1_7'), isNull);
      // 別接続は消えない
      expect(await service.getProxyPassword('conn2', 0), 'c');
    });

    test(
      'deleteProxyPassword without hopIndex is a no-op when nothing stored',
      () async {
        final service = SecureStorageService();

        await service.deleteProxyPassword('missing');

        expect(await service.getKeysWithPrefix('proxy_password_'), isEmpty);
      },
    );
  });
}
