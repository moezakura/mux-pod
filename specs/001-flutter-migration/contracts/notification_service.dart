/// Notification Service Contract
///
/// 通知ルール管理とマッチング処理のサービス層インターフェース。

import 'dart:async';

import '../models/notification_rule.dart';

/// 通知イベント
class NotificationEvent {
  final String ruleId;
  final String ruleName;
  final String connectionId;
  final String? sessionName;
  final int? windowIndex;
  final int? paneIndex;
  final String matchedText;
  final DateTime timestamp;

  const NotificationEvent({
    required this.ruleId,
    required this.ruleName,
    required this.connectionId,
    this.sessionName,
    this.windowIndex,
    this.paneIndex,
    required this.matchedText,
    required this.timestamp,
  });
}

/// 通知サービスインターフェース
abstract class NotificationService {
  /// 通知イベントストリーム
  Stream<NotificationEvent> get notifications;

  /// ルール一覧取得
  Future<List<NotificationRule>> listRules();

  /// ルール取得
  Future<NotificationRule?> getRule(String ruleId);

  /// ルール作成
  Future<NotificationRule> createRule(NotificationRule rule);

  /// ルール更新
  Future<void> updateRule(NotificationRule rule);

  /// ルール削除
  Future<void> deleteRule(String ruleId);

  /// ルール有効/無効切り替え
  Future<void> toggleRule({
    required String ruleId,
    required bool enabled,
  });

  /// 出力チェック（内部呼び出し用）
  void checkOutput({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
    required String output,
  });

  /// セッションリセット（once_per_session用）
  void resetSession(String connectionId);

  /// 通知履歴取得
  Future<List<NotificationEvent>> getHistory({
    int limit = 50,
    String? connectionId,
  });

  /// 通知履歴クリア
  Future<void> clearHistory();
}
