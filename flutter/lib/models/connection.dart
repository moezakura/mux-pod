import 'package:freezed_annotation/freezed_annotation.dart';

import 'auth_method.dart';

part 'connection.freezed.dart';
part 'connection.g.dart';

/// SSH接続設定
@freezed
class Connection with _$Connection {
  const factory Connection({
    required String id,
    required String name,
    required String host,
    @Default(22) int port,
    required String username,
    required AuthMethod authMethod,
    String? keyId,
    @Default(30) int timeout,
    @Default(60) int keepAliveInterval,
    String? icon,
    String? color,
    @Default([]) List<String> tags,
    DateTime? lastConnected,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Connection;

  factory Connection.fromJson(Map<String, dynamic> json) =>
      _$ConnectionFromJson(json);
}

/// 接続設定のバリデーション拡張
extension ConnectionValidation on Connection {
  /// バリデーション実行
  List<String> validate() {
    final errors = <String>[];

    if (name.isEmpty || name.length > 50) {
      errors.add('Name must be 1-50 characters');
    }

    if (host.isEmpty) {
      errors.add('Host is required');
    }

    if (port < 1 || port > 65535) {
      errors.add('Port must be 1-65535');
    }

    if (username.isEmpty || username.length > 32) {
      errors.add('Username must be 1-32 characters');
    }

    if (timeout < 5 || timeout > 120) {
      errors.add('Timeout must be 5-120 seconds');
    }

    if (keepAliveInterval != 0 &&
        (keepAliveInterval < 10 || keepAliveInterval > 300)) {
      errors.add('Keep-alive interval must be 0 (off) or 10-300 seconds');
    }

    return errors;
  }

  /// バリデーションが通るか
  bool get isValid => validate().isEmpty;
}
