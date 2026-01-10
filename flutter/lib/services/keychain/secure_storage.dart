import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// セキュアストレージサービス
///
/// flutter_secure_storage を使用してセンシティブなデータを暗号化保存する。
/// - SSH秘密鍵
/// - 接続パスワード
/// - その他の機密情報
class SecureStorageService {
  SecureStorageService({
    FlutterSecureStorage? storage,
  }) : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            );

  final FlutterSecureStorage _storage;

  // === キープレフィックス ===
  static const String _privateKeyPrefix = 'ssh_private_key_';
  static const String _passwordPrefix = 'password_';
  static const String _passphrasePrefix = 'passphrase_';

  // === SSH秘密鍵 ===

  /// 秘密鍵を保存
  Future<void> savePrivateKey({
    required String keyId,
    required String pem,
  }) async {
    await _storage.write(
      key: '$_privateKeyPrefix$keyId',
      value: pem,
    );
  }

  /// 秘密鍵を取得
  Future<String?> getPrivateKey(String keyId) async {
    return await _storage.read(key: '$_privateKeyPrefix$keyId');
  }

  /// 秘密鍵を削除
  Future<void> deletePrivateKey(String keyId) async {
    await _storage.delete(key: '$_privateKeyPrefix$keyId');
  }

  // === 接続パスワード ===

  /// パスワードを保存
  Future<void> savePassword({
    required String connectionId,
    required String password,
  }) async {
    await _storage.write(
      key: '$_passwordPrefix$connectionId',
      value: password,
    );
  }

  /// パスワードを取得
  Future<String?> getPassword(String connectionId) async {
    return await _storage.read(key: '$_passwordPrefix$connectionId');
  }

  /// パスワードを削除
  Future<void> deletePassword(String connectionId) async {
    await _storage.delete(key: '$_passwordPrefix$connectionId');
  }

  // === 鍵パスフレーズ ===

  /// パスフレーズを保存
  Future<void> savePassphrase({
    required String keyId,
    required String passphrase,
  }) async {
    await _storage.write(
      key: '$_passphrasePrefix$keyId',
      value: passphrase,
    );
  }

  /// パスフレーズを取得
  Future<String?> getPassphrase(String keyId) async {
    return await _storage.read(key: '$_passphrasePrefix$keyId');
  }

  /// パスフレーズを削除
  Future<void> deletePassphrase(String keyId) async {
    await _storage.delete(key: '$_passphrasePrefix$keyId');
  }

  // === ユーティリティ ===

  /// すべてのデータを削除
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  /// 特定のプレフィックスのキーをすべて削除
  Future<void> deleteAllWithPrefix(String prefix) async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(prefix)) {
        await _storage.delete(key: key);
      }
    }
  }
}
