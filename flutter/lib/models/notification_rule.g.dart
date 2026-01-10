// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_rule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$NotificationConditionImpl _$$NotificationConditionImplFromJson(
        Map<String, dynamic> json) =>
    _$NotificationConditionImpl(
      pattern: json['pattern'] as String,
      patternType:
          $enumDecodeNullable(_$PatternTypeEnumMap, json['patternType']) ??
              PatternType.text,
      caseSensitive: json['caseSensitive'] as bool? ?? false,
      negate: json['negate'] as bool? ?? false,
    );

Map<String, dynamic> _$$NotificationConditionImplToJson(
        _$NotificationConditionImpl instance) =>
    <String, dynamic>{
      'pattern': instance.pattern,
      'patternType': _$PatternTypeEnumMap[instance.patternType]!,
      'caseSensitive': instance.caseSensitive,
      'negate': instance.negate,
    };

const _$PatternTypeEnumMap = {
  PatternType.text: 'text',
  PatternType.regex: 'regex',
  PatternType.wildcard: 'wildcard',
};

_$NotificationRuleImpl _$$NotificationRuleImplFromJson(
        Map<String, dynamic> json) =>
    _$NotificationRuleImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      conditions: (json['conditions'] as List<dynamic>)
          .map((e) => NotificationCondition.fromJson(e as Map<String, dynamic>))
          .toList(),
      actions: (json['actions'] as List<dynamic>?)
              ?.map((e) => $enumDecode(_$NotificationActionEnumMap, e))
              .toList() ??
          const [NotificationAction.inApp],
      frequency: $enumDecodeNullable(
              _$NotificationFrequencyEnumMap, json['frequency']) ??
          NotificationFrequency.always,
      scope: $enumDecodeNullable(_$RuleScopeEnumMap, json['scope']) ??
          RuleScope.global,
      connectionId: json['connectionId'] as String?,
      sessionName: json['sessionName'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      lastMatchedAt: json['lastMatchedAt'] == null
          ? null
          : DateTime.parse(json['lastMatchedAt'] as String),
      matchCount: (json['matchCount'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$NotificationRuleImplToJson(
        _$NotificationRuleImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'conditions': instance.conditions,
      'actions':
          instance.actions.map((e) => _$NotificationActionEnumMap[e]!).toList(),
      'frequency': _$NotificationFrequencyEnumMap[instance.frequency]!,
      'scope': _$RuleScopeEnumMap[instance.scope]!,
      'connectionId': instance.connectionId,
      'sessionName': instance.sessionName,
      'enabled': instance.enabled,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'lastMatchedAt': instance.lastMatchedAt?.toIso8601String(),
      'matchCount': instance.matchCount,
    };

const _$NotificationActionEnumMap = {
  NotificationAction.inApp: 'inApp',
  NotificationAction.sound: 'sound',
  NotificationAction.vibrate: 'vibrate',
};

const _$NotificationFrequencyEnumMap = {
  NotificationFrequency.always: 'always',
  NotificationFrequency.oncePerSession: 'oncePerSession',
  NotificationFrequency.oncePerMatch: 'oncePerMatch',
};

const _$RuleScopeEnumMap = {
  RuleScope.global: 'global',
  RuleScope.connection: 'connection',
  RuleScope.session: 'session',
};

_$NotificationEventImpl _$$NotificationEventImplFromJson(
        Map<String, dynamic> json) =>
    _$NotificationEventImpl(
      id: json['id'] as String,
      ruleId: json['ruleId'] as String,
      ruleName: json['ruleName'] as String,
      connectionId: json['connectionId'] as String,
      connectionName: json['connectionName'] as String,
      sessionName: json['sessionName'] as String?,
      windowName: json['windowName'] as String?,
      paneIndex: (json['paneIndex'] as num?)?.toInt(),
      matchedText: json['matchedText'] as String,
      pattern: json['pattern'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      read: json['read'] as bool? ?? false,
      dismissed: json['dismissed'] as bool? ?? false,
    );

Map<String, dynamic> _$$NotificationEventImplToJson(
        _$NotificationEventImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'ruleId': instance.ruleId,
      'ruleName': instance.ruleName,
      'connectionId': instance.connectionId,
      'connectionName': instance.connectionName,
      'sessionName': instance.sessionName,
      'windowName': instance.windowName,
      'paneIndex': instance.paneIndex,
      'matchedText': instance.matchedText,
      'pattern': instance.pattern,
      'timestamp': instance.timestamp.toIso8601String(),
      'read': instance.read,
      'dismissed': instance.dismissed,
    };
