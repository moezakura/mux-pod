import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notification/notification_engine.dart';

/// 通知状態
class NotificationState {
  final List<NotificationRule> rules;
  final List<NotificationEvent> recentEvents;
  final bool globalEnabled;
  final bool isLoading;
  final String? error;

  const NotificationState({
    this.rules = const [],
    this.recentEvents = const [],
    this.globalEnabled = true,
    this.isLoading = false,
    this.error,
  });

  NotificationState copyWith({
    List<NotificationRule>? rules,
    List<NotificationEvent>? recentEvents,
    bool? globalEnabled,
    bool? isLoading,
    String? error,
  }) {
    return NotificationState(
      rules: rules ?? this.rules,
      recentEvents: recentEvents ?? this.recentEvents,
      globalEnabled: globalEnabled ?? this.globalEnabled,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 通知を管理するNotifier
class NotificationNotifier extends Notifier<NotificationState> {
  late final NotificationEngine _engine;
  static const int _maxRecentEvents = 50;

  @override
  NotificationState build() {
    _engine = NotificationEngine();

    // イベントリスナーを設定
    _engine.events.listen(_handleNotificationEvent);

    // 初期化
    _initialize();

    ref.onDispose(() {
      _engine.dispose();
    });

    return const NotificationState(isLoading: true);
  }

  Future<void> _initialize() async {
    try {
      await _engine.initialize();
      state = NotificationState(
        rules: _engine.rules,
        globalEnabled: _engine.globalEnabled,
      );
    } catch (e) {
      state = NotificationState(error: e.toString());
    }
  }

  void _handleNotificationEvent(NotificationEvent event) {
    // 最近のイベントに追加
    final events = [event, ...state.recentEvents];
    if (events.length > _maxRecentEvents) {
      events.removeLast();
    }
    state = state.copyWith(recentEvents: events);
  }

  /// 通知エンジンを取得
  NotificationEngine get engine => _engine;

  /// ルールを追加
  Future<void> addRule(NotificationRule rule) async {
    _engine.addRule(rule);
    await _engine.saveRules();
    state = state.copyWith(rules: _engine.rules);
  }

  /// ルールを削除
  Future<void> removeRule(String ruleId) async {
    _engine.removeRule(ruleId);
    await _engine.saveRules();
    state = state.copyWith(rules: _engine.rules);
  }

  /// ルールを更新
  Future<void> updateRule(NotificationRule rule) async {
    _engine.updateRule(rule);
    await _engine.saveRules();
    state = state.copyWith(rules: _engine.rules);
  }

  /// ルールの有効/無効を切り替え
  Future<void> toggleRule(String ruleId) async {
    _engine.toggleRule(ruleId);
    await _engine.saveRules();
    state = state.copyWith(rules: _engine.rules);
  }

  /// グローバル有効/無効を切り替え
  void toggleGlobalEnabled() {
    _engine.globalEnabled = !_engine.globalEnabled;
    state = state.copyWith(globalEnabled: _engine.globalEnabled);
  }

  /// テキストを処理
  Future<void> processText(
    String text, {
    String? sessionName,
    String? windowName,
    String? paneId,
  }) async {
    await _engine.processText(
      text,
      sessionName: sessionName,
      windowName: windowName,
      paneId: paneId,
    );
  }

  /// 最近のイベントをクリア
  void clearRecentEvents() {
    state = state.copyWith(recentEvents: []);
  }

  /// リロード
  Future<void> reload() async {
    state = state.copyWith(isLoading: true, error: null);
    await _engine.loadRules();
    state = state.copyWith(
      rules: _engine.rules,
      isLoading: false,
    );
  }
}

/// 通知プロバイダー
final notificationProvider =
    NotifierProvider<NotificationNotifier, NotificationState>(() {
  return NotificationNotifier();
});
