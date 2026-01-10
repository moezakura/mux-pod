import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/enums.dart';
import '../models/notification_rule.dart';
import '../services/notification/notification_engine.dart';
import '../services/notification/notification_monitor.dart';
import '../services/notification/notification_repository.dart';
import '../services/notification/pattern_matcher.dart';
import 'connection_provider.dart';

/// PatternMatcher プロバイダー
final patternMatcherProvider = Provider<PatternMatcher>((ref) {
  return PatternMatcher();
});

/// NotificationEngine プロバイダー
final notificationEngineProvider = Provider<NotificationEngine>((ref) {
  final patternMatcher = ref.watch(patternMatcherProvider);
  final engine = NotificationEngine(patternMatcher: patternMatcher);

  ref.onDispose(() {
    engine.dispose();
  });

  return engine;
});

/// NotificationRepository プロバイダー
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  return NotificationRepository(prefs: storageService.prefs);
});

/// NotificationActionExecutor プロバイダー
final notificationActionExecutorProvider =
    Provider<NotificationActionExecutor>((ref) {
  return NotificationActionExecutor();
});

/// 通知ルール一覧プロバイダー
final notificationRulesProvider =
    AsyncNotifierProvider<NotificationRulesNotifier, List<NotificationRule>>(
  NotificationRulesNotifier.new,
);

/// 通知ルールNotifier
class NotificationRulesNotifier extends AsyncNotifier<List<NotificationRule>> {
  @override
  Future<List<NotificationRule>> build() async {
    final rules = await _repository.getAllRules();

    // エンジンにルールを登録
    _engine.clearRules();
    _engine.registerRules(rules);

    return rules;
  }

  NotificationRepository get _repository =>
      ref.read(notificationRepositoryProvider);
  NotificationEngine get _engine => ref.read(notificationEngineProvider);

  /// ルール作成
  Future<NotificationRule> create({
    required String name,
    String? description,
    required List<NotificationCondition> conditions,
    List<NotificationAction> actions = const [NotificationAction.inApp],
    NotificationFrequency frequency = NotificationFrequency.always,
    RuleScope scope = RuleScope.global,
    String? connectionId,
    String? sessionName,
  }) async {
    final rule = NotificationRule(
      id: const Uuid().v4(),
      name: name,
      description: description,
      conditions: conditions,
      actions: actions,
      frequency: frequency,
      scope: scope,
      connectionId: connectionId,
      sessionName: sessionName,
      createdAt: DateTime.now(),
    );

    await _repository.saveRule(rule);
    _engine.registerRule(rule);
    ref.invalidateSelf();

    return rule;
  }

  /// 簡易ルール作成
  Future<NotificationRule> createSimple({
    required String name,
    required String pattern,
    PatternType patternType = PatternType.text,
    List<NotificationAction> actions = const [NotificationAction.inApp],
  }) async {
    return create(
      name: name,
      conditions: [
        NotificationCondition(
          pattern: pattern,
          patternType: patternType,
        ),
      ],
      actions: actions,
    );
  }

  /// ルール更新
  Future<void> updateRule(NotificationRule rule) async {
    await _repository.saveRule(rule);
    _engine.updateRule(rule);
    ref.invalidateSelf();
  }

  /// ルール削除
  Future<void> delete(String ruleId) async {
    await _repository.deleteRule(ruleId);
    _engine.unregisterRule(ruleId);
    ref.invalidateSelf();
  }

  /// ルール有効/無効切り替え
  Future<void> setEnabled(String ruleId, bool enabled) async {
    await _repository.setRuleEnabled(ruleId, enabled);
    _engine.setRuleEnabled(ruleId, enabled);
    ref.invalidateSelf();
  }

  /// デフォルトルール作成
  Future<void> createDefaultRules() async {
    await _repository.createDefaultRules();
    ref.invalidateSelf();
  }

  /// 全ルール同期
  Future<void> syncRulesWithEngine() async {
    final rules = await _repository.getAllRules();
    _engine.clearRules();
    _engine.registerRules(rules);
    state = AsyncValue.data(rules);
  }
}

