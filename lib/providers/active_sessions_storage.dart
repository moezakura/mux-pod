import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import 'active_session.dart';

/// アクティブセッション一覧の永続化（SharedPreferences への load / save）。
///
/// 保存直列キュー（[_saveFuture] チェーン）の所有者。アプリ内専用
/// （internal）。テストは notifier の公開メソッド経由で検証する方針。
class ActiveSessionsStorage {
  static const String storageKey = 'active_sessions';

  /// 永続化書き込みを直列化するためのFutureチェーン。
  Future<void>? _saveFuture;

  // inventory: PROV-ACTIVE-024
  /// ストレージからセッション情報を読み込み
  Future<List<ActiveSession>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(storageKey);
      if (jsonStr != null) {
        final jsonList = jsonDecode(jsonStr) as List<dynamic>;
        return jsonList
            .map((json) => ActiveSession.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      return null;
    } catch (e) {
      // 読み込みエラーは無視（初回起動時など）
      return null;
    }
  }

  // inventory: PROV-ACTIVE-025
  /// ストレージにセッション情報を保存。
  ///
  /// 複数の非同期書き込みが同時に走らないよう、[_saveFuture] チェーンで
  /// 直列化する。保存エラーはログに残し、後続の書き込みを阻害しない。
  Future<void> save(List<ActiveSession> sessions) async {
    final save = _enqueueSave(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final jsonList = sessions.map((s) => s.toJson()).toList();
        await prefs.setString(storageKey, jsonEncode(jsonList));
      } catch (e) {
        developer.log(
          'ActiveSessions save error: $e',
          name: 'ActiveSessionsProvider',
          error: e,
        );
      }
    });
    await save;
  }

  /// 保存処理を直列キューに入れる。
  Future<void> _enqueueSave(Future<void> Function() operation) {
    final previous = _saveFuture ?? Future.value();
    final current = previous.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _saveFuture = current;
    return current;
  }
}
