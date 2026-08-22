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
}
