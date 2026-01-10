import 'dart:convert';

import '../../models/ssh_key.dart';
import '../storage/storage_service.dart';
import 'secure_storage.dart';

/// SSH鍵リポジトリ
///
/// SSH鍵のメタデータと秘密鍵を管理する。
/// メタデータはSharedPreferences、秘密鍵はSecureStorageに保存。
class KeyRepository {
  KeyRepository({
    required StorageService storageService,
    required SecureStorageService secureStorage,
  })  : _storageService = storageService,
        _secureStorage = secureStorage;

  final StorageService _storageService;
  final SecureStorageService _secureStorage;

  static const String _keysKey = 'ssh_keys';

  /// 全鍵取得
  Future<List<SSHKey>> getAll() async {
    final jsonStr = _storageService.getString(_keysKey);
    if (jsonStr == null) return [];

    final List<dynamic> jsonList = json.decode(jsonStr) as List<dynamic>;
    return jsonList
        .map((j) => SSHKey.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// 単一鍵取得
  Future<SSHKey?> get(String id) async {
    final keys = await getAll();
    try {
      return keys.firstWhere((k) => k.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 鍵保存
  Future<void> save(SSHKey key) async {
    final keys = await getAll();
    final index = keys.indexWhere((k) => k.id == key.id);

    if (index >= 0) {
      keys[index] = key;
    } else {
      keys.add(key);
    }

    await _storageService.setString(
      _keysKey,
      json.encode(keys.map((k) => k.toJson()).toList()),
    );
  }

  /// 秘密鍵保存
  Future<void> savePrivateKey({
    required String keyId,
    required String privateKeyPem,
    String? passphrase,
  }) async {
    await _secureStorage.savePrivateKey(
      keyId: keyId,
      pem: privateKeyPem,
    );

    if (passphrase != null) {
      await _secureStorage.savePassphrase(
        keyId: keyId,
        passphrase: passphrase,
      );
    }
  }

  /// 秘密鍵取得
  Future<String?> getPrivateKey(String keyId) async {
    return await _secureStorage.getPrivateKey(keyId);
  }

  /// パスフレーズ取得
  Future<String?> getPassphrase(String keyId) async {
    return await _secureStorage.getPassphrase(keyId);
  }

  /// 鍵削除
  Future<void> delete(String id) async {
    final keys = await getAll();
    keys.removeWhere((k) => k.id == id);

    await _storageService.setString(
      _keysKey,
      json.encode(keys.map((k) => k.toJson()).toList()),
    );

    // 秘密鍵も削除
    await _secureStorage.deletePrivateKey(id);
    await _secureStorage.deletePassphrase(id);
  }

  /// デフォルト鍵設定
  Future<void> setDefault(String id) async {
    final keys = await getAll();
    final updatedKeys = keys.map((k) {
      return k.copyWith(isDefault: k.id == id);
    }).toList();

    await _storageService.setString(
      _keysKey,
      json.encode(updatedKeys.map((k) => k.toJson()).toList()),
    );
  }

  /// デフォルト鍵取得
  Future<SSHKey?> getDefault() async {
    final keys = await getAll();
    try {
      return keys.firstWhere((k) => k.isDefault);
    } catch (_) {
      // デフォルトがなければ最初の鍵を返す
      return keys.isNotEmpty ? keys.first : null;
    }
  }

  /// 最終使用日時更新
  Future<void> updateLastUsed(String keyId) async {
    final key = await get(keyId);
    if (key != null) {
      await save(key.copyWith(lastUsed: DateTime.now()));
    }
  }

  /// 鍵の存在確認
  Future<bool> exists(String id) async {
    final key = await get(id);
    return key != null;
  }

  /// 鍵数取得
  Future<int> count() async {
    final keys = await getAll();
    return keys.length;
  }
}
