import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backend/domain/multiplexer_backend.dart';
import '../services/backend/domain/multiplexer_session.dart';
import '../services/tmux/tmux_models.dart';
import '../services/tmux/tmux_to_domain.dart';
import 'active_session.dart';
import 'active_sessions_merger.dart';
import 'active_sessions_state.dart';
import 'active_sessions_storage.dart';

// inventory: PROV-ACTIVE-022
/// アクティブセッションを管理するNotifier
class ActiveSessionsNotifier extends Notifier<ActiveSessionsState> {
  /// セッションリストの永続化（保存直列キューは storage が保有）。
  late final ActiveSessionsStorage _storage = ActiveSessionsStorage();

  /// 接続単位のセッション差分マージ（純関数）。
  late final ActiveSessionsMerger _merger = ActiveSessionsMerger();

  @override
  // inventory: PROV-ACTIVE-023
  // inventory: LEGACY-0018
  ActiveSessionsState build() {
    // 初期化時にストレージから読み込み
    _loadFromStorage();
    return const ActiveSessionsState();
  }

  /// ストレージからセッション情報を読み込み
  Future<void> _loadFromStorage() async {
    final sessions = await _storage.load();
    if (sessions != null) {
      state = state.copyWith(sessions: sessions);
    }
  }

  // inventory: PROV-ACTIVE-026
  // inventory: LEGACY-0019
  /// セッションを追加または更新
  void addOrUpdateSession({
    required String connectionId,
    required String connectionName,
    required String host,
    required String sessionName,
    String? sessionId,
    required int windowCount,
    bool isAttached = true,
    int? lastWindowIndex,
    String? lastPaneId,
  }) {
    final key = '$connectionId:${sessionId ?? sessionName}';
    final existingIndex = state.sessions.indexWhere((s) => s.key == key);

    final existingSession = existingIndex >= 0
        ? state.sessions[existingIndex]
        : null;
    final now = DateTime.now();

    final session = ActiveSession(
      connectionId: connectionId,
      connectionName: connectionName,
      host: host,
      sessionName: sessionName,
      sessionId: sessionId,
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
    _storage.save(state.sessions);
  }

  // inventory: PROV-ACTIVE-027
  // inventory: LEGACY-0020
  /// セッションの最後に開いていたペイン情報を更新
  void updateLastPane({
    required String connectionId,
    required String sessionName,
    String? sessionId,
    required int windowIndex,
    required String paneId,
  }) {
    final key = '$connectionId:${sessionId ?? sessionName}';
    final existingIndex = state.sessions.indexWhere((s) => s.key == key);
    if (existingIndex < 0) return;

    final sessions = [...state.sessions];
    sessions[existingIndex] = sessions[existingIndex].copyWith(
      lastWindowIndex: windowIndex,
      lastPaneId: paneId,
      lastAccessedAt: DateTime.now(),
    );

    state = state.copyWith(sessions: sessions);
    _storage.save(state.sessions);
  }

  // inventory: PROV-ACTIVE-028
  // inventory: LEGACY-0021
  /// セッションのウィンドウ数を更新（ウィンドウ作成/削除後の同期用）
  void updateWindowCount(
    String connectionId,
    String sessionName,
    int windowCount, {
    String? sessionId,
  }) {
    final key = '$connectionId:${sessionId ?? sessionName}';
    final existingIndex = state.sessions.indexWhere((s) => s.key == key);
    if (existingIndex < 0) return;
    if (state.sessions[existingIndex].windowCount == windowCount) return;
    final sessions = [...state.sessions];
    sessions[existingIndex] = sessions[existingIndex].copyWith(
      windowCount: windowCount,
    );
    state = state.copyWith(sessions: sessions);
    _storage.save(state.sessions);
  }

  // inventory: PROV-ACTIVE-029
  // inventory: LEGACY-0022
  /// セッションを開いた時に最終アクセス日時を更新
  void touchSession(
    String connectionId,
    String sessionName, {
    String? sessionId,
  }) {
    final key = '$connectionId:${sessionId ?? sessionName}';
    final existingIndex = state.sessions.indexWhere((s) => s.key == key);
    if (existingIndex < 0) return;

    final sessions = [...state.sessions];
    sessions[existingIndex] = sessions[existingIndex].copyWith(
      lastAccessedAt: DateTime.now(),
    );

    state = state.copyWith(sessions: sessions);
    _storage.save(state.sessions);
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
    updateSessionsFromDomain(
      connectionId: connectionId,
      connectionName: connectionName,
      host: host,
      sessions: tmuxSessions.map((ts) => ts.toDomain()).toList(),
    );
  }

  /// 接続のセッション一覧を共通 domain モデルから更新する。
  ///
  /// tmux/herdr どちらの backend も [MultiplexerSession] 経由で登録できる。
  /// 既存のセッションの lastWindowIndex/lastPaneId/lastAccessedAt は保持する。
  /// マージ本体は [ActiveSessionsMerger]（純関数）が担う。
  void updateSessionsFromDomain({
    required String connectionId,
    required String connectionName,
    required String host,
    required List<MultiplexerSession> sessions,
    MultiplexerBackendKind backend = MultiplexerBackendKind.tmux,
  }) {
    final merged = _merger.merge(
      currentSessions: state.sessions,
      connectionId: connectionId,
      connectionName: connectionName,
      host: host,
      sessions: sessions,
      backend: backend,
      now: DateTime.now(),
    );
    state = state.copyWith(sessions: merged);
    _storage.save(state.sessions);
  }

  // inventory: PROV-ACTIVE-031
  // inventory: LEGACY-0024
  /// 現在のセッションを設定
  void setCurrentSession(
    String connectionId,
    String sessionName, {
    String? sessionId,
  }) {
    state = state.copyWith(
      currentSessionKey: '$connectionId:${sessionId ?? sessionName}',
    );
  }

  // inventory: PROV-ACTIVE-032
  /// 現在のセッションをクリア
  void clearCurrentSession() {
    state = state.copyWith(clearCurrentSession: true);
  }

  // inventory: PROV-ACTIVE-033
  // inventory: LEGACY-0026
  /// セッションを明示的に閉じる（削除）
  void closeSession(
    String connectionId,
    String sessionName, {
    String? sessionId,
  }) {
    final targetKey = '$connectionId:${sessionId ?? sessionName}';
    final sessions = state.sessions.where((s) => s.key != targetKey).toList();
    state = state.copyWith(sessions: sessions);
    _storage.save(state.sessions);
  }

  // inventory: PROV-ACTIVE-034
  // inventory: LEGACY-0027
  /// セッションを削除（closeSessionのエイリアス）
  void removeSession(
    String connectionId,
    String sessionName, {
    String? sessionId,
  }) {
    closeSession(connectionId, sessionName, sessionId: sessionId);
  }

  // inventory: PROV-ACTIVE-035
  // inventory: LEGACY-0028
  /// 接続の全セッションを削除
  void removeSessionsForConnection(String connectionId) {
    final sessions = state.sessions
        .where((s) => s.connectionId != connectionId)
        .toList();
    state = state.copyWith(sessions: sessions);
    _storage.save(state.sessions);
  }

  // inventory: PROV-ACTIVE-036
  // inventory: LEGACY-0029
  /// 全セッションをクリア
  void clear() {
    state = const ActiveSessionsState();
    _storage.save(state.sessions);
  }
}

// inventory: PROV-ACTIVE-037
/// アクティブセッションプロバイダー
final activeSessionsProvider =
    NotifierProvider<ActiveSessionsNotifier, ActiveSessionsState>(() {
      return ActiveSessionsNotifier();
    });
