import '../services/backend/domain/multiplexer_backend.dart';
import '../services/backend/domain/multiplexer_session.dart';
import 'active_session.dart';

/// 接続単位のセッション差分マージと履歴引継ぎ（純関数）。
///
/// 既存保持マップ構築、sessionId 優先キー化、legacy（sessionId null）
/// エントリの adopting 判定（同名ラベル唯一のみ）・重複継承防止を行う。
/// 既存一覧・新一覧・接続情報・`now` を受け取り新一覧を返す。
/// アプリ内専用（internal）。
class ActiveSessionsMerger {
  /// 接続のセッション一覧を共通 domain モデルから更新した結果を返す。
  ///
  /// 既存のセッションの lastWindowIndex/lastPaneId/lastAccessedAt は保持する。
  List<ActiveSession> merge({
    required List<ActiveSession> currentSessions,
    required String connectionId,
    required String connectionName,
    required String host,
    required List<MultiplexerSession> sessions,
    MultiplexerBackendKind backend = MultiplexerBackendKind.tmux,
    required DateTime now,
  }) {
    // 既存のセッション情報をマップに保存
    // キーは sessionId ?? sessionName（ID 優先）にすることで、同名ラベル
    // （herdr の "tmp" w3/w4）の履歴が相互誤継承されるのを防ぐ。
    final connectionSessions = currentSessions
        .where((s) => s.connectionId == connectionId)
        .toList();
    final existingMap = <String, ActiveSession>{};
    for (final s in connectionSessions) {
      existingMap[s.sessionId ?? s.sessionName] = s;
    }

    // 旧データ移行: sessionId 導入前のエントリ（sessionId == null）のうち、
    // 同名ラベル（sessionName）が一意なものを、新データの ID キーへ履歴ごと
    // 引き継ぐ。同名ラベルが複数ある場合（herdr の "tmp" w3/w4 が両方
    // sessionId: null で保存された旧データ）は対応関係を一意に決められない
    // ため移行しない（旧エントリは replace セマンティクスで破棄される）。
    final legacyLabelCounts = <String, int>{};
    for (final s in connectionSessions) {
      if (s.sessionId == null) {
        legacyLabelCounts[s.sessionName] =
            (legacyLabelCounts[s.sessionName] ?? 0) + 1;
      }
    }

    // 他の接続のセッションを保持
    final otherSessions = currentSessions
        .where((s) => s.connectionId != connectionId)
        .toList();

    // 移行で adopting 済みの旧エントリのキー（重複継承防止）。
    final adoptedLegacyKeys = <String>{};

    final newSessions = sessions.map((ms) {
      var existing = existingMap[ms.id ?? ms.name];
      // 旧エントリ（sessionId: null）→ 新データ（sessionId 付き）の引き継ぎ:
      // ID キーでヒットせず、ラベル一致する旧エントリが唯一の場合のみ
      // その旧エントリを adopting して履歴（connectedAt / lastAccessedAt /
      // lastWindowIndex / lastPaneId）を新エントリへ引き継ぐ。
      // adopting した旧エントリは以降の新エントリへ再利用しない
      // （新データ側にも同名ラベルが複数ある場合、履歴が重複継承されるのを防ぐ）。
      if (existing == null && ms.id != null) {
        final legacy = existingMap[ms.name];
        if (legacy != null &&
            legacy.sessionId == null &&
            legacyLabelCounts[ms.name] == 1 &&
            !adoptedLegacyKeys.contains(legacy.key)) {
          existing = legacy;
          adoptedLegacyKeys.add(legacy.key);
        }
      }
      return ActiveSession(
        connectionId: connectionId,
        connectionName: connectionName,
        host: host,
        sessionName: ms.name,
        sessionId: ms.id,
        windowCount: ms.windowCount,
        connectedAt: existing?.connectedAt ?? now,
        isAttached: ms.attached,
        backend: backend,
        lastWindowIndex: existing?.lastWindowIndex,
        lastPaneId: existing?.lastPaneId,
        lastAccessedAt: existing?.lastAccessedAt,
      );
    }).toList();

    return [...otherSessions, ...newSessions];
  }
}
