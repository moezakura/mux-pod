import 'package:flutter/widgets.dart';

import '../../services/backend/backend_type.dart';
import '../../services/backend/multiplexer_config.dart';
import '../../services/connection/proxy_config.dart';

/// 接続毎 keepalive プローブタイムアウトの下限（秒・🤝3）。
const int minKeepaliveSeconds = 5;

/// 接続毎 keepalive プローブタイムアウトの上限（秒・🤝3）。
const int maxKeepaliveSeconds = 300;

/// フォーム hop 行の生入力（正規化前）。
///
/// [ConnectionFormValues] は controller を知らないため、画面側が
/// controller 群からこの形へ収集して渡す。
class ProxyHopInput {
  const ProxyHopInput({
    required this.hostText,
    required this.portText,
    required this.usernameText,
    required this.authMethod,
    required this.passwordText,
    this.keyId,
  });

  /// ホストの入力文字列。
  final String hostText;

  /// ポートの入力文字列（空欄は [buildProxy] で 22 になる）。
  final String portText;

  /// ユーザー名の入力文字列。
  final String usernameText;

  /// 認証方式（`'password'` | `'key'`）。
  final String authMethod;

  /// パスワードの入力文字列（空欄 = 既存値維持・保存時に書き換えない）。
  final String passwordText;

  /// 鍵認証時に選択された鍵 ID。
  final String? keyId;
}

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
    required this.proxyEnabled,
    required this.proxyHops,
    required this.forwardHostText,
    required this.forwardPortText,
    required this.keepaliveText,
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

  /// ジャンプホスト経由スイッチの状態。
  final bool proxyEnabled;

  /// hop 全行の生入力（チェーン順）。
  final List<ProxyHopInput> proxyHops;

  /// 転送先ホストの入力文字列（任意）。
  final String forwardHostText;

  /// 転送先ポートの入力文字列（任意）。
  final String forwardPortText;

  /// 接続毎 keepalive の入力文字列（空欄 = 未設定・自動）。
  final String keepaliveText;

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

  /// hop 全行を集約して [ProxyConfig] を組み立てる（🤝2 multi-hop）。
  ///
  /// - [proxyEnabled] が false、または有効行が 0 の場合は null（直接接続）。
  /// - 空文字正規化（M6）: 転送先ホストの空文字は未指定扱い。
  ///   転送先ホスト未指定時は転送先ポートのみの入力を無視する
  ///   （転送先ホストなしのポートは意味を持たないため）。
  ProxyConfig? buildProxy() {
    if (!proxyEnabled) return null;
    final hops = <ProxyHop>[];
    for (final hop in proxyHops) {
      final host = hop.hostText.trim();
      if (host.isEmpty) continue;
      hops.add(
        ProxyHop(
          host: host,
          port: int.tryParse(hop.portText.trim()) ?? 22,
          username: hop.usernameText.trim(),
          authMethod: hop.authMethod,
          keyId: hop.authMethod == 'key' ? hop.keyId : null,
        ),
      );
    }
    if (hops.isEmpty) return null;
    final forwardHost = forwardHostText.trim();
    final forwardPort = forwardHost.isEmpty
        ? null
        : int.tryParse(forwardPortText.trim());
    return ProxyConfig(
      hops: hops,
      forwardHost: forwardHost.isEmpty ? null : forwardHost,
      forwardPort: forwardPort,
    );
  }

  /// 接続毎 keepalive の入力を nullable int へパースする（🤝3）。
  ///
  /// 空欄 = 未設定（null・自動）。範囲外（[minKeepaliveSeconds] 未満・
  /// [maxKeepaliveSeconds] 超過）や非数は null（バリデーションで
  /// 保存がブロックされるため、ここでは防御的に未設定扱いにする）。
  int? get keepAliveTimeoutSecondsOrNull {
    final text = keepaliveText.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null) return null;
    if (value < minKeepaliveSeconds || value > maxKeepaliveSeconds) {
      return null;
    }
    return value;
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
    bool proxyEnabled = false,
    List<ProxyHopInput> proxyHops = const [],
    String forwardHostText = '',
    String forwardPortText = '',
    String keepaliveText = '',
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
      proxyEnabled: proxyEnabled,
      proxyHops: proxyHops,
      forwardHostText: forwardHostText,
      forwardPortText: forwardPortText,
      keepaliveText: keepaliveText,
    );
  }
}
