import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'active_session_provider.dart';

/// 最終アクセス日時でソートされたセッション履歴プロバイダー
/// lastAccessedAt降順（最新が先頭）でソート
final sessionHistoryProvider = Provider<List<ActiveSession>>((ref) {
  final state = ref.watch(activeSessionsProvider);

  final sorted = [...state.sessions]
    ..sort((a, b) {
      // lastAccessedAtがなければconnectedAtにフォールバック
      final aTime = a.lastAccessedAt ?? a.connectedAt;
      final bTime = b.lastAccessedAt ?? b.connectedAt;
      return bTime.compareTo(aTime); // 降順
    });

  return sorted;
});
