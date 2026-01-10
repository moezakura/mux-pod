import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../models/enums.dart';

/// 鍵生成結果
class KeyGenerationResult {
  const KeyGenerationResult({
    required this.privateKeyPem,
    required this.publicKeyPem,
    required this.publicKeyOpenSSH,
    required this.fingerprint,
    required this.type,
    this.bits,
  });

  final String privateKeyPem;
  final String publicKeyPem;
  final String publicKeyOpenSSH;
  final String fingerprint;
  final KeyType type;
  final int? bits;
}

/// SSH鍵生成サービス
///
/// RSA, Ed25519, ECDSA鍵を生成する。
class KeyGenerationService {
  KeyGenerationService();

  /// RSA鍵生成
  Future<KeyGenerationResult> generateRSA({
    int bits = 4096,
    String? passphrase,
    String comment = '',
  }) async {
    final secureRandom = _getSecureRandom();

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), bits, 64),
        secureRandom,
      ));

    final pair = keyGen.generateKeyPair();
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;

    // PEM形式に変換
    final privateKeyPem = _encodeRSAPrivateKeyToPem(privateKey, publicKey, passphrase: passphrase);
    final publicKeyPem = _encodeRSAPublicKeyToPem(publicKey);
    final publicKeyOpenSSH = _encodeRSAPublicKeyToOpenSSH(publicKey, comment);

    // フィンガープリント計算
    final fingerprint = _calculateFingerprint(publicKey);

    return KeyGenerationResult(
      privateKeyPem: privateKeyPem,
      publicKeyPem: publicKeyPem,
      publicKeyOpenSSH: publicKeyOpenSSH,
      fingerprint: fingerprint,
      type: KeyType.rsa,
      bits: bits,
    );
  }

  /// Ed25519鍵生成
  Future<KeyGenerationResult> generateEd25519({
    String? passphrase,
    String comment = '',
  }) async {
    // Ed25519はpointyCastleでは直接サポートされていないため
    // 簡易的な実装を提供（実際にはdartssh2のEd25519サポートを使用）

    // 32バイトのシード生成
    final random = Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      seed[i] = random.nextInt(256);
    }

    // 仮のプレースホルダー（実際の実装ではdartssh2を使用）
    final privateKeyPem = _createEd25519PrivateKeyPem(seed, passphrase: passphrase);
    final publicKeyOpenSSH = 'ssh-ed25519 AAAA... $comment';
    final fingerprint = 'SHA256:${base64Encode(seed.sublist(0, 32))}';

    return KeyGenerationResult(
      privateKeyPem: privateKeyPem,
      publicKeyPem: '', // Ed25519ではPEM公開鍵は通常使用しない
      publicKeyOpenSSH: publicKeyOpenSSH,
      fingerprint: fingerprint,
      type: KeyType.ed25519,
    );
  }

  /// ECDSA鍵生成（P-256）
  Future<KeyGenerationResult> generateECDSA({
    String? passphrase,
    String comment = '',
  }) async {
    final secureRandom = _getSecureRandom();

    final domainParams = ECDomainParameters('secp256r1');
    final keyGen = ECKeyGenerator()
      ..init(ParametersWithRandom(
        ECKeyGeneratorParameters(domainParams),
        secureRandom,
      ));

    final pair = keyGen.generateKeyPair();
    final publicKey = pair.publicKey as ECPublicKey;
    final privateKey = pair.privateKey as ECPrivateKey;

    // PEM形式に変換
    final privateKeyPem = _encodeECPrivateKeyToPem(privateKey, passphrase: passphrase);
    final publicKeyOpenSSH = _encodeECPublicKeyToOpenSSH(publicKey, comment);
    final fingerprint = _calculateECFingerprint(publicKey);

    return KeyGenerationResult(
      privateKeyPem: privateKeyPem,
      publicKeyPem: '',
      publicKeyOpenSSH: publicKeyOpenSSH,
      fingerprint: fingerprint,
      type: KeyType.ecdsa,
    );
  }

  SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  String _encodeRSAPrivateKeyToPem(
    RSAPrivateKey privateKey,
    RSAPublicKey publicKey, {
    String? passphrase,
  }) {
    // ASN.1 DER形式でエンコード（手動実装）
    final elements = <Uint8List>[
      _encodeASN1Integer(BigInt.zero), // version
      _encodeASN1Integer(publicKey.modulus!),
      _encodeASN1Integer(publicKey.exponent!),
      _encodeASN1Integer(privateKey.privateExponent!),
      _encodeASN1Integer(privateKey.p!),
      _encodeASN1Integer(privateKey.q!),
      _encodeASN1Integer(privateKey.privateExponent! % (privateKey.p! - BigInt.one)),
      _encodeASN1Integer(privateKey.privateExponent! % (privateKey.q! - BigInt.one)),
      _encodeASN1Integer(privateKey.q!.modInverse(privateKey.p!)),
    ];

    final derBytes = _encodeASN1Sequence(elements);
    final b64 = base64Encode(derBytes);
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 64) {
      lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
    }

    return '-----BEGIN RSA PRIVATE KEY-----\n${lines.join('\n')}\n-----END RSA PRIVATE KEY-----';
  }

  String _encodeRSAPublicKeyToPem(RSAPublicKey publicKey) {
    final elements = <Uint8List>[
      _encodeASN1Integer(publicKey.modulus!),
      _encodeASN1Integer(publicKey.exponent!),
    ];

    final derBytes = _encodeASN1Sequence(elements);
    final b64 = base64Encode(derBytes);
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 64) {
      lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
    }

    return '-----BEGIN RSA PUBLIC KEY-----\n${lines.join('\n')}\n-----END RSA PUBLIC KEY-----';
  }

  /// ASN.1 INTEGER をDERエンコード
  Uint8List _encodeASN1Integer(BigInt value) {
    var bytes = _bigIntToBytes(value);
    // 先頭ビットが1の場合は0x00を追加（符号付き整数として）
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList([0, ...bytes]);
    }
    // タグ(0x02) + 長さ + 値
    return _encodeASN1Element(0x02, bytes);
  }

  /// ASN.1 SEQUENCE をDERエンコード
  Uint8List _encodeASN1Sequence(List<Uint8List> elements) {
    final content = BytesBuilder();
    for (final elem in elements) {
      content.add(elem);
    }
    // タグ(0x30) + 長さ + 値
    return _encodeASN1Element(0x30, content.toBytes());
  }

  /// ASN.1要素をDERエンコード (タグ + 長さ + 値)
  Uint8List _encodeASN1Element(int tag, Uint8List content) {
    final lengthBytes = _encodeASN1Length(content.length);
    return Uint8List.fromList([tag, ...lengthBytes, ...content]);
  }

  /// ASN.1長さをDERエンコード
  Uint8List _encodeASN1Length(int length) {
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

  String _encodeRSAPublicKeyToOpenSSH(RSAPublicKey publicKey, String comment) {
    // OpenSSH形式: ssh-rsa base64(type_len + type + e_len + e + n_len + n) comment
    final buffer = BytesBuilder();

    // type
    final typeBytes = utf8.encode('ssh-rsa');
    buffer.add(_encodeLength(typeBytes.length));
    buffer.add(typeBytes);

    // e (exponent)
    final eBytes = _encodeMPInt(publicKey.exponent!);
    buffer.add(eBytes);

    // n (modulus)
    final nBytes = _encodeMPInt(publicKey.modulus!);
    buffer.add(nBytes);

    final b64 = base64Encode(buffer.toBytes());
    return 'ssh-rsa $b64 $comment'.trim();
  }

  Uint8List _encodeLength(int length) {
    final buffer = ByteData(4);
    buffer.setUint32(0, length, Endian.big);
    return buffer.buffer.asUint8List();
  }

  Uint8List _encodeMPInt(BigInt value) {
    var bytes = _bigIntToBytes(value);
    // 先頭ビットが1の場合は0x00を追加（符号付き整数として）
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList([0, ...bytes]);
    }
    return Uint8List.fromList([..._encodeLength(bytes.length), ...bytes]);
  }

  Uint8List _bigIntToBytes(BigInt value) {
    final hex = value.toRadixString(16);
    final paddedHex = hex.length.isOdd ? '0$hex' : hex;
    final bytes = <int>[];
    for (var i = 0; i < paddedHex.length; i += 2) {
      bytes.add(int.parse(paddedHex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  String _calculateFingerprint(RSAPublicKey publicKey) {
    // SHA-256フィンガープリント
    final buffer = BytesBuilder();

    final typeBytes = utf8.encode('ssh-rsa');
    buffer.add(_encodeLength(typeBytes.length));
    buffer.add(typeBytes);

    final eBytes = _encodeMPInt(publicKey.exponent!);
    buffer.add(eBytes);

    final nBytes = _encodeMPInt(publicKey.modulus!);
    buffer.add(nBytes);

    final digest = SHA256Digest();
    final hash = digest.process(buffer.toBytes());
    return 'SHA256:${base64Encode(hash).replaceAll('=', '')}';
  }

  String _createEd25519PrivateKeyPem(Uint8List seed, {String? passphrase}) {
    // OpenSSH形式のEd25519秘密鍵（簡易版）
    final b64 = base64Encode(seed);
    return '-----BEGIN OPENSSH PRIVATE KEY-----\n$b64\n-----END OPENSSH PRIVATE KEY-----';
  }

  String _encodeECPrivateKeyToPem(ECPrivateKey privateKey, {String? passphrase}) {
    final d = _bigIntToBytes(privateKey.d!);
    final b64 = base64Encode(d);
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 64) {
      lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
    }
    return '-----BEGIN EC PRIVATE KEY-----\n${lines.join('\n')}\n-----END EC PRIVATE KEY-----';
  }

  String _encodeECPublicKeyToOpenSSH(ECPublicKey publicKey, String comment) {
    // 簡易版
    final x = _bigIntToBytes(publicKey.Q!.x!.toBigInteger()!);
    final y = _bigIntToBytes(publicKey.Q!.y!.toBigInteger()!);
    final b64 = base64Encode([...x, ...y]);
    return 'ecdsa-sha2-nistp256 $b64 $comment'.trim();
  }

  String _calculateECFingerprint(ECPublicKey publicKey) {
    final x = _bigIntToBytes(publicKey.Q!.x!.toBigInteger()!);
    final y = _bigIntToBytes(publicKey.Q!.y!.toBigInteger()!);
    final digest = SHA256Digest();
    final hash = digest.process(Uint8List.fromList([...x, ...y]));
    return 'SHA256:${base64Encode(hash).replaceAll('=', '')}';
  }
}
