
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/tmux/tmux_models.dart';

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
  // inventory: PROV-ACTIVE-006
  // inventory: LEGACY-0005
  final int windowCount;
  // inventory: PROV-ACTIVE-007
  // inventory: LEGACY-0006
  final DateTime connectedAt;
  // inventory: PROV-ACTIVE-008
  // inventory: LEGACY-0007
  final bool isAttached;

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
    required this.windowCount,
    required this.connectedAt,
    this.isAttached = true,
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
    int? windowCount,
    DateTime? connectedAt,
    bool? isAttached,
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
      windowCount: windowCount ?? this.windowCount,
      connectedAt: connectedAt ?? this.connectedAt,
      isAttached: isAttached ?? this.isAttached,
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
      'windowCount': windowCount,
      'connectedAt': connectedAt.toIso8601String(),
      'isAttached': isAttached,
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
      windowCount: json['windowCount'] as int? ?? 0,
      connectedAt: DateTime.parse(json['connectedAt'] as String),
      isAttached: json['isAttached'] as bool? ?? false,
      lastWindowIndex: json['lastWindowIndex'] as int?,
      lastPaneId: json['lastPaneId'] as String?,
      lastAccessedAt: lastAccessedAtStr != null ? DateTime.parse(lastAccessedAtStr) : null,
    );
  }

  // inventory: PROV-ACTIVE-015
  // inventory: LEGACY-0014
  /// セッションの一意なキー
  String get key => '$connectionId:$sessionName';
}

// inventory: PROV-ACTIVE-016
/// アクティブセッション一覧の状態
class ActiveSessionsState {
  // inventory: PROV-ACTIVE-017
  // inventory: LEGACY-0015
  final List<ActiveSession> sessions;
  // inventory: PROV-ACTIVE-018
  // inventory: LEGACY-0016
  final String? currentSessionKey; // connectionId:sessionName

  const ActiveSessionsState({
    this.sessions = const [],
    this.currentSessionKey,
  });

  // inventory: PROV-ACTIVE-019
  ActiveSessionsState copyWith({
    List<ActiveSession>? sessions,
    String? currentSessionKey,
    // inventory: LEGACY-0025
    bool clearCurrentSession = false,
  }) {
    return ActiveSessionsState(
      sessions: sessions ?? this.sessions,
      currentSessionKey:
          clearCurrentSession ? null : (currentSessionKey ?? this.currentSessionKey),
    );
  }

  // inventory: PROV-ACTIVE-020
  // inventory: LEGACY-0017
  /// 指定した接続のセッション一覧を取得
  List<ActiveSession> getSessionsForConnection(String connectionId) {
    return sessions.where((s) => s.connectionId == connectionId).toList();
  }

  // inventory: PROV-ACTIVE-021
  /// 現在のセッションを取得
  ActiveSession? get currentSession {
    if (currentSessionKey == null) return null;
    try {
      return sessions.firstWhere(
        (s) => '${s.connectionId}:${s.sessionName}' == currentSessionKey,
      );
    } catch (e) {
      return null;
    }
  }
}

// inventory: PROV-ACTIVE-022
/// アクティブセッションを管理するNotifier
class ActiveSessionsNotifier extends Notifier<ActiveSessionsState> {
  static const _storageKey = 'active_sessions';

  /// 永続化書き込みを直列化するためのFutureチェーン。
  Future<void>? _saveFuture;

  @override
  // inventory: PROV-ACTIVE-023
  // inventory: LEGACY-0018
  ActiveSessionsState build() {
    // 初期化時にストレージから読み込み
    // inventory: PROV-ACTIVE-024
    _loadFromStorage();
    return const ActiveSessionsState();
  }

