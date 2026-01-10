import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'ssh_key.freezed.dart';
part 'ssh_key.g.dart';

/// SSH鍵ペア
@freezed
class SSHKey with _$SSHKey {
  const factory SSHKey({
    required String id,
    required String name,
    required KeyType type,
    int? bits,
    required String fingerprint,
    required String publicKey,
    @Default(false) bool encrypted,
    @Default(false) bool isDefault,
    required DateTime createdAt,
    DateTime? lastUsed,
  }) = _SSHKey;

  factory SSHKey.fromJson(Map<String, dynamic> json) =>
      _$SSHKeyFromJson(json);
}

/// SSH鍵バリデーション拡張
extension SSHKeyValidation on SSHKey {
  /// バリデーション実行
  List<String> validate() {
    final errors = <String>[];

    if (name.isEmpty || name.length > 50) {
      errors.add('Name must be 1-50 characters');
    }

    if (type == KeyType.rsa && bits != null) {
      if (![2048, 3072, 4096].contains(bits)) {
        errors.add('RSA bits must be 2048, 3072, or 4096');
      }
    }

    if (!fingerprint.startsWith('SHA256:')) {
      errors.add('Fingerprint must be SHA256 format');
    }

    return errors;
  }

  /// バリデーションが通るか
  bool get isValid => validate().isEmpty;
}
