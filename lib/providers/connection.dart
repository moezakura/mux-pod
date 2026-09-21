import '../services/backend/backend_type.dart';
import '../services/backend/multiplexer_config.dart';
import '../services/connection/connection_storage_schema.dart';

/// 接続設定
class Connection {
  /// 現在の永続化スキーマバージョン（このアプリが書き込む新形式）。
  ///
  /// 旧 JSON（schemaVersion なし・tmuxPath 形式）は [legacyStorageSchemaVersion]
  /// として読み込む。新旧 JSON を共存させ、ダウングレード時に旧アプリが
  /// 読めるよう tmux backend では旧 `tmuxPath` フィールドも書き出す
  /// （G6 合意#4: schema 番号で新旧共存）。
  ///
  /// 実値は service 層（[ConnectionMigration]）と共有するため
  /// [ConnectionStorageSchema] に集約している。provider 層から import すると
  /// 循環依存になるため、このエイリアス経由で参照する。
  static const int currentStorageSchemaVersion =
      ConnectionStorageSchema.current;

  /// 旧 JSON（schemaVersion なし・tmuxPath 形式）のバージョン。
  static const int legacyStorageSchemaVersion = ConnectionStorageSchema.legacy;

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authMethod; // 'password' | 'key'
  final String? keyId;

  /// 使用する multiplexer の設定。
  final MultiplexerConfig multiplexer;

  /// 永続化スキーマのバージョン（JSON 上の形式を表す）。
  final int storageSchemaVersion;

  final DateTime createdAt;
  final DateTime? lastConnectedAt;

  /// ディープリンク用の識別子（外部スクリプトと共有可能）
  final String? deepLinkId;

  Connection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authMethod = 'password',
    this.keyId,
    MultiplexerConfig? multiplexer,
    int? storageSchemaVersion,
    required this.createdAt,
    this.lastConnectedAt,
    this.deepLinkId,
  }) : storageSchemaVersion =
           storageSchemaVersion ?? currentStorageSchemaVersion,
       multiplexer = multiplexer ?? const MultiplexerConfig.tmux();

  Connection copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? authMethod,
    String? keyId,
    MultiplexerConfig? multiplexer,
    int? storageSchemaVersion,
    DateTime? createdAt,
    DateTime? lastConnectedAt,
    String? deepLinkId,
    bool clearDeepLinkId = false,
  }) {
    return Connection(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      keyId: keyId ?? this.keyId,
      multiplexer: multiplexer ?? this.multiplexer,
      storageSchemaVersion: storageSchemaVersion ?? this.storageSchemaVersion,
      createdAt: createdAt ?? this.createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      deepLinkId: clearDeepLinkId ? null : (deepLinkId ?? this.deepLinkId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'authMethod': authMethod,
      'keyId': keyId,
      'multiplexer': multiplexer.toJson(),
      // ダウングレード互換: 旧アプリ（tmuxPath のみ読む）向けに tmux の
      // 実行ファイルパスも書き出す。自動検出（null）の場合は旧アプリ側で
      // 自動検出になるため省略してよい（G6 合意#4）。
      if (multiplexer.backend == BackendType.tmux &&
          multiplexer.executablePath != null)
        'tmuxPath': multiplexer.executablePath,
      'storageSchemaVersion': currentStorageSchemaVersion,
      'createdAt': createdAt.toIso8601String(),
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      'deepLinkId': deepLinkId,
    };
  }

  factory Connection.fromJson(Map<String, dynamic> json) {
    final multiplexerJson = json['multiplexer'] as Map<String, dynamic>?;
    final tmuxPath = json['tmuxPath'] as String?;
    final MultiplexerConfig multiplexer;
    if (multiplexerJson != null) {
      multiplexer = MultiplexerConfig.fromJson(multiplexerJson);
    } else if (tmuxPath != null && tmuxPath.isNotEmpty) {
      multiplexer = MultiplexerConfig.tmux(tmuxPath);
    } else {
      multiplexer = const MultiplexerConfig.tmux();
    }

    return Connection(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      username: json['username'] as String,
      authMethod: json['authMethod'] as String? ?? 'password',
      keyId: json['keyId'] as String?,
      multiplexer: multiplexer,
      // schemaVersion なしの旧 JSON は v1 として扱う。
      storageSchemaVersion:
          json['storageSchemaVersion'] as int? ?? legacyStorageSchemaVersion,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.parse(json['lastConnectedAt'] as String)
          : null,
      deepLinkId: json['deepLinkId'] as String?,
    );
  }
}

/// 読み込めなかった破損レコードの情報。
class CorruptedConnection {
  /// 読み込めた ID（ない場合もある）。
  final String? id;

  /// 破損理由（非機密）。
  final String reason;

  /// 元の JSON レコード（デバッグ・回復用）。
  final Map<String, dynamic>? rawJson;

  const CorruptedConnection({this.id, required this.reason, this.rawJson});

  Map<String, dynamic> toJson() {
    return {'id': id, 'reason': reason, 'rawJson': rawJson};
  }
}
