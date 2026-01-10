import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pointycastle/export.dart';

import '../../models/enums.dart';

/// 鍵インポート結果
class KeyImportResult {
  const KeyImportResult({
    required this.publicKeyOpenSSH,
    required this.fingerprint,
    required this.type,
    this.bits,
    required this.isEncrypted,
  });

  final String publicKeyOpenSSH;
  final String fingerprint;
  final KeyType type;
  final int? bits;
  final bool isEncrypted;
}

/// 鍵インポートエラー
class KeyImportException implements Exception {
  const KeyImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// SSH鍵インポートサービス
///
/// PEM形式の秘密鍵をパースして検証する。
class KeyImportService {
  KeyImportService();

  /// 秘密鍵をパースしてメタデータを抽出
  Future<KeyImportResult> parsePrivateKey(
    String privateKeyPem, {
    String? passphrase,
  }) async {
    // PEM形式の検証
    if (!_isPemFormat(privateKeyPem)) {
      throw const KeyImportException('Invalid PEM format');
    }

    // 暗号化されているか確認
    final isEncrypted = _isEncrypted(privateKeyPem);
    if (isEncrypted && passphrase == null) {
      throw const KeyImportException('Key is encrypted. Passphrase required.');
    }

    try {
      // dartssh2を使ってパース
      final keyPairs = SSHKeyPair.fromPem(privateKeyPem, passphrase);
      if (keyPairs.isEmpty) {
        throw const KeyImportException('No valid key found in PEM');
      }

      final keyPair = keyPairs.first;
      final type = _detectKeyType(keyPair);
      final bits = _detectBits(keyPair, type);
      final publicKeyOpenSSH = _extractPublicKeyOpenSSH(keyPair);
      final fingerprint = _calculateFingerprint(keyPair);

      return KeyImportResult(
        publicKeyOpenSSH: publicKeyOpenSSH,
        fingerprint: fingerprint,
        type: type,
        bits: bits,
        isEncrypted: isEncrypted,
      );
    } catch (e) {
      if (e is KeyImportException) rethrow;
      throw KeyImportException('Failed to parse key: $e');
    }
  }

  /// 公開鍵をパース
  Future<KeyImportResult> parsePublicKey(String publicKey) async {
    final trimmed = publicKey.trim();

    // OpenSSH形式 (ssh-rsa AAAA... comment)
    if (trimmed.startsWith('ssh-')) {
      return _parseOpenSSHPublicKey(trimmed);
    }

    // PEM形式
    if (trimmed.contains('BEGIN') && trimmed.contains('PUBLIC KEY')) {
      return _parsePemPublicKey(trimmed);
    }

    throw const KeyImportException('Unsupported public key format');
  }

  /// 秘密鍵と公開鍵が一致するか検証
  Future<bool> verifyKeyPair(
    String privateKeyPem,
    String publicKey, {
    String? passphrase,
  }) async {
    try {
      final privateResult = await parsePrivateKey(privateKeyPem, passphrase: passphrase);
      final publicResult = await parsePublicKey(publicKey);

      // フィンガープリントで比較
      return privateResult.fingerprint == publicResult.fingerprint;
    } catch (_) {
      return false;
    }
  }

  bool _isPemFormat(String content) {
    return content.contains('-----BEGIN') && content.contains('-----END');
  }

  bool _isEncrypted(String pemContent) {
    return pemContent.contains('ENCRYPTED') ||
        pemContent.contains('Proc-Type: 4,ENCRYPTED') ||
        pemContent.contains('DEK-Info:');
  }

  KeyType _detectKeyType(SSHKeyPair keyPair) {
    final typeStr = keyPair.type.toLowerCase();
    if (typeStr.contains('rsa')) {
      return KeyType.rsa;
    } else if (typeStr.contains('ed25519')) {
      return KeyType.ed25519;
    } else if (typeStr.contains('ecdsa')) {
      return KeyType.ecdsa;
    }
    return KeyType.rsa; // デフォルト
  }

