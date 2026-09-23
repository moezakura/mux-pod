import 'package:flutter/widgets.dart';

import '../../services/backend/backend_type.dart';
import '../../services/backend/multiplexer_config.dart';

/// フォーム入力値の不変集約。
///
/// 接続テスト・保存の両方で同じ読み取り規則（トリム等）を使用するため、
/// コントローラから収集する処理をここに集約する。Riverpod には依存しない。
class ConnectionFormValues {
  const ConnectionFormValues({
    required this.name,
    required this.host,
    required this.portText,
    required this.username,
    required this.password,
    required this.multiplexerPath,
    required this.deepLinkId,
    required this.authMethod,
    this.keyId,
    required this.backend,
  });

  final String name;
  final String host;

  /// ポート番号の入力文字列（バリデーション後にパース）。
  final String portText;
  final String username;
  final String password;
  final String multiplexerPath;
  final String deepLinkId;
  final String authMethod; // 'password' | 'key'
  final String? keyId;
  final BackendType backend;

  /// ポート番号（未入力・不正時は 22）。
  int get port => int.tryParse(portText) ?? 22;

  /// トリム後の multiplexer パス（空なら null）。
  String? get executablePath {
    final path = multiplexerPath.trim();
    return path.isEmpty ? null : path;
  }

  /// トリム後の deep link ID（空なら null）。
  String? get deepLinkIdOrNull {
    final id = deepLinkId.trim();
    return id.isEmpty ? null : id;
  }

  /// 選択中の [BackendType] に応じた [MultiplexerConfig] を組み立てる。
  MultiplexerConfig buildMultiplexer() {
    return backend == BackendType.herdr
        ? MultiplexerConfig(
            backend: BackendType.herdr,
            executablePath: executablePath,
          )
        : MultiplexerConfig.tmux(executablePath);
  }

  /// フォームのコントローラ群から入力値を収集する。
  factory ConnectionFormValues.fromControllers({
    required TextEditingController nameController,
    required TextEditingController hostController,
    required TextEditingController portController,
    required TextEditingController usernameController,
    required TextEditingController passwordController,
    required TextEditingController multiplexerPathController,
    required TextEditingController deepLinkIdController,
    required String authMethod,
    required String? keyId,
    required BackendType backend,
  }) {
    return ConnectionFormValues(
      name: nameController.text.trim(),
      host: hostController.text.trim(),
      portText: portController.text,
      username: usernameController.text.trim(),
      password: passwordController.text,
      multiplexerPath: multiplexerPathController.text,
      deepLinkId: deepLinkIdController.text,
      authMethod: authMethod,
      keyId: keyId,
      backend: backend,
    );
  }
}
