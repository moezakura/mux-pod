import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/enums.dart';
import '../../models/notification_rule.dart';

/// 通知ルールリポジトリ
///
/// 通知ルールの永続化を担当する。
class NotificationRepository {
  NotificationRepository({
    required SharedPreferences prefs,
  }) : _prefs = prefs;

  final SharedPreferences _prefs;

  static const _rulesKey = 'notification_rules';
  static const _eventsKey = 'notification_events';
  static const _maxEvents = 100; // 最大保存イベント数

  /// 全ルールを取得
  Future<List<NotificationRule>> getAllRules() async {
    final json = _prefs.getString(_rulesKey);
    if (json == null) return [];

    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      return decoded
          .map((e) => NotificationRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// ルールを保存
  Future<void> saveRule(NotificationRule rule) async {
    final rules = await getAllRules();
    final index = rules.indexWhere((r) => r.id == rule.id);

    if (index >= 0) {
      rules[index] = rule.copyWith(updatedAt: DateTime.now());
    } else {
      rules.add(rule);
    }

    await _saveRules(rules);
  }

  /// ルールを削除
  Future<void> deleteRule(String ruleId) async {
    final rules = await getAllRules();
    rules.removeWhere((r) => r.id == ruleId);
    await _saveRules(rules);
  }

  /// 全ルールを保存
  Future<void> _saveRules(List<NotificationRule> rules) async {
    final json = jsonEncode(rules.map((r) => r.toJson()).toList());
    await _prefs.setString(_rulesKey, json);
  }

  /// ルールを取得（ID指定）
  Future<NotificationRule?> getRule(String ruleId) async {
    final rules = await getAllRules();
    try {
      return rules.firstWhere((r) => r.id == ruleId);
    } catch (e) {
      return null;
    }
  }

  /// ルールの有効/無効を切り替え
  Future<void> setRuleEnabled(String ruleId, bool enabled) async {
    final rule = await getRule(ruleId);
    if (rule != null) {
      await saveRule(rule.copyWith(enabled: enabled, updatedAt: DateTime.now()));
    }
  }

  /// ルールのマッチ情報を更新
  Future<void> updateRuleMatchInfo(
    String ruleId, {
    required DateTime matchedAt,
    required int incrementCount,
  }) async {
    final rule = await getRule(ruleId);
    if (rule != null) {
      await saveRule(rule.copyWith(
        lastMatchedAt: matchedAt,
        matchCount: rule.matchCount + incrementCount,
        updatedAt: DateTime.now(),
      ));
    }
  }

  // === 通知イベント履歴 ===

  /// 通知イベントを保存
  Future<void> saveEvent(NotificationEvent event) async {
    final events = await getAllEvents();
    events.insert(0, event);

    // 最大数を超えたら古いイベントを削除
    if (events.length > _maxEvents) {
      events.removeRange(_maxEvents, events.length);
    }

    await _saveEvents(events);
  }

  /// 全イベントを取得
  Future<List<NotificationEvent>> getAllEvents() async {
    final json = _prefs.getString(_eventsKey);
    if (json == null) return [];

    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      return decoded
          .map((e) => NotificationEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 未読イベントを取得
  Future<List<NotificationEvent>> getUnreadEvents() async {
    final events = await getAllEvents();
    return events.where((e) => !e.read).toList();
  }

  /// イベントを既読にする
  Future<void> markEventAsRead(String eventId) async {
    final events = await getAllEvents();
    final index = events.indexWhere((e) => e.id == eventId);
    if (index >= 0) {
      events[index] = events[index].copyWith(read: true);
      await _saveEvents(events);
    }
  }

  /// 全イベントを既読にする
  Future<void> markAllEventsAsRead() async {
    final events = await getAllEvents();
    final updated = events.map((e) => e.copyWith(read: true)).toList();
    await _saveEvents(updated);
  }

  /// イベントを消去
  Future<void> dismissEvent(String eventId) async {
    final events = await getAllEvents();
    final index = events.indexWhere((e) => e.id == eventId);
    if (index >= 0) {
      events[index] = events[index].copyWith(dismissed: true);
      await _saveEvents(events);
    }
  }

  /// イベントを削除
  Future<void> deleteEvent(String eventId) async {
    final events = await getAllEvents();
    events.removeWhere((e) => e.id == eventId);
    await _saveEvents(events);
  }

  /// 全イベントを削除
  Future<void> clearAllEvents() async {
    await _prefs.remove(_eventsKey);
  }

  /// イベントを保存
  Future<void> _saveEvents(List<NotificationEvent> events) async {
    final json = jsonEncode(events.map((e) => e.toJson()).toList());
    await _prefs.setString(_eventsKey, json);
  }

  // === ユーティリティ ===

  /// 接続に関連するルールを取得
  Future<List<NotificationRule>> getRulesForConnection(String connectionId) async {
    final rules = await getAllRules();
    return rules.where((r) {
      if (r.scope == RuleScope.global) return true;
      return r.connectionId == connectionId;
    }).toList();
  }

  /// 有効なルールのみ取得
  Future<List<NotificationRule>> getEnabledRules() async {
    final rules = await getAllRules();
    return rules.where((r) => r.enabled).toList();
  }

  /// デフォルトルールを作成
  Future<void> createDefaultRules() async {
    final existingRules = await getAllRules();
    if (existingRules.isNotEmpty) return;

    final defaultRules = [
      NotificationRule.simple(
        id: 'default_error',
        name: 'Error Detection',
        pattern: 'error',
        actions: [NotificationAction.inApp, NotificationAction.vibrate],
      ),
      NotificationRule.simple(
        id: 'default_warning',
        name: 'Warning Detection',
        pattern: 'warning',
        actions: [NotificationAction.inApp],
      ),
      NotificationRule.simple(
        id: 'default_build_complete',
        name: 'Build Complete',
        pattern: 'BUILD SUCCESS',
        actions: [NotificationAction.inApp, NotificationAction.sound],
      ),
    ];

    for (final rule in defaultRules) {
      await saveRule(rule);
    }
  }
}
