import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';

void main() {
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

    test('returns null when read throws PlatformException (unreadable key)',
        () async {
      // 復号不能（Keystore キー欠如）をシミュレート
      SecureStorageService.setTestValues({'privatekey_k1': 'X'});
      SecureStorageService.setTestThrowKeys({'privatekey_k1'});
      final storage = SecureStorageService();

      expect(await storage.getPrivateKey('k1'), isNull);
    });

    test('returns stored key when not in throw keys', () async {
      SecureStorageService.setTestValues({'privatekey_k1': 'PRIVATE_KEY'});
      SecureStorageService.setTestThrowKeys({'privatekey_other'});
      final storage = SecureStorageService();

      expect(await storage.getPrivateKey('k1'), 'PRIVATE_KEY');
    });
  });
}
