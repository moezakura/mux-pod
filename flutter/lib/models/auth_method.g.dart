// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_method.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PasswordAuthImpl _$$PasswordAuthImplFromJson(Map<String, dynamic> json) =>
    _$PasswordAuthImpl(
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$PasswordAuthImplToJson(_$PasswordAuthImpl instance) =>
    <String, dynamic>{
      'runtimeType': instance.$type,
    };

_$KeyAuthImpl _$$KeyAuthImplFromJson(Map<String, dynamic> json) =>
    _$KeyAuthImpl(
      keyId: json['keyId'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$KeyAuthImplToJson(_$KeyAuthImpl instance) =>
    <String, dynamic>{
      'keyId': instance.keyId,
      'runtimeType': instance.$type,
    };
