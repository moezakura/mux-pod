// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ConnectionImpl _$$ConnectionImplFromJson(Map<String, dynamic> json) =>
    _$ConnectionImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username'] as String,
      authMethod:
          AuthMethod.fromJson(json['authMethod'] as Map<String, dynamic>),
      keyId: json['keyId'] as String?,
      timeout: (json['timeout'] as num?)?.toInt() ?? 30,
      keepAliveInterval: (json['keepAliveInterval'] as num?)?.toInt() ?? 60,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
      lastConnected: json['lastConnected'] == null
          ? null
          : DateTime.parse(json['lastConnected'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$$ConnectionImplToJson(_$ConnectionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'host': instance.host,
      'port': instance.port,
      'username': instance.username,
      'authMethod': instance.authMethod,
      'keyId': instance.keyId,
      'timeout': instance.timeout,
      'keepAliveInterval': instance.keepAliveInterval,
      'icon': instance.icon,
      'color': instance.color,
      'tags': instance.tags,
      'lastConnected': instance.lastConnected?.toIso8601String(),
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
