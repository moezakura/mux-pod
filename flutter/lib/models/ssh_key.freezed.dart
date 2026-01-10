// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ssh_key.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

SSHKey _$SSHKeyFromJson(Map<String, dynamic> json) {
  return _SSHKey.fromJson(json);
}

/// @nodoc
mixin _$SSHKey {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  KeyType get type => throw _privateConstructorUsedError;
  int? get bits => throw _privateConstructorUsedError;
  String get fingerprint => throw _privateConstructorUsedError;
  String get publicKey => throw _privateConstructorUsedError;
  bool get encrypted => throw _privateConstructorUsedError;
  bool get isDefault => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  DateTime? get lastUsed => throw _privateConstructorUsedError;

  /// Serializes this SSHKey to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SSHKey
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SSHKeyCopyWith<SSHKey> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SSHKeyCopyWith<$Res> {
  factory $SSHKeyCopyWith(SSHKey value, $Res Function(SSHKey) then) =
      _$SSHKeyCopyWithImpl<$Res, SSHKey>;
  @useResult
  $Res call(
      {String id,
      String name,
      KeyType type,
      int? bits,
      String fingerprint,
      String publicKey,
      bool encrypted,
      bool isDefault,
      DateTime createdAt,
      DateTime? lastUsed});
}

/// @nodoc
class _$SSHKeyCopyWithImpl<$Res, $Val extends SSHKey>
    implements $SSHKeyCopyWith<$Res> {
  _$SSHKeyCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SSHKey
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? type = null,
    Object? bits = freezed,
    Object? fingerprint = null,
    Object? publicKey = null,
    Object? encrypted = null,
    Object? isDefault = null,
    Object? createdAt = null,
    Object? lastUsed = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as KeyType,
      bits: freezed == bits
          ? _value.bits
          : bits // ignore: cast_nullable_to_non_nullable
              as int?,
      fingerprint: null == fingerprint
          ? _value.fingerprint
          : fingerprint // ignore: cast_nullable_to_non_nullable
              as String,
      publicKey: null == publicKey
          ? _value.publicKey
          : publicKey // ignore: cast_nullable_to_non_nullable
              as String,
      encrypted: null == encrypted
          ? _value.encrypted
          : encrypted // ignore: cast_nullable_to_non_nullable
              as bool,
      isDefault: null == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      lastUsed: freezed == lastUsed
          ? _value.lastUsed
          : lastUsed // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SSHKeyImplCopyWith<$Res> implements $SSHKeyCopyWith<$Res> {
  factory _$$SSHKeyImplCopyWith(
          _$SSHKeyImpl value, $Res Function(_$SSHKeyImpl) then) =
      __$$SSHKeyImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      KeyType type,
      int? bits,
      String fingerprint,
      String publicKey,
      bool encrypted,
      bool isDefault,
      DateTime createdAt,
      DateTime? lastUsed});
}

/// @nodoc
class __$$SSHKeyImplCopyWithImpl<$Res>
    extends _$SSHKeyCopyWithImpl<$Res, _$SSHKeyImpl>
    implements _$$SSHKeyImplCopyWith<$Res> {
  __$$SSHKeyImplCopyWithImpl(
      _$SSHKeyImpl _value, $Res Function(_$SSHKeyImpl) _then)
      : super(_value, _then);

  /// Create a copy of SSHKey
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? type = null,
    Object? bits = freezed,
    Object? fingerprint = null,
    Object? publicKey = null,
    Object? encrypted = null,
    Object? isDefault = null,
    Object? createdAt = null,
    Object? lastUsed = freezed,
  }) {
    return _then(_$SSHKeyImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as KeyType,
      bits: freezed == bits
          ? _value.bits
          : bits // ignore: cast_nullable_to_non_nullable
              as int?,
      fingerprint: null == fingerprint
          ? _value.fingerprint
          : fingerprint // ignore: cast_nullable_to_non_nullable
              as String,
      publicKey: null == publicKey
          ? _value.publicKey
          : publicKey // ignore: cast_nullable_to_non_nullable
              as String,
      encrypted: null == encrypted
          ? _value.encrypted
          : encrypted // ignore: cast_nullable_to_non_nullable
              as bool,
      isDefault: null == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      lastUsed: freezed == lastUsed
          ? _value.lastUsed
          : lastUsed // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SSHKeyImpl implements _SSHKey {
  const _$SSHKeyImpl(
      {required this.id,
      required this.name,
      required this.type,
      this.bits,
      required this.fingerprint,
      required this.publicKey,
      this.encrypted = false,
      this.isDefault = false,
      required this.createdAt,
      this.lastUsed});

  factory _$SSHKeyImpl.fromJson(Map<String, dynamic> json) =>
      _$$SSHKeyImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final KeyType type;
  @override
  final int? bits;
  @override
  final String fingerprint;
  @override
  final String publicKey;
  @override
  @JsonKey()
  final bool encrypted;
  @override
  @JsonKey()
  final bool isDefault;
  @override
  final DateTime createdAt;
  @override
  final DateTime? lastUsed;

  @override
  String toString() {
    return 'SSHKey(id: $id, name: $name, type: $type, bits: $bits, fingerprint: $fingerprint, publicKey: $publicKey, encrypted: $encrypted, isDefault: $isDefault, createdAt: $createdAt, lastUsed: $lastUsed)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SSHKeyImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.bits, bits) || other.bits == bits) &&
            (identical(other.fingerprint, fingerprint) ||
                other.fingerprint == fingerprint) &&
            (identical(other.publicKey, publicKey) ||
                other.publicKey == publicKey) &&
            (identical(other.encrypted, encrypted) ||
                other.encrypted == encrypted) &&
            (identical(other.isDefault, isDefault) ||
                other.isDefault == isDefault) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.lastUsed, lastUsed) ||
                other.lastUsed == lastUsed));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, type, bits,
      fingerprint, publicKey, encrypted, isDefault, createdAt, lastUsed);

  /// Create a copy of SSHKey
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SSHKeyImplCopyWith<_$SSHKeyImpl> get copyWith =>
      __$$SSHKeyImplCopyWithImpl<_$SSHKeyImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SSHKeyImplToJson(
      this,
    );
  }
}

abstract class _SSHKey implements SSHKey {
  const factory _SSHKey(
      {required final String id,
      required final String name,
      required final KeyType type,
      final int? bits,
      required final String fingerprint,
      required final String publicKey,
      final bool encrypted,
      final bool isDefault,
      required final DateTime createdAt,
      final DateTime? lastUsed}) = _$SSHKeyImpl;

  factory _SSHKey.fromJson(Map<String, dynamic> json) = _$SSHKeyImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  KeyType get type;
  @override
  int? get bits;
  @override
  String get fingerprint;
  @override
  String get publicKey;
  @override
  bool get encrypted;
  @override
  bool get isDefault;
  @override
  DateTime get createdAt;
  @override
  DateTime? get lastUsed;

  /// Create a copy of SSHKey
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SSHKeyImplCopyWith<_$SSHKeyImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
