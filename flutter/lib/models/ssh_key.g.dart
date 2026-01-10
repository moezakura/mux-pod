// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ssh_key.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SSHKeyImpl _$$SSHKeyImplFromJson(Map<String, dynamic> json) => _$SSHKeyImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      type: $enumDecode(_$KeyTypeEnumMap, json['type']),
      bits: (json['bits'] as num?)?.toInt(),
      fingerprint: json['fingerprint'] as String,
      publicKey: json['publicKey'] as String,
      encrypted: json['encrypted'] as bool? ?? false,
      isDefault: json['isDefault'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsed: json['lastUsed'] == null
          ? null
          : DateTime.parse(json['lastUsed'] as String),
    );

Map<String, dynamic> _$$SSHKeyImplToJson(_$SSHKeyImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'type': _$KeyTypeEnumMap[instance.type]!,
      'bits': instance.bits,
      'fingerprint': instance.fingerprint,
      'publicKey': instance.publicKey,
      'encrypted': instance.encrypted,
      'isDefault': instance.isDefault,
      'createdAt': instance.createdAt.toIso8601String(),
      'lastUsed': instance.lastUsed?.toIso8601String(),
    };

const _$KeyTypeEnumMap = {
  KeyType.rsa: 'rsa',
  KeyType.ed25519: 'ed25519',
  KeyType.ecdsa: 'ecdsa',
};