  int? _detectBits(SSHKeyPair keyPair, KeyType type) {
    if (type == KeyType.rsa) {
      // RSAの場合はモジュラスのビット数を返す
      // dartssh2のAPIからは直接取得できないため、公開鍵から推定
      final pubKey = keyPair.toPublicKey();
      final pubKeyStr = pubKey.toString();
      // 簡易的な推定（実際にはバイト数から計算）
      if (pubKeyStr.length > 700) return 4096;
      if (pubKeyStr.length > 400) return 3072;
      return 2048;
    }
    return null;
  }

  String _extractPublicKeyOpenSSH(SSHKeyPair keyPair) {
    final pubKey = keyPair.toPublicKey();
    return pubKey.toString();
  }

  String _calculateFingerprint(SSHKeyPair keyPair) {
    // dartssh2のSSHKeyPairからフィンガープリントを計算
    final pubKey = keyPair.toPublicKey();
    final pubKeyStr = pubKey.toString();

    // OpenSSH形式からbase64部分を抽出
    final parts = pubKeyStr.split(' ');
    if (parts.length >= 2) {
      try {
        final keyData = base64Decode(parts[1]);
        final digest = SHA256Digest();
        final hash = digest.process(Uint8List.fromList(keyData));
        return 'SHA256:${base64Encode(hash).replaceAll('=', '')}';
      } catch (_) {
        // フォールバック
      }
    }

    // フォールバック: 文字列のハッシュ
    final digest = SHA256Digest();
    final hash = digest.process(Uint8List.fromList(utf8.encode(pubKeyStr)));
    return 'SHA256:${base64Encode(hash).replaceAll('=', '')}';
  }

  KeyImportResult _parseOpenSSHPublicKey(String publicKey) {
    final parts = publicKey.split(' ');
    if (parts.length < 2) {
      throw const KeyImportException('Invalid OpenSSH public key format');
    }

    final keyType = parts[0];
    final keyData = parts[1];

    KeyType type;
    int? bits;

    if (keyType == 'ssh-rsa') {
      type = KeyType.rsa;
      // RSAのビット数を推定
      try {
        final decoded = base64Decode(keyData);
        if (decoded.length > 400) {
          bits = 4096;
        } else if (decoded.length > 300) {
          bits = 3072;
        } else {
          bits = 2048;
        }
      } catch (_) {
        bits = 2048;
      }
    } else if (keyType == 'ssh-ed25519') {
      type = KeyType.ed25519;
    } else if (keyType.startsWith('ecdsa')) {
      type = KeyType.ecdsa;
    } else {
      throw KeyImportException('Unsupported key type: $keyType');
    }

    // フィンガープリント計算
    String fingerprint;
    try {
      final decoded = base64Decode(keyData);
      final digest = SHA256Digest();
      final hash = digest.process(Uint8List.fromList(decoded));
      fingerprint = 'SHA256:${base64Encode(hash).replaceAll('=', '')}';
    } catch (_) {
      throw const KeyImportException('Failed to calculate fingerprint');
    }

    return KeyImportResult(
      publicKeyOpenSSH: publicKey,
      fingerprint: fingerprint,
      type: type,
      bits: bits,
      isEncrypted: false,
    );
  }

  KeyImportResult _parsePemPublicKey(String pemContent) {
    // PEM公開鍵のパース（簡易版）
    // 実際にはASN.1パーサーが必要

    // RSA公開鍵と仮定
    final digest = SHA256Digest();
    final hash = digest.process(Uint8List.fromList(utf8.encode(pemContent)));
    final fingerprint = 'SHA256:${base64Encode(hash).replaceAll('=', '')}';

    return KeyImportResult(
      publicKeyOpenSSH: 'ssh-rsa ... (from PEM)',
      fingerprint: fingerprint,
      type: KeyType.rsa,
      bits: 2048,
      isEncrypted: false,
    );
  }
}