/// 単一ルールプロバイダー
final notificationRuleProvider =
    FutureProvider.family<NotificationRule?, String>((ref, id) async {
  final repository = ref.watch(notificationRepositoryProvider);
  return await repository.getRule(id);
});

/// 通知イベント履歴プロバイダー
final notificationEventsProvider =
    AsyncNotifierProvider<NotificationEventsNotifier, List<NotificationEvent>>(
  NotificationEventsNotifier.new,
);

/// 通知イベントNotifier
class NotificationEventsNotifier
    extends AsyncNotifier<List<NotificationEvent>> {
  StreamSubscription<NotificationEvent>? _subscription;

  @override
  Future<List<NotificationEvent>> build() async {
    // エンジンからのイベントを購読
    _subscription?.cancel();
    _subscription = _engine.events.listen(_onNewEvent);

    ref.onDispose(() {
      _subscription?.cancel();
    });

    return await _repository.getAllEvents();
  }

  NotificationRepository get _repository =>
      ref.read(notificationRepositoryProvider);
  NotificationEngine get _engine => ref.read(notificationEngineProvider);
  NotificationActionExecutor get _actionExecutor =>
      ref.read(notificationActionExecutorProvider);

  /// 新しいイベント受信時
  void _onNewEvent(NotificationEvent event) async {
    // イベント保存
    await _repository.saveEvent(event);

    // ルールのマッチ情報更新
    await _repository.updateRuleMatchInfo(
      event.ruleId,
      matchedAt: event.timestamp,
      incrementCount: 1,
    );

    // アクション実行
    final rule = await _repository.getRule(event.ruleId);
    if (rule != null) {
      await _actionExecutor.execute(event, rule.actions);
    }

    // 状態更新
    ref.invalidateSelf();
  }

  /// イベント既読
  Future<void> markAsRead(String eventId) async {
    await _repository.markEventAsRead(eventId);
    ref.invalidateSelf();
  }

  /// 全イベント既読
  Future<void> markAllAsRead() async {
    await _repository.markAllEventsAsRead();
    ref.invalidateSelf();
  }

  /// イベント消去
  Future<void> dismiss(String eventId) async {
    await _repository.dismissEvent(eventId);
    ref.invalidateSelf();
  }

  /// イベント削除
  Future<void> delete(String eventId) async {
    await _repository.deleteEvent(eventId);
    ref.invalidateSelf();
  }

  /// 全イベント削除
  Future<void> clearAll() async {
    await _repository.clearAllEvents();
    ref.invalidateSelf();
  }
}

/// 未読イベント数プロバイダー
final unreadNotificationCountProvider = Provider<int>((ref) {
  final eventsAsync = ref.watch(notificationEventsProvider);
  return eventsAsync.maybeWhen(
    data: (events) => events.where((e) => !e.read).length,
    orElse: () => 0,
  );
});

/// 最新の未読イベントプロバイダー
final latestUnreadEventProvider = Provider<NotificationEvent?>((ref) {
  final eventsAsync = ref.watch(notificationEventsProvider);
  return eventsAsync.maybeWhen(
    data: (events) {
      final unread = events.where((e) => !e.read && !e.dismissed).toList();
      return unread.isEmpty ? null : unread.first;
    },
    orElse: () => null,
  );
});

/// 接続ごとのルールプロバイダー
final connectionRulesProvider =
    FutureProvider.family<List<NotificationRule>, String>(
        (ref, connectionId) async {
  final repository = ref.watch(notificationRepositoryProvider);
  return await repository.getRulesForConnection(connectionId);
});

/// 有効なルールのみプロバイダー
final enabledRulesProvider =
    FutureProvider<List<NotificationRule>>((ref) async {
  final repository = ref.watch(notificationRepositoryProvider);
  return await repository.getEnabledRules();
});

/// NotificationMonitorFactory プロバイダー
final notificationMonitorFactoryProvider =
    Provider<NotificationMonitorFactory>((ref) {
  final engine = ref.watch(notificationEngineProvider);
  final factory = NotificationMonitorFactory(engine: engine);

  ref.onDispose(() {
    factory.clear();
  });

  return factory;
});
