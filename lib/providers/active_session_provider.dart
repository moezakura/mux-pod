import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/tmux/tmux_parser.dart';

/// アクティブセッション情報
class ActiveSession {
  final String connectionId;
  final String connectionName;
  final String host;
  final String sessionName;
  final int windowCount;
  final DateTime connectedAt;
  final bool isAttached;

  /// 最後に開いていたウィンドウインデックス
  final int? lastWindowIndex;

  /// 最後に開いていたペインID
  final String? lastPaneId;

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
  });

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
    );
  }

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
    };
  }

  /// JSONからデシリアライズ
  factory ActiveSession.fromJson(Map<String, dynamic> json) {
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
    );
  }

  /// セッションの一意なキー
  String get key => '$connectionId:$sessionName';
}

/// アクティブセッション一覧の状態
class ActiveSessionsState {
  final List<ActiveSession> sessions;
  final String? currentSessionKey; // connectionId:sessionName

  const ActiveSessionsState({
    this.sessions = const [],
    this.currentSessionKey,
  });

  ActiveSessionsState copyWith({
    List<ActiveSession>? sessions,
    String? currentSessionKey,
    bool clearCurrentSession = false,
  }) {
    return ActiveSessionsState(
      sessions: sessions ?? this.sessions,
      currentSessionKey:
          clearCurrentSession ? null : (currentSessionKey ?? this.currentSessionKey),
    );
  }

  /// 指定した接続のセッション一覧を取得
  List<ActiveSession> getSessionsForConnection(String connectionId) {
    return sessions.where((s) => s.connectionId == connectionId).toList();
  }

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

/// アクティブセッションを管理するNotifier
class ActiveSessionsNotifier extends Notifier<ActiveSessionsState> {
  static const _storageKey = 'active_sessions';

  @override
  ActiveSessionsState build() {
    // 初期化時にストレージから読み込み
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

  /// ストレージにセッション情報を保存
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = state.sessions.map((s) => s.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      // 保存エラーは無視
    }
  }

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

    final session = ActiveSession(
      connectionId: connectionId,
      connectionName: connectionName,
      host: host,
      sessionName: sessionName,
      windowCount: windowCount,
      connectedAt: existingSession?.connectedAt ?? DateTime.now(),
      isAttached: isAttached,
      lastWindowIndex: lastWindowIndex ?? existingSession?.lastWindowIndex,
      lastPaneId: lastPaneId ?? existingSession?.lastPaneId,
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
    );

    state = state.copyWith(sessions: sessions);
    _saveToStorage();
  }

  /// 接続のセッション一覧を更新（tmuxセッションリストから）
  /// 既存のセッションの lastWindowIndex/lastPaneId は保持する
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
      );
    }).toList();

    state = state.copyWith(sessions: [...otherSessions, ...newSessions]);
    _saveToStorage();
  }

  /// 現在のセッションを設定
  void setCurrentSession(String connectionId, String sessionName) {
    state = state.copyWith(currentSessionKey: '$connectionId:$sessionName');
  }

  /// 現在のセッションをクリア
  void clearCurrentSession() {
    state = state.copyWith(clearCurrentSession: true);
  }

  /// セッションを明示的に閉じる（削除）
  void closeSession(String connectionId, String sessionName) {
    final sessions = state.sessions
        .where((s) => !(s.connectionId == connectionId && s.sessionName == sessionName))
        .toList();
    state = state.copyWith(sessions: sessions);
    _saveToStorage();
  }

  /// セッションを削除（closeSessionのエイリアス）
  void removeSession(String connectionId, String sessionName) {
    closeSession(connectionId, sessionName);
  }

  /// 接続の全セッションを削除
  void removeSessionsForConnection(String connectionId) {
    final sessions =
        state.sessions.where((s) => s.connectionId != connectionId).toList();
    state = state.copyWith(sessions: sessions);
    _saveToStorage();
  }

  /// 全セッションをクリア
  void clear() {
    state = const ActiveSessionsState();
    _saveToStorage();
  }
}

/// アクティブセッションプロバイダー
final activeSessionsProvider =
    NotifierProvider<ActiveSessionsNotifier, ActiveSessionsState>(() {
  return ActiveSessionsNotifier();
});
