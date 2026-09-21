import '../services/backend/domain/multiplexer_backend.dart';

// inventory: PROV-ACTIVE-001
/// アクティブセッション情報
class ActiveSession {
  // inventory: PROV-ACTIVE-002
  // inventory: LEGACY-0001
  final String connectionId;
  // inventory: PROV-ACTIVE-003
  // inventory: LEGACY-0002
  final String connectionName;
  // inventory: PROV-ACTIVE-004
  // inventory: LEGACY-0003
  final String host;
  // inventory: PROV-ACTIVE-005
  // inventory: LEGACY-0004
  final String sessionName;
  // inventory: PROV-ACTIVE-005b
  /// セッション ID（tmux: "$0" / herdr: "w3"）。
  ///
  /// null の場合は [sessionName] でキー化する（旧データ互換）。
  /// herdr の同名ラベル（例: "tmp" の w3/w4）を ID で区別するために使う。
  final String? sessionId;
  // inventory: PROV-ACTIVE-006
  // inventory: LEGACY-0005
  final int windowCount;
  // inventory: PROV-ACTIVE-007
  // inventory: LEGACY-0006
  final DateTime connectedAt;
  // inventory: PROV-ACTIVE-008
  // inventory: LEGACY-0007
  final bool isAttached;

  /// backend 種別（backend 固有の UI・操作分岐に使う）。
  final MultiplexerBackendKind backend;

  // inventory: PROV-ACTIVE-009
  // inventory: LEGACY-0008
  /// 最後に開いていたウィンドウインデックス
  final int? lastWindowIndex;

  // inventory: PROV-ACTIVE-010
  // inventory: LEGACY-0009
  /// 最後に開いていたペインID
  final String? lastPaneId;

  // inventory: PROV-ACTIVE-011
  // inventory: LEGACY-0010
  /// 最終アクセス日時（履歴ソート用）
  final DateTime? lastAccessedAt;

  const ActiveSession({
    required this.connectionId,
    required this.connectionName,
    required this.host,
    required this.sessionName,
    this.sessionId,
    required this.windowCount,
    required this.connectedAt,
    this.isAttached = true,
    this.backend = MultiplexerBackendKind.tmux,
    this.lastWindowIndex,
    this.lastPaneId,
    this.lastAccessedAt,
  });

  // inventory: PROV-ACTIVE-012
  // inventory: LEGACY-0011
  ActiveSession copyWith({
    String? connectionId,
    String? connectionName,
    String? host,
    String? sessionName,
    String? sessionId,
    int? windowCount,
    DateTime? connectedAt,
    bool? isAttached,
    MultiplexerBackendKind? backend,
    int? lastWindowIndex,
    String? lastPaneId,
    DateTime? lastAccessedAt,
    bool clearLastPane = false,
  }) {
    return ActiveSession(
      connectionId: connectionId ?? this.connectionId,
      connectionName: connectionName ?? this.connectionName,
      host: host ?? this.host,
      sessionName: sessionName ?? this.sessionName,
      sessionId: sessionId ?? this.sessionId,
      windowCount: windowCount ?? this.windowCount,
      connectedAt: connectedAt ?? this.connectedAt,
      isAttached: isAttached ?? this.isAttached,
      backend: backend ?? this.backend,
      lastWindowIndex: lastWindowIndex ?? this.lastWindowIndex,
      lastPaneId: clearLastPane ? null : (lastPaneId ?? this.lastPaneId),
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }

  // inventory: PROV-ACTIVE-013
  // inventory: LEGACY-0012
  /// JSON形式でシリアライズ
  Map<String, dynamic> toJson() {
    return {
      'connectionId': connectionId,
      'connectionName': connectionName,
      'host': host,
      'sessionName': sessionName,
      'sessionId': sessionId,
      'windowCount': windowCount,
      'connectedAt': connectedAt.toIso8601String(),
      'isAttached': isAttached,
      'backend': backend.name,
      'lastWindowIndex': lastWindowIndex,
      'lastPaneId': lastPaneId,
      'lastAccessedAt': lastAccessedAt?.toIso8601String(),
    };
  }

  // inventory: PROV-ACTIVE-014
  // inventory: LEGACY-0013
  /// JSONからデシリアライズ
  factory ActiveSession.fromJson(Map<String, dynamic> json) {
    final lastAccessedAtStr = json['lastAccessedAt'] as String?;
    return ActiveSession(
      connectionId: json['connectionId'] as String,
      connectionName: json['connectionName'] as String,
      host: json['host'] as String,
      sessionName: json['sessionName'] as String,
      sessionId: json['sessionId'] as String?,
      windowCount: json['windowCount'] as int? ?? 0,
      connectedAt: DateTime.parse(json['connectedAt'] as String),
      isAttached: json['isAttached'] as bool? ?? false,
      backend: MultiplexerBackendKind.values.firstWhere(
        (b) => b.name == json['backend'],
        orElse: () => MultiplexerBackendKind.tmux,
      ),
      lastWindowIndex: json['lastWindowIndex'] as int?,
      lastPaneId: json['lastPaneId'] as String?,
      lastAccessedAt: lastAccessedAtStr != null
          ? DateTime.parse(lastAccessedAtStr)
          : null,
    );
  }

  // inventory: PROV-ACTIVE-015
  // inventory: LEGACY-0014
  /// セッションの一意なキー
  ///
  /// セッション ID（tmux: "$0" / herdr: "w3"）を優先し、無ければ
  /// sessionName（ラベル名）でキー化する（旧データ互換）。
  String get key {
    final id = sessionId ?? sessionName;
    return '$connectionId:$id';
  }
}
