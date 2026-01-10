import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_method.freezed.dart';
part 'auth_method.g.dart';

/// SSH認証方法
@freezed
sealed class AuthMethod with _$AuthMethod {
  /// パスワード認証
  const factory AuthMethod.password() = PasswordAuth;

  /// 鍵認証
  const factory AuthMethod.key({
    required String keyId,
  }) = KeyAuth;

  factory AuthMethod.fromJson(Map<String, dynamic> json) =>
      _$AuthMethodFromJson(json);
}
