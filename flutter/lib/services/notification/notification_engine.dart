import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/enums.dart';
import '../../models/notification_rule.dart';
import 'pattern_matcher.dart';

/// 通知エンジン
///
/// ターミナル出力を監視し、ルールにマッチした場合に通知イベントを発行する。
class NotificationEngine {
  NotificationEngine({
    PatternMatcher? patternMatcher,
  }) : _patternMatcher = patternMatcher ?? PatternMatcher();

  final PatternMatcher _patternMatcher;
  final _uuid = const Uuid();

  /// 登録されたルール
  final Map<String, NotificationRule> _rules = {};

  /// 通知イベントストリーム
  final _eventController = StreamController<NotificationEvent>.broadcast();

  /// 頻度制御用のマッチ履歴
  /// key: ruleId, value: 最後のマッチ情報
  final Map<String, _MatchHistory> _matchHistory = {};

  /// セッション開始時間（oncePerSession用）
  final Map<String, DateTime> _sessionStartTimes = {};

  /// 通知イベントストリーム
  Stream<NotificationEvent> get events => _eventController.stream;

  /// ルール一覧を取得
  List<NotificationRule> get rules => _rules.values.toList();

  /// ルールを登録
  void registerRule(NotificationRule rule) {
    _rules[rule.id] = rule;
  }

  /// ルールを複数登録
  void registerRules(Iterable<NotificationRule> rules) {
    for (final rule in rules) {
      registerRule(rule);
    }
  }

  /// ルールを削除
  void unregisterRule(String ruleId) {
    _rules.remove(ruleId);
    _matchHistory.remove(ruleId);
  }

  /// 全ルールをクリア
  void clearRules() {
    _rules.clear();
    _matchHistory.clear();
  }

  /// ルールを更新
  void updateRule(NotificationRule rule) {
    _rules[rule.id] = rule;
  }

  /// セッション開始を記録
  void startSession(String connectionId) {
    _sessionStartTimes[connectionId] = DateTime.now();
  }

  /// セッション終了を記録
  void endSession(String connectionId) {
    _sessionStartTimes.remove(connectionId);
    // このセッションに関連するマッチ履歴をクリア
    _matchHistory.removeWhere((_, history) => history.connectionId == connectionId);
  }

  /// ターミナル出力を処理
  ///
  /// [text] 新しく出力されたテキスト
  /// [connectionId] 接続ID
  /// [connectionName] 接続名
  /// [sessionName] tmuxセッション名（オプション）
  /// [windowName] tmuxウィンドウ名（オプション）
  /// [paneIndex] tmuxペインインデックス（オプション）
  Future<List<NotificationEvent>> processOutput({
    required String text,
    required String connectionId,
    required String connectionName,
    String? sessionName,
    String? windowName,
    int? paneIndex,
  }) async {
    final events = <NotificationEvent>[];

    for (final rule in _rules.values) {
      if (!rule.enabled) continue;

      // スコープチェック
      if (!_checkScope(rule, connectionId, sessionName)) continue;

      // パターンマッチング
      final result = _patternMatcher.matchRule(rule, text);
      if (!result.matched) continue;

      // 頻度チェック
      if (!_checkFrequency(rule, connectionId, result.matchedText ?? text)) {
        continue;
      }

      // 通知イベント生成
      final event = NotificationEvent(
        id: _uuid.v4(),
        ruleId: rule.id,
        ruleName: rule.name,
        connectionId: connectionId,
        connectionName: connectionName,
        sessionName: sessionName,
        windowName: windowName,
        paneIndex: paneIndex,
        matchedText: result.matchedText ?? text,
        pattern: rule.conditions.first.pattern,
        timestamp: DateTime.now(),
      );

      events.add(event);
      _eventController.add(event);

      // マッチ履歴を更新
      _updateMatchHistory(rule.id, connectionId, result.matchedText ?? text);

      // デバッグログ
      debugPrint(
        'NotificationEngine: Rule "${rule.name}" matched: "${result.matchedText}"',
      );
    }

    return events;
  }

  /// スコープをチェック
  bool _checkScope(
    NotificationRule rule,
    String connectionId,
    String? sessionName,
  ) {
    switch (rule.scope) {
      case RuleScope.global:
        return true;
      case RuleScope.connection:
        return rule.connectionId == connectionId;
      case RuleScope.session:
        return rule.connectionId == connectionId &&
            rule.sessionName == sessionName;
    }
  }

  /// 頻度をチェック
  bool _checkFrequency(
    NotificationRule rule,
    String connectionId,
    String matchedText,
  ) {
    final history = _matchHistory[rule.id];

    switch (rule.frequency) {
      case NotificationFrequency.always:
        return true;

      case NotificationFrequency.oncePerSession:
        final sessionStart = _sessionStartTimes[connectionId];
        if (sessionStart == null) return true;
        if (history == null) return true;
        // このセッション開始後にマッチしていなければOK
        return history.lastMatchTime.isBefore(sessionStart);

      case NotificationFrequency.oncePerMatch:
        if (history == null) return true;
        // 同じテキストでマッチしていなければOK
        return history.lastMatchedText != matchedText;
    }
  }

  /// マッチ履歴を更新
  void _updateMatchHistory(
    String ruleId,
    String connectionId,
    String matchedText,
  ) {
    _matchHistory[ruleId] = _MatchHistory(
      connectionId: connectionId,
      lastMatchTime: DateTime.now(),
      lastMatchedText: matchedText,
    );
  }

  /// ルールを有効/無効切り替え
  void setRuleEnabled(String ruleId, bool enabled) {
    final rule = _rules[ruleId];
    if (rule != null) {
      _rules[ruleId] = rule.copyWith(enabled: enabled);
    }
  }

  /// リソース解放
  void dispose() {
    _eventController.close();
    _patternMatcher.clearCache();
  }
}

/// マッチ履歴
class _MatchHistory {
  final String connectionId;
  final DateTime lastMatchTime;
  final String lastMatchedText;

  const _MatchHistory({
    required this.connectionId,
    required this.lastMatchTime,
    required this.lastMatchedText,
  });
}

/// 通知アクション実行サービス
class NotificationActionExecutor {
  /// 通知アクションを実行
  Future<void> execute(
    NotificationEvent event,
    List<NotificationAction> actions,
  ) async {
    for (final action in actions) {
      switch (action) {
        case NotificationAction.inApp:
          // アプリ内通知（上位レイヤーで処理）
          debugPrint('NotificationActionExecutor: In-app notification');
        case NotificationAction.sound:
          await _playSound();
        case NotificationAction.vibrate:
          await _vibrate();
      }
    }
  }

  Future<void> _playSound() async {
    // TODO: flutter_localnotificationsやaudioplayersで実装
    debugPrint('NotificationActionExecutor: Play sound');
  }

  Future<void> _vibrate() async {
    // TODO: vibrateパッケージで実装
    debugPrint('NotificationActionExecutor: Vibrate');
  }
}
