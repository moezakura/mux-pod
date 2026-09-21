import 'active_session.dart';

// inventory: PROV-ACTIVE-016
/// アクティブセッション一覧の状態
class ActiveSessionsState {
  // inventory: PROV-ACTIVE-017
  // inventory: LEGACY-0015
  final List<ActiveSession> sessions;
  // inventory: PROV-ACTIVE-018
  // inventory: LEGACY-0016
  final String? currentSessionKey; // connectionId:sessionName

  const ActiveSessionsState({this.sessions = const [], this.currentSessionKey});

  // inventory: PROV-ACTIVE-019
  ActiveSessionsState copyWith({
    List<ActiveSession>? sessions,
    String? currentSessionKey,
    // inventory: LEGACY-0025
    bool clearCurrentSession = false,
  }) {
    return ActiveSessionsState(
      sessions: sessions ?? this.sessions,
      currentSessionKey: clearCurrentSession
          ? null
          : (currentSessionKey ?? this.currentSessionKey),
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
      return sessions.firstWhere((s) => s.key == currentSessionKey);
    } catch (e) {
      return null;
    }
  }
}
