// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'auth_method.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AuthMethod _$AuthMethodFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'password':
      return PasswordAuth.fromJson(json);
    case 'key':
      return KeyAuth.fromJson(json);

    default:
      throw CheckedFromJsonException(json, 'runtimeType', 'AuthMethod',
          'Invalid union type "${json['runtimeType']}"!');
  }
}

/// @nodoc
mixin _$AuthMethod {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() password,
    required TResult Function(String keyId) key,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? password,
    TResult? Function(String keyId)? key,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? password,
    TResult Function(String keyId)? key,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PasswordAuth value) password,
    required TResult Function(KeyAuth value) key,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PasswordAuth value)? password,
    TResult? Function(KeyAuth value)? key,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PasswordAuth value)? password,
    TResult Function(KeyAuth value)? key,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;

  /// Serializes this AuthMethod to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AuthMethodCopyWith<$Res> {
  factory $AuthMethodCopyWith(
          AuthMethod value, $Res Function(AuthMethod) then) =
      _$AuthMethodCopyWithImpl<$Res, AuthMethod>;
}

/// @nodoc
class _$AuthMethodCopyWithImpl<$Res, $Val extends AuthMethod>
    implements $AuthMethodCopyWith<$Res> {
  _$AuthMethodCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AuthMethod
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$PasswordAuthImplCopyWith<$Res> {
  factory _$$PasswordAuthImplCopyWith(
          _$PasswordAuthImpl value, $Res Function(_$PasswordAuthImpl) then) =
      __$$PasswordAuthImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PasswordAuthImplCopyWithImpl<$Res>
    extends _$AuthMethodCopyWithImpl<$Res, _$PasswordAuthImpl>
    implements _$$PasswordAuthImplCopyWith<$Res> {
  __$$PasswordAuthImplCopyWithImpl(
      _$PasswordAuthImpl _value, $Res Function(_$PasswordAuthImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthMethod
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
@JsonSerializable()
class _$PasswordAuthImpl implements PasswordAuth {
  const _$PasswordAuthImpl({final String? $type}) : $type = $type ?? 'password';

  factory _$PasswordAuthImpl.fromJson(Map<String, dynamic> json) =>
      _$$PasswordAuthImplFromJson(json);

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'AuthMethod.password()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$PasswordAuthImpl);
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() password,
    required TResult Function(String keyId) key,
  }) {
    return password();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? password,
    TResult? Function(String keyId)? key,
  }) {
    return password?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? password,
    TResult Function(String keyId)? key,
    required TResult orElse(),
  }) {
    if (password != null) {
      return password();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PasswordAuth value) password,
    required TResult Function(KeyAuth value) key,
  }) {
    return password(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PasswordAuth value)? password,
    TResult? Function(KeyAuth value)? key,
  }) {
    return password?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PasswordAuth value)? password,
    TResult Function(KeyAuth value)? key,
    required TResult orElse(),
  }) {
    if (password != null) {
      return password(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$PasswordAuthImplToJson(
      this,
    );
  }
}

abstract class PasswordAuth implements AuthMethod {
  const factory PasswordAuth() = _$PasswordAuthImpl;

  factory PasswordAuth.fromJson(Map<String, dynamic> json) =
      _$PasswordAuthImpl.fromJson;
}

/// @nodoc
abstract class _$$KeyAuthImplCopyWith<$Res> {
  factory _$$KeyAuthImplCopyWith(
          _$KeyAuthImpl value, $Res Function(_$KeyAuthImpl) then) =
      __$$KeyAuthImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String keyId});
}

/// @nodoc
class __$$KeyAuthImplCopyWithImpl<$Res>
    extends _$AuthMethodCopyWithImpl<$Res, _$KeyAuthImpl>
    implements _$$KeyAuthImplCopyWith<$Res> {
  __$$KeyAuthImplCopyWithImpl(
      _$KeyAuthImpl _value, $Res Function(_$KeyAuthImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthMethod
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? keyId = null,
  }) {
    return _then(_$KeyAuthImpl(
      keyId: null == keyId
          ? _value.keyId
          : keyId // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$KeyAuthImpl implements KeyAuth {
  const _$KeyAuthImpl({required this.keyId, final String? $type})
      : $type = $type ?? 'key';

  factory _$KeyAuthImpl.fromJson(Map<String, dynamic> json) =>
      _$$KeyAuthImplFromJson(json);

  @override
  final String keyId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'AuthMethod.key(keyId: $keyId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$KeyAuthImpl &&
            (identical(other.keyId, keyId) || other.keyId == keyId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, keyId);

  /// Create a copy of AuthMethod
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$KeyAuthImplCopyWith<_$KeyAuthImpl> get copyWith =>
      __$$KeyAuthImplCopyWithImpl<_$KeyAuthImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() password,
    required TResult Function(String keyId) key,
  }) {
    return key(keyId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? password,
    TResult? Function(String keyId)? key,
  }) {
    return key?.call(keyId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? password,
    TResult Function(String keyId)? key,
    required TResult orElse(),
  }) {
    if (key != null) {
      return key(keyId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PasswordAuth value) password,
    required TResult Function(KeyAuth value) key,
  }) {
    return key(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PasswordAuth value)? password,
    TResult? Function(KeyAuth value)? key,
  }) {
    return key?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PasswordAuth value)? password,
    TResult Function(KeyAuth value)? key,
    required TResult orElse(),
  }) {
    if (key != null) {
      return key(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$KeyAuthImplToJson(
      this,
    );
  }
}

abstract class KeyAuth implements AuthMethod {
  const factory KeyAuth({required final String keyId}) = _$KeyAuthImpl;

  factory KeyAuth.fromJson(Map<String, dynamic> json) = _$KeyAuthImpl.fromJson;

  String get keyId;

  /// Create a copy of AuthMethod
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$KeyAuthImplCopyWith<_$KeyAuthImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
