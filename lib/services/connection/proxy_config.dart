/// ジャンプホスト（SSH 踏み台）経由接続の設定。
///
/// 接続設定（`Connection.proxy`）として永続化される persisted 形。
/// 実行時に認証情報を解決した runtime 形は `ssh_models.dart` の
/// `SshProxyOptions` が担う（層の規約: persisted / runtime 分離）。
///
/// 値オブジェクトの規約（`MultiplexerConfig` パターン）に従う:
/// const コンストラクタ / toJson / fromJson（FormatException）/ == / copyWith。
/// 未知の JSON 形式は破損データとして `Connection.fromJson` 側で
/// null フォールバック（M2）できるよう `FormatException` で拒否する。
library;

/// ジャンプホストチェーンの最大ホップ数。
///
/// connector の validate と UI の「ホップを追加」停止の両方で強制する
/// （OQ-5）。上限により最悪レイテンシ（hops × timeout × 2）が機械的に
/// bounded され、設定爆発（循環チェーン等）も構造的に防止される。
const int maxProxyHops = 5;

/// ジャンプホスト 1 ホップの設定。
class ProxyHop {
  /// 踏み台ホスト。
  final String host;

  /// 踏み台ポート。
  final int port;

  /// 踏み台のユーザー名。
  final String username;

  /// 認証方式（`'password'` | `'key'`）。
  final String authMethod;

  /// 鍵認証時に使う保存済み SSH 鍵の ID（password 認証時は null）。
  final String? keyId;

  /// copyWith のクリア用センチネル。
  static const _kClearSentinel = Object();

  const ProxyHop({
    required this.host,
    this.port = 22,
    required this.username,
    this.authMethod = 'password',
    this.keyId,
  });

  /// 部分的に値を更新したコピーを返す。
  ///
  /// [keyId] に `null` を渡すと `keyId` をクリアできる。
  ProxyHop copyWith({
    String? host,
    int? port,
    String? username,
    String? authMethod,
    Object? keyId = _kClearSentinel,
  }) {
    return ProxyHop(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      keyId: keyId == _kClearSentinel ? this.keyId : keyId as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'username': username,
      'authMethod': authMethod,
      'keyId': keyId,
    };
  }

  /// JSON から復元する。
  ///
  /// 型が壊れている場合は [FormatException] を投げる（破損データ耐性 M2 の
  /// ため TypeError を漏らさない）。
  factory ProxyHop.fromJson(Map<String, dynamic> json) {
    final host = json['host'];
    final port = json['port'];
    final username = json['username'];
    final authMethod = json['authMethod'];
    final keyId = json['keyId'];
    if (host is! String) {
      throw FormatException('host must be a string: $host');
    }
    if (port != null && port is! int) {
      throw FormatException('port must be an int: $port');
    }
    if (username is! String) {
      throw FormatException('username must be a string: $username');
    }
    if (authMethod != null && authMethod is! String) {
      throw FormatException('authMethod must be a string: $authMethod');
    }
    if (keyId != null && keyId is! String) {
      throw FormatException('keyId must be a string: $keyId');
    }
    return ProxyHop(
      host: host,
      port: port as int? ?? 22,
      username: username,
      authMethod: authMethod as String? ?? 'password',
      keyId: keyId as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProxyHop &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          username == other.username &&
          authMethod == other.authMethod &&
          keyId == other.keyId;

  @override
  int get hashCode => Object.hash(host, port, username, authMethod, keyId);

  @override
  String toString() =>
      'ProxyHop(host: $host, port: $port, username: $username, '
      'authMethod: $authMethod, keyId: $keyId)';
}

/// ジャンプホスト経由接続の設定。
///
/// [hops] はチェーン順（hop 0 が最初にダイヤルされる踏み台）。hop i は
/// hop i-1 経由で到達し、最終 hop から [forwardHost]:[forwardPort]
/// （未指定時は接続先座標）へ転送される。
class ProxyConfig {
  /// 踏み台チェーン（チェーン順・1 ホップ以上）。
  final List<ProxyHop> hops;

  /// 転送先ホスト（null なら接続先の host で解決）。
  final String? forwardHost;

  /// 転送先ポート（null なら接続先の port で解決）。
  final int? forwardPort;

  /// copyWith のクリア用センチネル。
  static const _kClearSentinel = Object();

  const ProxyConfig({required this.hops, this.forwardHost, this.forwardPort});

  /// 部分的に値を更新したコピーを返す。
  ///
  /// [forwardHost] / [forwardPort] に `null` を渡すとそれぞれクリアできる。
  ProxyConfig copyWith({
    List<ProxyHop>? hops,
    Object? forwardHost = _kClearSentinel,
    Object? forwardPort = _kClearSentinel,
  }) {
    return ProxyConfig(
      hops: hops ?? this.hops,
      forwardHost: forwardHost == _kClearSentinel
          ? this.forwardHost
          : forwardHost as String?,
      forwardPort: forwardPort == _kClearSentinel
          ? this.forwardPort
          : forwardPort as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hops': hops.map((hop) => hop.toJson()).toList(),
      'forwardHost': forwardHost,
      'forwardPort': forwardPort,
    };
  }

  /// JSON から復元する。
  ///
  /// 型が壊れている場合は [FormatException] を投げる（破損データ耐性 M2 の
  /// ため TypeError を漏らさない）。
  factory ProxyConfig.fromJson(Map<String, dynamic> json) {
    final hopsJson = json['hops'];
    if (hopsJson is! List) {
      throw FormatException('hops must be a list: ${json['hops']}');
    }
    final forwardHost = json['forwardHost'];
    final forwardPort = json['forwardPort'];
    if (forwardHost != null && forwardHost is! String) {
      throw FormatException('forwardHost must be a string: $forwardHost');
    }
    if (forwardPort != null && forwardPort is! int) {
      throw FormatException('forwardPort must be an int: $forwardPort');
    }
    return ProxyConfig(
      hops: hopsJson.map((hopJson) {
        if (hopJson is! Map) {
          throw FormatException('hop must be a map: $hopJson');
        }
        return ProxyHop.fromJson(Map<String, dynamic>.from(hopJson));
      }).toList(),
      forwardHost: forwardHost as String?,
      forwardPort: forwardPort as int?,
    );
  }

  /// hops を含む deep 等価（L1）。要素は [ProxyHop.==] で比較する。
  bool hopsEqual(ProxyConfig other) {
    if (hops.length != other.hops.length) return false;
    for (var i = 0; i < hops.length; i++) {
      if (hops[i] != other.hops[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProxyConfig &&
          runtimeType == other.runtimeType &&
          hopsEqual(other) &&
          forwardHost == other.forwardHost &&
          forwardPort == other.forwardPort;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(hops), forwardHost, forwardPort);

  @override
  String toString() =>
      'ProxyConfig(hops: $hops, forwardHost: $forwardHost, '
      'forwardPort: $forwardPort)';
}
