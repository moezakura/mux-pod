import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/keychain/ssh_key_service.dart';

void main() {
  late SshKeyService service;

  setUp(() {
    service = SshKeyService();
  });

  group('Ed25519 Key Generation (T013)', () {
    test('generates valid Ed25519 key pair', () async {
      final keyPair = await service.generateEd25519();

      expect(keyPair.type, equals('ed25519'));
      expect(keyPair.privateKeyBytes.length, equals(32));
      expect(keyPair.publicKeyBytes.length, equals(32));
      expect(keyPair.fingerprint, startsWith('SHA256:'));
      expect(keyPair.privatePem, contains('-----BEGIN OPENSSH PRIVATE KEY-----'));
      expect(keyPair.privatePem, contains('-----END OPENSSH PRIVATE KEY-----'));
      expect(keyPair.publicKeyString, startsWith('ssh-ed25519 '));
    });

    test('generates Ed25519 key pair with comment', () async {
      const comment = 'test@example.com';
      final keyPair = await service.generateEd25519(comment: comment);

      expect(keyPair.publicKeyString, contains(comment));
    });

    test('generates unique keys each time', () async {
      final keyPair1 = await service.generateEd25519();
      final keyPair2 = await service.generateEd25519();

      expect(keyPair1.fingerprint, isNot(equals(keyPair2.fingerprint)));
      expect(keyPair1.privateKeyBytes, isNot(equals(keyPair2.privateKeyBytes)));
    });
  });

  group('RSA Key Generation (T014)', () {
    test('generates valid RSA-2048 key pair', () async {
      final keyPair = await service.generateRsa(bits: 2048);

      expect(keyPair.type, equals('rsa-2048'));
      expect(keyPair.fingerprint, startsWith('SHA256:'));
      expect(keyPair.privatePem, contains('-----BEGIN RSA PRIVATE KEY-----'));
      expect(keyPair.privatePem, contains('-----END RSA PRIVATE KEY-----'));
      expect(keyPair.publicKeyString, startsWith('ssh-rsa '));
    });

    test('generates valid RSA-3072 key pair', () async {
      final keyPair = await service.generateRsa(bits: 3072);

      expect(keyPair.type, equals('rsa-3072'));
      expect(keyPair.fingerprint, startsWith('SHA256:'));
    });

    test('generates valid RSA-4096 key pair', () async {
      final keyPair = await service.generateRsa(bits: 4096);

      expect(keyPair.type, equals('rsa-4096'));
      expect(keyPair.fingerprint, startsWith('SHA256:'));
    });

    test('generates RSA key pair with comment', () async {
      const comment = 'test@example.com';
      final keyPair = await service.generateRsa(bits: 2048, comment: comment);

      expect(keyPair.publicKeyString, contains(comment));
    });

    test('generates unique RSA keys each time', () async {
      final keyPair1 = await service.generateRsa(bits: 2048);
      final keyPair2 = await service.generateRsa(bits: 2048);

      expect(keyPair1.fingerprint, isNot(equals(keyPair2.fingerprint)));
    });
  });

  group('PEM Format Conversion (T015)', () {
    test('Ed25519 PEM is parseable by dartssh2', () async {
      final keyPair = await service.generateEd25519();

      // PEMが正しい形式であることを確認
      expect(keyPair.privatePem, contains('-----BEGIN OPENSSH PRIVATE KEY-----'));
      expect(keyPair.privatePem, contains('-----END OPENSSH PRIVATE KEY-----'));

      // dartssh2で再パース可能か確認
      final parsed = await service.parseFromPem(keyPair.privatePem);
      expect(parsed.type, equals('ed25519'));
      expect(parsed.fingerprint, equals(keyPair.fingerprint));
    });

    test('RSA PEM is in PKCS#1 format', () async {
      final keyPair = await service.generateRsa(bits: 2048);

      expect(keyPair.privatePem, contains('-----BEGIN RSA PRIVATE KEY-----'));
      expect(keyPair.privatePem, contains('-----END RSA PRIVATE KEY-----'));

      // dartssh2で再パース可能か確認
      final parsed = await service.parseFromPem(keyPair.privatePem);
      expect(parsed.fingerprint, equals(keyPair.fingerprint));
    });

    test('authorized_keys format is correct for Ed25519', () async {
      final keyPair = await service.generateEd25519(comment: 'test');

      final parts = keyPair.publicKeyString.split(' ');
      expect(parts.length, equals(3));
      expect(parts[0], equals('ssh-ed25519'));
      expect(parts[2], equals('test'));
    });

    test('authorized_keys format is correct for RSA', () async {
      final keyPair = await service.generateRsa(bits: 2048, comment: 'test');

      final parts = keyPair.publicKeyString.split(' ');
      expect(parts.length, equals(3));
      expect(parts[0], equals('ssh-rsa'));
      expect(parts[2], equals('test'));
    });
  });

  group('Fingerprint Calculation', () {
    test('fingerprint format is SHA256:base64', () async {
      final keyPair = await service.generateEd25519();

      expect(keyPair.fingerprint, startsWith('SHA256:'));
      // Base64文字列（=なし）
      final base64Part = keyPair.fingerprint.substring(7);
      expect(base64Part, isNot(contains('=')));
      expect(base64Part.length, greaterThan(0));
    });

    test('same key produces same fingerprint', () async {
      final keyPair = await service.generateEd25519();
      final fingerprint1 = service.calculateFingerprint(
        'ssh-ed25519',
        keyPair.publicKeyBytes,
      );
      final fingerprint2 = service.calculateFingerprint(
        'ssh-ed25519',
        keyPair.publicKeyBytes,
      );

      expect(fingerprint1, equals(fingerprint2));
    });
  });

  group('isEncrypted Detection', () {
    test('detects unencrypted key', () async {
      final keyPair = await service.generateEd25519();
      final isEncrypted = service.isEncrypted(keyPair.privatePem);

      expect(isEncrypted, isFalse);
    });
  });

  // User Story 2 Tests (T026-T028)
  group('PEM Parsing (T026)', () {
    test('parses valid Ed25519 PEM', () async {
      // 生成した鍵のPEMをパースできることを確認
      final original = await service.generateEd25519(comment: 'test');
      final parsed = await service.parseFromPem(original.privatePem);

      expect(parsed.type, equals('ed25519'));
      expect(parsed.fingerprint, equals(original.fingerprint));
      expect(parsed.publicKeyString, contains('ssh-ed25519'));
    });

    test('parses valid RSA PEM', () async {
      final original = await service.generateRsa(bits: 2048, comment: 'test');
      final parsed = await service.parseFromPem(original.privatePem);

      expect(parsed.fingerprint, equals(original.fingerprint));
      // dartssh2はRSA鍵を'rsa-sha2-256'として報告することがある
      expect(parsed.publicKeyString, anyOf(
        contains('ssh-rsa'),
        contains('rsa-sha2-256'),
        contains('rsa-sha2-512'),
      ));
    });

    test('returns correct key type for Ed25519', () async {
      final original = await service.generateEd25519();
      final parsed = await service.parseFromPem(original.privatePem);

      expect(parsed.type, equals('ed25519'));
    });
  });

  group('Passphrase-encrypted Key Parsing (T027)', () {
    test('detects unencrypted Ed25519 PEM', () async {
      final keyPair = await service.generateEd25519();
      final isEncrypted = service.isEncrypted(keyPair.privatePem);

      expect(isEncrypted, isFalse);
    });

    test('detects unencrypted RSA PEM', () async {
      final keyPair = await service.generateRsa(bits: 2048);
      final isEncrypted = service.isEncrypted(keyPair.privatePem);

      expect(isEncrypted, isFalse);
    });
  });

  group('Invalid PEM Rejection (T028)', () {
    test('throws FormatException for invalid PEM', () {
      const invalidPem = '''-----BEGIN OPENSSH PRIVATE KEY-----
invalid content here
-----END OPENSSH PRIVATE KEY-----''';

      expect(
        () => service.parseFromPem(invalidPem),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for empty string', () {
      expect(
        () => service.parseFromPem(''),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for non-PEM text', () {
      expect(
        () => service.parseFromPem('just some random text'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for truncated PEM', () {
      const truncatedPem = '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG''';

      expect(
        () => service.parseFromPem(truncatedPem),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
