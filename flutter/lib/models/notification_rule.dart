import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

import 'enums.dart';

part 'notification_rule.freezed.dart';
part 'notification_rule.g.dart';

/// 通知ルールのパターンタイプ
enum PatternType {
  /// テキスト完全一致
  text,

  /// 正規表現
  regex,

  /// ワイルドカード（*, ?）
  wildcard,
}

/// 通知ルールのスコープ
enum RuleScope {
  /// 全ての接続に適用
  global,

  /// 特定の接続のみ
  connection,

  /// 特定のセッションのみ
  session,
}

/// 通知条件
@freezed
class NotificationCondition with _$NotificationCondition {
  const factory NotificationCondition({
    /// パターン文字列
    required String pattern,

    /// パターンタイプ
    @Default(PatternType.text) PatternType patternType,

    /// 大文字小文字を区別するか
    @Default(false) bool caseSensitive,

    /// 否定条件（パターンにマッチしない場合に発火）
    @Default(false) bool negate,
  }) = _NotificationCondition;

  factory NotificationCondition.fromJson(Map<String, dynamic> json) =>
      _$NotificationConditionFromJson(json);
}

/// 通知ルール
@freezed
class NotificationRule with _$NotificationRule {
  const NotificationRule._();

  const factory NotificationRule({
    /// ルールID
    required String id,

    /// ルール名
    required String name,

    /// ルールの説明
    String? description,

    /// 通知条件リスト（AND条件）
    required List<NotificationCondition> conditions,

    /// 通知アクション
    @Default([NotificationAction.inApp]) List<NotificationAction> actions,

    /// 通知頻度
    @Default(NotificationFrequency.always) NotificationFrequency frequency,

    /// ルールのスコープ
    @Default(RuleScope.global) RuleScope scope,

    /// 対象の接続ID（scope == connection の場合）
    String? connectionId,

    /// 対象のセッション名（scope == session の場合）
    String? sessionName,

    /// ルールが有効か
    @Default(true) bool enabled,

    /// 作成日時
    required DateTime createdAt,

    /// 更新日時
    DateTime? updatedAt,

    /// 最後にマッチした日時
    DateTime? lastMatchedAt,

    /// マッチ回数
    @Default(0) int matchCount,
  }) = _NotificationRule;

  factory NotificationRule.fromJson(Map<String, dynamic> json) =>
      _$NotificationRuleFromJson(json);

  /// 簡易作成用ファクトリ
  factory NotificationRule.simple({
    required String id,
    required String name,
    required String pattern,
    PatternType patternType = PatternType.text,
    List<NotificationAction> actions = const [NotificationAction.inApp],
    NotificationFrequency frequency = NotificationFrequency.always,
  }) {
    return NotificationRule(
      id: id,
      name: name,
      conditions: [
        NotificationCondition(
          pattern: pattern,
          patternType: patternType,
        ),
      ],
      actions: actions,
      frequency: frequency,
      createdAt: DateTime.now(),
    );
  }
}

/// 通知イベント（マッチ発生時のイベント）
@freezed
class NotificationEvent with _$NotificationEvent {
  const factory NotificationEvent({
    /// イベントID
    required String id,

    /// マッチしたルールID
    required String ruleId,

    /// マッチしたルール名
    required String ruleName,

    /// 接続ID
    required String connectionId,

    /// 接続名
    required String connectionName,

    /// セッション名
    String? sessionName,

    /// ウィンドウ名
    String? windowName,

    /// ペインインデックス
    int? paneIndex,

    /// マッチしたテキスト
    required String matchedText,

    /// マッチしたパターン
    required String pattern,

    /// 発生日時
    required DateTime timestamp,

    /// 既読か
    @Default(false) bool read,

    /// 消音されたか
    @Default(false) bool dismissed,
  }) = _NotificationEvent;

  factory NotificationEvent.fromJson(Map<String, dynamic> json) =>
      _$NotificationEventFromJson(json);
}