  /// ストレージからセッション情報を読み込み
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final jsonList = jsonDecode(jsonStr) as List<dynamic>;
        final sessions = jsonList
            .map((json) => ActiveSession.fromJson(json as Map<String, dynamic>))
            .toList();
        state = state.copyWith(sessions: sessions);
      }
    } catch (e) {
      // 読み込みエラーは無視（初回起動時など）
    }
  }

  // inventory: PROV-ACTIVE-025
  /// ストレージにセッション情報を保存。
  ///
  /// 複数の非同期書き込みが同時に走らないよう、[_saveFuture] チェーンで
  /// 直列化する。保存エラーはログに残し、後続の書き込みを阻害しない。
  Future<void> _saveToStorage() async {
    final save = _enqueueSave(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final jsonList = state.sessions.map((s) => s.toJson()).toList();
        await prefs.setString(_storageKey, jsonEncode(jsonList));
      } catch (e) {
        developer.log('ActiveSessions save error: $e', name: 'ActiveSessionsProvider', error: e);
      }
    });
    await save;
  }

  /// 保存処理を直列キューに入れる。
  Future<void> _enqueueSave(Future<void> Function() operation) {
    final previous = _saveFuture ?? Future.value();
    final current = previous.then((_) => operation(), onError: (_) => operation());
    _saveFuture = current;
    return current;
  }

  // inventory: PROV-ACTIVE-026
  // inventory: LEGACY-0019
  /// セッションを追加または更新
  void addOrUpdateSession({
    required String connectionId,
    required String connectionName,
    required String host,
    required String sessionName,
    required int windowCount,
    bool isAttached = true,
    int? lastWindowIndex,
    String? lastPaneId,
  }) {
    final key = '$connectionId:$sessionName';
    final existingIndex = state.sessions.indexWhere(
      (s) => s.key == key,
    );

    final existingSession = existingIndex >= 0 ? state.sessions[existingIndex] : null;
    final now = DateTime.now();

    final session = ActiveSession(
      connectionId: connectionId,
      connectionName: connectionName,
      host: host,
      sessionName: sessionName,
      windowCount: windowCount,
      connectedAt: existingSession?.connectedAt ?? now,
      isAttached: isAttached,
      lastWindowIndex: lastWindowIndex ?? existingSession?.lastWindowIndex,
      lastPaneId: lastPaneId ?? existingSession?.lastPaneId,
      lastAccessedAt: isAttached ? now : existingSession?.lastAccessedAt,
    );

    final sessions = [...state.sessions];
    if (existingIndex >= 0) {
      sessions[existingIndex] = session;
    } else {
      sessions.add(session);
    }

    state = state.copyWith(sessions: sessions);
    _saveToStorage();
  }

  // inventory: PROV-ACTIVE-027
  // inventory: LEGACY-0020
  /// セッションの最後に開いていたペイン情報を更新
  void updateLastPane({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required String paneId,
  }) {
    final key = '$connectionId:$sessionName';
    final existingIndex = state.sessions.indexWhere((s) => s.key == key);
    if (existingIndex < 0) return;

    final sessions = [...state.sessions];
    sessions[existingIndex] = sessions[existingIndex].copyWith(
      lastWindowIndex: windowIndex,
      lastPaneId: paneId,
      lastAccessedAt: DateTime.now(),
    );

    state = state.copyWith(sessions: sessions);
    _saveToStorage();
  }

  // inventory: PROV-ACTIVE-028
  // inventory: LEGACY-0021
  /// セッションのウィンドウ数を更新（ウィンドウ作成/削除後の同期用）
  void updateWindowCount(String connectionId, String sessionName, int windowCount) {
    final key = '$connectionId:$sessionName';
    final existingIndex = state.sessions.indexWhere((s) => s.key == key);
    if (existingIndex < 0) return;
    if (state.sessions[existingIndex].windowCount == windowCount) return;
    final sessions = [...state.sessions];
    sessions[existingIndex] =
        sessions[existingIndex].copyWith(windowCount: windowCount);
    state = state.copyWith(sessions: sessions);
    _saveToStorage();
  }

  // inventory: PROV-ACTIVE-029
  // inventory: LEGACY-0022
  /// セッションを開いた時に最終アクセス日時を更新
  void touchSession(String connectionId, String sessionName) {
    final key = '$connectionId:$sessionName';
    final existingIndex = state.sessions.indexWhere((s) => s.key == key);
    if (existingIndex < 0) return;

    final sessions = [...state.sessions];
    sessions[existingIndex] = sessions[existingIndex].copyWith(
      lastAccessedAt: DateTime.now(),
    );

    state = state.copyWith(sessions: sessions);
    _saveToStorage();
  }

  // inventory: PROV-ACTIVE-030
  // inventory: LEGACY-0023
  /// 接続のセッション一覧を更新（tmuxセッションリストから）
  /// 既存のセッションの lastWindowIndex/lastPaneId/lastAccessedAt は保持する
  void updateSessionsForConnection({
    required String connectionId,
    required String connectionName,
    required String host,
    required List<TmuxSession> tmuxSessions,
  }) {
    // 既存のセッション情報をマップに保存
    final existingMap = <String, ActiveSession>{};
    for (final s in state.sessions.where((s) => s.connectionId == connectionId)) {
      existingMap[s.sessionName] = s;
    }

    // 他の接続のセッションを保持
    final otherSessions = state.sessions
        .where((s) => s.connectionId != connectionId)
        .toList();

    final newSessions = tmuxSessions.map((ts) {
      final existing = existingMap[ts.name];
      return ActiveSession(
        connectionId: connectionId,
        connectionName: connectionName,
        host: host,
        sessionName: ts.name,
        windowCount: ts.windowCount,
        connectedAt: existing?.connectedAt ?? DateTime.now(),
        isAttached: ts.attached,
        lastWindowIndex: existing?.lastWindowIndex,
        lastPaneId: existing?.lastPaneId,
        lastAccessedAt: existing?.lastAccessedAt,
      );
    }).toList();

    state = state.copyWith(sessions: [...otherSessions, ...newSessions]);
    _saveToStorage();
  }

  // inventory: PROV-ACTIVE-031
  // inventory: LEGACY-0024
  /// 現在のセッションを設定
  void setCurrentSession(String connectionId, String sessionName) {
    state = state.copyWith(currentSessionKey: '$connectionId:$sessionName');
  }

  // inventory: PROV-ACTIVE-032
  /// 現在のセッションをクリア
  void clearCurrentSession() {
    state = state.copyWith(clearCurrentSession: true);
  }

  // inventory: PROV-ACTIVE-033
  // inventory: LEGACY-0026
  /// セッションを明示的に閉じる（削除）
  void closeSession(String connectionId, String sessionName) {
    final sessions = state.sessions
        .where((s) => !(s.connectionId == connectionId && s.sessionName == sessionName))
        .toList();
    state = state.copyWith(sessions: sessions);
    _saveToStorage();
  }

  // inventory: PROV-ACTIVE-034
  // inventory: LEGACY-0027
  /// セッションを削除（closeSessionのエイリアス）
  void removeSession(String connectionId, String sessionName) {
    closeSession(connectionId, sessionName);
  }

  // inventory: PROV-ACTIVE-035
  // inventory: LEGACY-0028
  /// 接続の全セッションを削除
  void removeSessionsForConnection(String connectionId) {
    final sessions =
        state.sessions.where((s) => s.connectionId != connectionId).toList();
    state = state.copyWith(sessions: sessions);
    _saveToStorage();
  }

  // inventory: PROV-ACTIVE-036
  // inventory: LEGACY-0029
  /// 全セッションをクリア
  void clear() {
    state = const ActiveSessionsState();
    _saveToStorage();
  }
}

// inventory: PROV-ACTIVE-037
/// アクティブセッションプロバイダー
final activeSessionsProvider =
    NotifierProvider<ActiveSessionsNotifier, ActiveSessionsState>(() {
  return ActiveSessionsNotifier();
});
