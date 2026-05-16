import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:dartssh2/dartssh2.dart';

/// SSH鍵ペアのデータクラス
class SshKeyPair {
  final String type; // 'ed25519' のみサポート
  final Uint8List privateKeyBytes;
  final Uint8List publicKeyBytes;
  final String fingerprint;
  final String privatePem;
  final String publicKeyString; // authorized_keys形式

  const SshKeyPair({
    required this.type,
    required this.privateKeyBytes,
    required this.publicKeyBytes,
    required this.fingerprint,
    required this.privatePem,
    required this.publicKeyString,
  });
}

/// RSA鍵が指定された場合に投げられる例外。
/// MuxPod は Ed25519 のみをサポートする。
class UnsupportedKeyTypeException implements Exception {
  final String keyType;
  final String message;

  const UnsupportedKeyTypeException(this.keyType, this.message);

  @override
  String toString() => message;
}

/// SSH鍵サービス
///
/// MuxPod は Ed25519 鍵のみをサポートする。RSA は #58 で廃止された。
class SshKeyService {
  /// Ed25519鍵ペアを生成
  Future<SshKeyPair> generateEd25519({String? comment}) async {
    final algorithm = crypto.Ed25519();
    final keyPair = await algorithm.newKeyPair();

    final privateKeyBytes =
        Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyBytes = Uint8List.fromList(publicKey.bytes);

    final fingerprint = calculateFingerprint('ssh-ed25519', publicKeyBytes);
    final privatePem =
        _buildEd25519Pem(privateKeyBytes, publicKeyBytes, comment ?? '');
    final publicKeyString =
        toAuthorizedKeys('ssh-ed25519', publicKeyBytes, comment ?? '');

    return SshKeyPair(
      type: 'ed25519',
      privateKeyBytes: privateKeyBytes,
      publicKeyBytes: publicKeyBytes,
      fingerprint: fingerprint,
      privatePem: privatePem,
      publicKeyString: publicKeyString,
    );
  }

  /// PEM文字列から鍵をパース
  ///
  /// RSA 鍵は [UnsupportedKeyTypeException] を投げる。
  Future<SshKeyPair> parseFromPem(
    String pemContent, {
    String? passphrase,
  }) async {
    final keyPairs = SSHKeyPair.fromPem(pemContent, passphrase);
    if (keyPairs.isEmpty) {
      throw const FormatException('Invalid PEM format or wrong passphrase');
    }

    final keyPair = keyPairs.first;
    final type = keyPair.type;

    if (type != 'ssh-ed25519') {
      throw UnsupportedKeyTypeException(
        type,
        'Unsupported key type: $type. MuxPod only supports Ed25519 keys. '
        'Please generate a new Ed25519 key.',
      );
    }

    // 公開鍵のBlobを取得（dartssh2のencodeは完全なSSH公開鍵Blobを返す）
    final publicKeyBlob = keyPair.toPublicKey().encode();
    // Blobから直接フィンガープリントを計算（再ラップしない）
    final fingerprint = calculateFingerprintFromBlob(publicKeyBlob);

    return SshKeyPair(
      type: 'ed25519',
      privateKeyBytes: Uint8List(0), // パース時は秘密鍵バイトは不要
      publicKeyBytes: publicKeyBlob,
      fingerprint: fingerprint,
      privatePem: pemContent,
      publicKeyString: '$type ${base64Encode(publicKeyBlob)}',
    );
  }

  /// 鍵がパスフレーズで暗号化されているか確認
  bool isEncrypted(String pemContent) {
    return SSHKeyPair.isEncryptedPem(pemContent);
  }

  /// 公開鍵のフィンガープリントを計算 (SHA256)
  String calculateFingerprint(String keyType, Uint8List publicKeyBytes) {
    // SSH公開鍵Blobを構築
    final blob = _buildPublicKeyBlob(keyType, publicKeyBytes);
    return calculateFingerprintFromBlob(blob);
  }

