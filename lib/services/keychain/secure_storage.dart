import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// セキュアストレージサービス
class SecureStorageService {
  final FlutterSecureStorage _storage;

  /// テスト用のインメモリストレージ。
  static Map<String, String>? _testValues;

  /// テスト用: 読み取り時に例外（復号不能）を投げるキー一覧。
  static Set<String>? _testThrowKeys;

  /// テスト用のストレージ値をセットする。
  /// null を渡すとテストモードを解除する。
  static void setTestValues(Map<String, String>? values) {
    _testValues = values != null ? Map.of(values) : null;
  }

  /// テスト用: 読み取り時に例外（PlatformException: 復号不能）を投げるキーを指定する。
  /// null を渡すと解除する。
  static void setTestThrowKeys(Set<String>? keys) {
    _testThrowKeys = keys != null ? Set.of(keys) : null;
  }

  SecureStorageService() : _storage = const FlutterSecureStorage();

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
  ///
  /// 復号不能（Keystore キー欠如など）の場合は例外を捕捉して null を返す。
  /// それ以外の例外（一時障害・実装エラー）は再スローし、破損と誤判定しない。
  Future<String?> getPrivateKey(String keyId) async {
    try {
      return await _readValue('privatekey_$keyId');
    } on PlatformException catch (e) {
      // Keystore 復号不能（Failed to unwrap key）など → 破損鍵として null 扱い
      debugPrint(
        '[SecureStorage] getPrivateKey failed for id=$keyId: ${e.code}',
      );
      return null;
    } catch (e) {
      // 一時障害・実装エラーは再スロー（破損と誤判定しない）
      debugPrint(
        '[SecureStorage] getPrivateKey unexpected error for id=$keyId: $e',
      );
      rethrow;
    }
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
  Future<void> writeValue(String key, String value) async =>
      _writeValue(key, value);

  /// 任意の値を削除する。
  Future<void> deleteValue(String key) async => _deleteValue(key);

  Future<String?> _readValue(String key) async {
    if (_testValues != null) {
      if (_testThrowKeys?.contains(key) ?? false) {
        throw PlatformException(
          code: 'invalid_key',
          message: 'Failed to unwrap key',
        );
      }
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
    // resetOnError の既定は true で、Android の readAll() は 1 件でも復号
    // 不能なエントリがあると secure storage 全体を消してから再試行する
    // （パスワード・秘密鍵・接続設定まで飛ぶ）。列挙でその挙動は許容でき
    // ないため、ここだけ明示的に無効化して例外として受け取る。
    return await _storage.readAll(
      aOptions: const AndroidOptions(resetOnError: false),
    );
  }

  // ===== ホスト鍵検証 =====

  /// ホスト鍵フィンガープリントを保存
  Future<void> saveHostKeyFingerprint(
    String host,
    int port,
    String type,
    String fingerprint,
  ) async {
    final key = _hostKeyKey(host, port, type);
    await _writeValue(key, fingerprint);
    await _rememberHostKey(key);
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
    final key = _hostKeyKey(host, port, type);
    await _deleteValue(key);
    await _forgetHostKey(key);
  }

  /// 保存済みのホスト鍵フィンガープリントを全て削除し、削除件数を返す。
  ///
  /// サーバーのホスト鍵が変わった / 保存状態が壊れた場合に、アプリデータ
  /// 全体を消さず、次回接続でホスト鍵を再受諾できるようにする。
  ///
  /// 索引に載っているキーは個別削除する。個別削除は復号を伴わないので、
  /// fingerprint の保存値が壊れていても成功する（この機能の本来の用途）。
  /// 索引を持たない旧バージョンが書いた分は列挙で拾うが、列挙は復号を伴う
  /// ため失敗し得る。失敗しても索引側の削除は続行する。
  Future<int> deleteAllHostKeyFingerprints() async {
    final keys = <String>{};
    try {
      keys.addAll(await _hostKeyIndex());
    } on PlatformException catch (e) {
      debugPrint('hostkey index unreadable: ${e.code}');
    }
    try {
      keys.addAll(await getKeysWithPrefix(_hostKeyPrefix));
    } on PlatformException catch (e) {
      debugPrint('hostkey enumeration failed: ${e.code}');
    }
    keys.remove(_hostKeyIndexKey);
    for (final key in keys) {
      await _deleteValue(key);
    }
    await _deleteValue(_hostKeyIndexKey);
    return keys.length;
  }

  // ===== ホスト鍵の索引 =====
  //
  // 「どのキーを書いたか」だけを 1 エントリにまとめて保持する。fingerprint
  // 本体とは別エントリなので、本体が復号不能になっても索引から鍵名を取り出
  // して個別削除できる。索引キー自身も hostkey_ プレフィックスに属するため、
  // 全消去時に一緒に消える。

  Future<Set<String>> _hostKeyIndex() async {
    final raw = await _readValue(_hostKeyIndexKey);
    if (raw == null || raw.isEmpty) return <String>{};
    return raw.split('\n').where((k) => k.isNotEmpty).toSet();
  }

  Future<void> _rememberHostKey(String key) async {
    final index = await _hostKeyIndex();
    if (!index.add(key)) return;
    await _writeValue(_hostKeyIndexKey, index.join('\n'));
  }

  Future<void> _forgetHostKey(String key) async {
    final index = await _hostKeyIndex();
    if (!index.remove(key)) return;
    await _writeValue(_hostKeyIndexKey, index.join('\n'));
  }

  static const String _hostKeyPrefix = 'hostkey_';

  /// 書き込んだホスト鍵キーの索引（鍵名のみ、値は含まない）。
  static const String _hostKeyIndexKey = '${_hostKeyPrefix}index';

  String _hostKeyKey(String host, int port, String type) {
    return '$_hostKeyPrefix${host}_${port}_$type';
  }
}
