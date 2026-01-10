/// Key Service Contract
///
/// SSH鍵管理のサービス層インターフェース。
/// 鍵の生成、インポート、エクスポート、セキュアストレージを担当。

import 'dart:async';

import '../models/ssh_key.dart';

/// 鍵生成オプション
class KeyGenerationOptions {
  final KeyType type;
  final int? bits; // RSAのみ: 2048, 3072, 4096
  final String? passphrase;
  final String? comment;

  const KeyGenerationOptions({
    required this.type,
    this.bits,
    this.passphrase,
    this.comment,
  });
}

/// 鍵インポート結果
class KeyImportResult {
  final SSHKey key;
  final bool requiresPassphrase;

  const KeyImportResult({
    required this.key,
    required this.requiresPassphrase,
  });
}

/// 鍵サービスインターフェース
abstract class KeyService {
  /// 鍵一覧取得
  Future<List<SSHKey>> listKeys();

  /// 鍵取得
  Future<SSHKey?> getKey(String keyId);

  /// 鍵生成
  Future<SSHKey> generateKey({
    required String name,
    required KeyGenerationOptions options,
  });

  /// 鍵インポート（PEM形式）
  Future<KeyImportResult> importKey({
    required String name,
    required String privateKeyPem,
    String? passphrase,
  });

  /// 鍵インポート（ファイルから）
  Future<KeyImportResult> importKeyFromFile({
    required String name,
    required String filePath,
    String? passphrase,
  });

  /// 秘密鍵取得（認証用）
  Future<String> getPrivateKey({
    required String keyId,
    String? passphrase,
  });

  /// 公開鍵取得（OpenSSH形式）
  Future<String> getPublicKey(String keyId);

  /// 鍵削除
  Future<void> deleteKey(String keyId);

  /// 鍵名更新
  Future<void> updateKeyName({
    required String keyId,
    required String name,
  });

  /// デフォルト鍵設定
  Future<void> setDefaultKey(String keyId);

  /// デフォルト鍵取得
  Future<SSHKey?> getDefaultKey();

  /// フィンガープリント計算
  Future<String> calculateFingerprint(String publicKey);

  /// 鍵タイプ判定
  KeyType detectKeyType(String privateKeyPem);

  /// パスフレーズ検証
  Future<bool> verifyPassphrase({
    required String keyId,
    required String passphrase,
  });
}
