import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// セキュアストレージサービス
class SecureStorageService {
  final FlutterSecureStorage _storage;

  /// テスト用のインメモリストレージ。
  static Map<String, String>? _testValues;

  /// テスト用のストレージ値をセットする。
  /// null を渡すとテストモードを解除する。
  static void setTestValues(Map<String, String>? values) {
    _testValues = values != null ? Map.of(values) : null;
  }

  SecureStorageService()
      : _storage = const FlutterSecureStorage();

  // ===== パスワード管理 =====

  /// パスワードを保存
  Future<void> savePassword(String connectionId, String password) async {
    await _writeValue('password_$connectionId', password);
  }

  /// パスワードを取得
  Future<String?> getPassword(String connectionId) async {
    return await _readValue('password_$connectionId');
  }

  /// パスワードを削除
  Future<void> deletePassword(String connectionId) async {
    await _deleteValue('password_$connectionId');
  }

  // ===== SSH鍵管理 =====

  /// 秘密鍵を保存
  Future<void> savePrivateKey(String keyId, String privateKey) async {
    await _writeValue('privatekey_$keyId', privateKey);
  }

  /// 秘密鍵を取得
  Future<String?> getPrivateKey(String keyId) async {
    return await _readValue('privatekey_$keyId');
  }

  /// 秘密鍵を削除
  Future<void> deletePrivateKey(String keyId) async {
    await _deleteValue('privatekey_$keyId');
  }

  /// パスフレーズを保存
  Future<void> savePassphrase(String keyId, String passphrase) async {
    await _writeValue('passphrase_$keyId', passphrase);
  }

  /// パスフレーズを取得
  Future<String?> getPassphrase(String keyId) async {
    return await _readValue('passphrase_$keyId');
  }

  /// パスフレーズを削除
  Future<void> deletePassphrase(String keyId) async {
    await _deleteValue('passphrase_$keyId');
  }

  // ===== ユーティリティ =====

  /// すべてのデータを削除
  Future<void> deleteAll() async {
    if (_testValues != null) {
      _testValues!.clear();
      return;
    }
    await _storage.deleteAll();
  }

  /// 指定プレフィックスのキー一覧を取得
  Future<List<String>> getKeysWithPrefix(String prefix) async {
    final all = await _readAllValues();
    return all.keys.where((key) => key.startsWith(prefix)).toList();
  }

  // ===== 低レベルストレージ =====

  /// 任意の値を読み込む。
  Future<String?> readValue(String key) async => _readValue(key);

  /// 任意の値を書き込む。
  Future<void> writeValue(String key, String value) async => _writeValue(key, value);

  /// 任意の値を削除する。
  Future<void> deleteValue(String key) async => _deleteValue(key);

  Future<String?> _readValue(String key) async {
    if (_testValues != null) {
      return _testValues![key];
    }
    return await _storage.read(key: key);
  }

  Future<void> _writeValue(String key, String value) async {
    if (_testValues != null) {
      _testValues![key] = value;
      return;
    }
    await _storage.write(key: key, value: value);
  }

  Future<void> _deleteValue(String key) async {
    if (_testValues != null) {
      _testValues!.remove(key);
      return;
    }
    await _storage.delete(key: key);
  }

  Future<Map<String, String>> _readAllValues() async {
    if (_testValues != null) {
      return Map.of(_testValues!);
    }
    return await _storage.readAll();
  }

  // ===== ホスト鍵検証 =====

  /// ホスト鍵フィンガープリントを保存
  Future<void> saveHostKeyFingerprint(
    String host,
    int port,
    String type,
    String fingerprint,
  ) async {
    await _writeValue(_hostKeyKey(host, port, type), fingerprint);
  }

  /// ホスト鍵フィンガープリントを取得
  Future<String?> getHostKeyFingerprint(
    String host,
    int port,
    String type,
  ) async {
    return await _readValue(_hostKeyKey(host, port, type));
  }

  /// ホスト鍵フィンガープリントを削除
  Future<void> deleteHostKeyFingerprint(
    String host,
    int port,
    String type,
  ) async {
    await _deleteValue(_hostKeyKey(host, port, type));
  }

  String _hostKeyKey(String host, int port, String type) {
    return 'hostkey_${host}_${port}_$type';
  }
}
