import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:dartssh2/dartssh2.dart';
import 'package:pointycastle/export.dart' as pc;

/// SSH鍵ペアのデータクラス
class SshKeyPair {
  final String type; // 'ed25519' | 'rsa-2048' | 'rsa-3072' | 'rsa-4096'
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

/// SSH鍵サービス
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

  /// RSA鍵ペアを生成
  Future<SshKeyPair> generateRsa({
    required int bits,
    String? comment,
  }) async {
    assert(bits == 2048 || bits == 3072 || bits == 4096);

    final secureRandom = pc.FortunaRandom();
    final seedSource = List<int>.generate(32, (i) => DateTime.now().millisecondsSinceEpoch % 256);
    secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seedSource)));

    final keyGen = pc.RSAKeyGenerator()
      ..init(pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), bits, 64),
        secureRandom,
      ));

    final pair = keyGen.generateKeyPair();
    final publicKey = pair.publicKey as pc.RSAPublicKey;
    final privateKey = pair.privateKey as pc.RSAPrivateKey;

    final publicKeyBlob = _buildRsaPublicKeyBlob(publicKey);
    final fingerprint = calculateFingerprint('ssh-rsa', publicKeyBlob);
    final privatePem = _buildRsaPem(privateKey, publicKey, comment ?? '');
    final publicKeyString =
        toAuthorizedKeys('ssh-rsa', publicKeyBlob, comment ?? '');

    return SshKeyPair(
      type: 'rsa-$bits',
      privateKeyBytes: _rsaPrivateKeyToBytes(privateKey),
      publicKeyBytes: publicKeyBlob,
      fingerprint: fingerprint,
      privatePem: privatePem,
      publicKeyString: publicKeyString,
    );
  }

  /// PEM文字列から鍵をパース
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

    // 公開鍵のBlobを取得（dartssh2のencodeは完全なSSH公開鍵Blobを返す）
    final publicKeyBlob = keyPair.toPublicKey().encode();
    // Blobから直接フィンガープリントを計算（再ラップしない）
    final fingerprint = calculateFingerprintFromBlob(publicKeyBlob);

    String keyType;
    if (type == 'ssh-ed25519') {
      keyType = 'ed25519';
    } else if (type == 'ssh-rsa') {
      // RSAのビット数は公開鍵から推測
      keyType = 'rsa-4096'; // デフォルト
    } else {
      keyType = type;
    }

    return SshKeyPair(
      type: keyType,
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
    } else if (keyType == 'ssh-rsa') {
      // RSAの場合、publicKeyBytesは既にBlobフォーマット
      return publicKeyBytes;
    }
    return publicKeyBytes;
  }

  Uint8List _buildRsaPublicKeyBlob(pc.RSAPublicKey publicKey) {
    final buffer = BytesBuilder();
    final typeBytes = utf8.encode('ssh-rsa');
    buffer.add(_encodeUint32(typeBytes.length));
    buffer.add(typeBytes);

    // e (public exponent)
    final eBytes = _encodeMpInt(publicKey.publicExponent!);
    buffer.add(eBytes);

    // n (modulus)
    final nBytes = _encodeMpInt(publicKey.modulus!);
    buffer.add(nBytes);

    return buffer.toBytes();
  }

  Uint8List _encodeMpInt(BigInt value) {
    var bytes = _bigIntToBytes(value);
    // 先頭ビットが1の場合、0x00を追加
    if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
      bytes = Uint8List.fromList([0, ...bytes]);
    }
    final buffer = BytesBuilder();
    buffer.add(_encodeUint32(bytes.length));
    buffer.add(bytes);
    return buffer.toBytes();
  }

  Uint8List _bigIntToBytes(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List _encodeUint32(int value) {
    return Uint8List.fromList([
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }

  Uint8List _rsaPrivateKeyToBytes(pc.RSAPrivateKey privateKey) {
    // 簡略化のため、modulusのバイト表現を返す
    return _bigIntToBytes(privateKey.modulus!);
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

  String _buildRsaPem(
      pc.RSAPrivateKey privateKey, pc.RSAPublicKey publicKey, String comment) {
    // RSA秘密鍵をPKCS#1形式で出力 (ASN.1 DER手動エンコード)
    final derBytes = _encodeRsaPrivateKeyDer(privateKey, publicKey);

    final encoded = base64Encode(derBytes);
    final lines = <String>[];
    for (var i = 0; i < encoded.length; i += 64) {
      lines.add(encoded.substring(i, i + 64 > encoded.length ? encoded.length : i + 64));
    }

    return '-----BEGIN RSA PRIVATE KEY-----\n${lines.join('\n')}\n-----END RSA PRIVATE KEY-----\n';
  }

  Uint8List _encodeRsaPrivateKeyDer(
      pc.RSAPrivateKey privateKey, pc.RSAPublicKey publicKey) {
    // PKCS#1 RSAPrivateKey structure:
    // RSAPrivateKey ::= SEQUENCE {
    //   version           Version,
    //   modulus           INTEGER,  -- n
    //   publicExponent    INTEGER,  -- e
    //   privateExponent   INTEGER,  -- d
    //   prime1            INTEGER,  -- p
    //   prime2            INTEGER,  -- q
    //   exponent1         INTEGER,  -- d mod (p-1)
    //   exponent2         INTEGER,  -- d mod (q-1)
    //   coefficient       INTEGER,  -- (inverse of q) mod p
    // }
    final integers = [
      BigInt.zero, // version
      privateKey.modulus!,
      publicKey.publicExponent!,
      privateKey.privateExponent!,
      privateKey.p!,
      privateKey.q!,
      privateKey.privateExponent! % (privateKey.p! - BigInt.one),
      privateKey.privateExponent! % (privateKey.q! - BigInt.one),
      privateKey.q!.modInverse(privateKey.p!),
    ];

    final encodedIntegers = integers.map(_encodeAsn1Integer).toList();
    final contentLength = encodedIntegers.fold<int>(0, (sum, e) => sum + e.length);

    final buffer = BytesBuilder();
    // SEQUENCE tag
    buffer.addByte(0x30);
    // Length
    buffer.add(_encodeAsn1Length(contentLength));
    // Contents
    for (final encoded in encodedIntegers) {
      buffer.add(encoded);
    }

    return buffer.toBytes();
  }

  Uint8List _encodeAsn1Integer(BigInt value) {
    final buffer = BytesBuilder();
    // INTEGER tag
    buffer.addByte(0x02);

    var bytes = _bigIntToBytes(value);
    // 先頭ビットが1の場合、符号ビット用に0x00を追加
    if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
      bytes = Uint8List.fromList([0, ...bytes]);
    }
    // 0の場合は1バイトの0
    if (bytes.isEmpty) {
      bytes = Uint8List.fromList([0]);
    }

    buffer.add(_encodeAsn1Length(bytes.length));
    buffer.add(bytes);

    return buffer.toBytes();
  }

  Uint8List _encodeAsn1Length(int length) {
    if (length < 128) {
      return Uint8List.fromList([length]);
    } else if (length < 256) {
      return Uint8List.fromList([0x81, length]);
    } else if (length < 65536) {
      return Uint8List.fromList([0x82, (length >> 8) & 0xff, length & 0xff]);
    } else {
      return Uint8List.fromList([
        0x83,
        (length >> 16) & 0xff,
        (length >> 8) & 0xff,
        length & 0xff,
      ]);
    }
  }

  Uint8List _encodeString(String value) {
    final bytes = utf8.encode(value);
    final buffer = BytesBuilder();
    buffer.add(_encodeUint32(bytes.length));
    buffer.add(bytes);
    return buffer.toBytes();
  }
}
