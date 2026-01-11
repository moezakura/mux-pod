import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// セキュアストレージサービス
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(
            encryptedSharedPreferences: true,
          ),
        );

  // ===== パスワード管理 =====

  /// パスワードを保存
  Future<void> savePassword(String connectionId, String password) async {
    await _storage.write(
      key: 'password_$connectionId',
      value: password,
    );
  }

  /// パスワードを取得
  Future<String?> getPassword(String connectionId) async {
    return await _storage.read(key: 'password_$connectionId');
  }

  /// パスワードを削除
  Future<void> deletePassword(String connectionId) async {
    await _storage.delete(key: 'password_$connectionId');
  }

  // ===== SSH鍵管理 =====

  /// 秘密鍵を保存
  Future<void> savePrivateKey(String keyId, String privateKey) async {
    await _storage.write(
      key: 'privatekey_$keyId',
      value: privateKey,
    );
  }

  /// 秘密鍵を取得
  Future<String?> getPrivateKey(String keyId) async {
    return await _storage.read(key: 'privatekey_$keyId');
  }

  /// 秘密鍵を削除
  Future<void> deletePrivateKey(String keyId) async {
    await _storage.delete(key: 'privatekey_$keyId');
  }

  /// パスフレーズを保存
  Future<void> savePassphrase(String keyId, String passphrase) async {
    await _storage.write(
      key: 'passphrase_$keyId',
      value: passphrase,
    );
  }

  /// パスフレーズを取得
  Future<String?> getPassphrase(String keyId) async {
    return await _storage.read(key: 'passphrase_$keyId');
  }

  /// パスフレーズを削除
  Future<void> deletePassphrase(String keyId) async {
    await _storage.delete(key: 'passphrase_$keyId');
  }

  // ===== ユーティリティ =====

  /// すべてのデータを削除
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  /// 指定プレフィックスのキー一覧を取得
  Future<List<String>> getKeysWithPrefix(String prefix) async {
    final all = await _storage.readAll();
    return all.keys.where((key) => key.startsWith(prefix)).toList();
  }
}