  /// SSH公開鍵Blobから直接フィンガープリントを計算
  String calculateFingerprintFromBlob(Uint8List blob) {
    final hash = sha256.convert(blob);
    final encoded = base64Encode(hash.bytes);
    // パディングの=を除去
    return 'SHA256:${encoded.replaceAll('=', '')}';
  }

  /// 公開鍵をauthorized_keys形式に変換
  String toAuthorizedKeys(String keyType, Uint8List publicKeyBytes, String comment) {
    final blob = _buildPublicKeyBlob(keyType, publicKeyBytes);
    final encoded = base64Encode(blob);
    return comment.isEmpty ? '$keyType $encoded' : '$keyType $encoded $comment';
  }

  // ===== Private Helper Methods =====

  Uint8List _buildPublicKeyBlob(String keyType, Uint8List publicKeyBytes) {
    if (keyType == 'ssh-ed25519') {
      // Ed25519の場合、公開鍵は32バイト
      final typeBytes = utf8.encode(keyType);
      final buffer = BytesBuilder();
      buffer.add(_encodeUint32(typeBytes.length));
      buffer.add(typeBytes);
      buffer.add(_encodeUint32(publicKeyBytes.length));
      buffer.add(publicKeyBytes);
      return buffer.toBytes();
    }
    return publicKeyBytes;
  }

  Uint8List _encodeUint32(int value) {
    return Uint8List.fromList([
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }

  String _buildEd25519Pem(
      Uint8List privateKey, Uint8List publicKey, String comment) {
    // OpenSSH形式のEd25519秘密鍵PEMを構築
    // 簡略化のため、dartssh2で読み込み可能な形式で返す
    final buffer = BytesBuilder();

    // AUTH_MAGIC
    buffer.add(utf8.encode('openssh-key-v1'));
    buffer.addByte(0);

    // ciphername: none
    buffer.add(_encodeString('none'));
    // kdfname: none
    buffer.add(_encodeString('none'));
    // kdfoptions: empty
    buffer.add(_encodeUint32(0));
    // number of keys: 1
    buffer.add(_encodeUint32(1));

    // public key blob
    final pubBlob = _buildPublicKeyBlob('ssh-ed25519', publicKey);
    buffer.add(_encodeUint32(pubBlob.length));
    buffer.add(pubBlob);

    // private key section
    final privateSection = BytesBuilder();
    // checkint (random, same twice)
    final checkInt = DateTime.now().millisecondsSinceEpoch & 0xffffffff;
    privateSection.add(_encodeUint32(checkInt));
    privateSection.add(_encodeUint32(checkInt));
    // keytype
    privateSection.add(_encodeString('ssh-ed25519'));
    // public key
    privateSection.add(_encodeUint32(publicKey.length));
    privateSection.add(publicKey);
    // private key (64 bytes: 32 private + 32 public)
    final fullPrivate = Uint8List.fromList([...privateKey, ...publicKey]);
    privateSection.add(_encodeUint32(fullPrivate.length));
    privateSection.add(fullPrivate);
    // comment
    privateSection.add(_encodeString(comment));
    // padding
    var padding = 1;
    while (privateSection.length % 8 != 0) {
      privateSection.addByte(padding++);
    }

    final privBytes = privateSection.toBytes();
    buffer.add(_encodeUint32(privBytes.length));
    buffer.add(privBytes);

    final encoded = base64Encode(buffer.toBytes());
    final lines = <String>[];
    for (var i = 0; i < encoded.length; i += 70) {
      lines.add(encoded.substring(i, i + 70 > encoded.length ? encoded.length : i + 70));
    }

    return '-----BEGIN OPENSSH PRIVATE KEY-----\n${lines.join('\n')}\n-----END OPENSSH PRIVATE KEY-----\n';
  }

  Uint8List _encodeString(String value) {
    final bytes = utf8.encode(value);
    final buffer = BytesBuilder();
    buffer.add(_encodeUint32(bytes.length));
    buffer.add(bytes);
    return buffer.toBytes();
  }
}
