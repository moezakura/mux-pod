// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'notification_rule.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

NotificationCondition _$NotificationConditionFromJson(
    Map<String, dynamic> json) {
  return _NotificationCondition.fromJson(json);
}

/// @nodoc
mixin _$NotificationCondition {
  /// パターン文字列
  String get pattern => throw _privateConstructorUsedError;

  /// パターンタイプ
  PatternType get patternType => throw _privateConstructorUsedError;

  /// 大文字小文字を区別するか
  bool get caseSensitive => throw _privateConstructorUsedError;

  /// 否定条件（パターンにマッチしない場合に発火）
  bool get negate => throw _privateConstructorUsedError;

  /// Serializes this NotificationCondition to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of NotificationCondition
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NotificationConditionCopyWith<NotificationCondition> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NotificationConditionCopyWith<$Res> {
  factory $NotificationConditionCopyWith(NotificationCondition value,
          $Res Function(NotificationCondition) then) =
      _$NotificationConditionCopyWithImpl<$Res, NotificationCondition>;
  @useResult
  $Res call(
      {String pattern,
      PatternType patternType,
      bool caseSensitive,
      bool negate});
}

/// @nodoc
class _$NotificationConditionCopyWithImpl<$Res,
        $Val extends NotificationCondition>
    implements $NotificationConditionCopyWith<$Res> {
  _$NotificationConditionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of NotificationCondition
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pattern = null,
    Object? patternType = null,
    Object? caseSensitive = null,
    Object? negate = null,
  }) {
    return _then(_value.copyWith(
      pattern: null == pattern
          ? _value.pattern
          : pattern // ignore: cast_nullable_to_non_nullable
              as String,
      patternType: null == patternType
          ? _value.patternType
          : patternType // ignore: cast_nullable_to_non_nullable
              as PatternType,
      caseSensitive: null == caseSensitive
          ? _value.caseSensitive
          : caseSensitive // ignore: cast_nullable_to_non_nullable
              as bool,
      negate: null == negate
          ? _value.negate
          : negate // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$NotificationConditionImplCopyWith<$Res>
    implements $NotificationConditionCopyWith<$Res> {
  factory _$$NotificationConditionImplCopyWith(
          _$NotificationConditionImpl value,
          $Res Function(_$NotificationConditionImpl) then) =
      __$$NotificationConditionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String pattern,
      PatternType patternType,
      bool caseSensitive,
      bool negate});
}

/// @nodoc
class __$$NotificationConditionImplCopyWithImpl<$Res>
    extends _$NotificationConditionCopyWithImpl<$Res,
        _$NotificationConditionImpl>
    implements _$$NotificationConditionImplCopyWith<$Res> {
  __$$NotificationConditionImplCopyWithImpl(_$NotificationConditionImpl _value,
      $Res Function(_$NotificationConditionImpl) _then)
      : super(_value, _then);

  /// Create a copy of NotificationCondition
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pattern = null,
    Object? patternType = null,
    Object? caseSensitive = null,
    Object? negate = null,
  }) {
    return _then(_$NotificationConditionImpl(
      pattern: null == pattern
          ? _value.pattern
          : pattern // ignore: cast_nullable_to_non_nullable
              as String,
      patternType: null == patternType
          ? _value.patternType
          : patternType // ignore: cast_nullable_to_non_nullable
              as PatternType,
      caseSensitive: null == caseSensitive
          ? _value.caseSensitive
          : caseSensitive // ignore: cast_nullable_to_non_nullable
              as bool,
      negate: null == negate
          ? _value.negate
          : negate // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$NotificationConditionImpl
    with DiagnosticableTreeMixin
    implements _NotificationCondition {
  const _$NotificationConditionImpl(
      {required this.pattern,
      this.patternType = PatternType.text,
      this.caseSensitive = false,
      this.negate = false});

  factory _$NotificationConditionImpl.fromJson(Map<String, dynamic> json) =>
      _$$NotificationConditionImplFromJson(json);

  /// パターン文字列
  @override
  final String pattern;

  /// パターンタイプ
  @override
  @JsonKey()
  final PatternType patternType;

  /// 大文字小文字を区別するか
  @override
  @JsonKey()
  final bool caseSensitive;

  /// 否定条件（パターンにマッチしない場合に発火）
  @override
  @JsonKey()
  final bool negate;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'NotificationCondition(pattern: $pattern, patternType: $patternType, caseSensitive: $caseSensitive, negate: $negate)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'NotificationCondition'))
      ..add(DiagnosticsProperty('pattern', pattern))
      ..add(DiagnosticsProperty('patternType', patternType))
      ..add(DiagnosticsProperty('caseSensitive', caseSensitive))
      ..add(DiagnosticsProperty('negate', negate));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NotificationConditionImpl &&
            (identical(other.pattern, pattern) || other.pattern == pattern) &&
            (identical(other.patternType, patternType) ||
                other.patternType == patternType) &&
            (identical(other.caseSensitive, caseSensitive) ||
                other.caseSensitive == caseSensitive) &&
            (identical(other.negate, negate) || other.negate == negate));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, pattern, patternType, caseSensitive, negate);

  /// Create a copy of NotificationCondition
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NotificationConditionImplCopyWith<_$NotificationConditionImpl>
      get copyWith => __$$NotificationConditionImplCopyWithImpl<
          _$NotificationConditionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$NotificationConditionImplToJson(
      this,
    );
  }
}

abstract class _NotificationCondition implements NotificationCondition {
  const factory _NotificationCondition(
      {required final String pattern,
      final PatternType patternType,
      final bool caseSensitive,
      final bool negate}) = _$NotificationConditionImpl;

  factory _NotificationCondition.fromJson(Map<String, dynamic> json) =
      _$NotificationConditionImpl.fromJson;

  /// パターン文字列
  @override
  String get pattern;

  /// パターンタイプ
  @override
  PatternType get patternType;

  /// 大文字小文字を区別するか
  @override
  bool get caseSensitive;

  /// 否定条件（パターンにマッチしない場合に発火）
  @override
  bool get negate;

  /// Create a copy of NotificationCondition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NotificationConditionImplCopyWith<_$NotificationConditionImpl>
      get copyWith => throw _privateConstructorUsedError;
}

NotificationRule _$NotificationRuleFromJson(Map<String, dynamic> json) {
  return _NotificationRule.fromJson(json);
}

/// @nodoc
mixin _$NotificationRule {
  /// ルールID
  String get id => throw _privateConstructorUsedError;

  /// ルール名
  String get name => throw _privateConstructorUsedError;

  /// ルールの説明
  String? get description => throw _privateConstructorUsedError;

  /// 通知条件リスト（AND条件）
  List<NotificationCondition> get conditions =>
      throw _privateConstructorUsedError;

  /// 通知アクション
  List<NotificationAction> get actions => throw _privateConstructorUsedError;

  /// 通知頻度
  NotificationFrequency get frequency => throw _privateConstructorUsedError;

  /// ルールのスコープ
  RuleScope get scope => throw _privateConstructorUsedError;

  /// 対象の接続ID（scope == connection の場合）
  String? get connectionId => throw _privateConstructorUsedError;

  /// 対象のセッション名（scope == session の場合）
  String? get sessionName => throw _privateConstructorUsedError;

  /// ルールが有効か
  bool get enabled => throw _privateConstructorUsedError;

  /// 作成日時
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// 更新日時
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  /// 最後にマッチした日時
  DateTime? get lastMatchedAt => throw _privateConstructorUsedError;

  /// マッチ回数
  int get matchCount => throw _privateConstructorUsedError;

  /// Serializes this NotificationRule to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of NotificationRule
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NotificationRuleCopyWith<NotificationRule> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NotificationRuleCopyWith<$Res> {
  factory $NotificationRuleCopyWith(
          NotificationRule value, $Res Function(NotificationRule) then) =
      _$NotificationRuleCopyWithImpl<$Res, NotificationRule>;
  @useResult
  $Res call(
      {String id,
      String name,
      String? description,
      List<NotificationCondition> conditions,
      List<NotificationAction> actions,
      NotificationFrequency frequency,
      RuleScope scope,
      String? connectionId,
      String? sessionName,
      bool enabled,
      DateTime createdAt,
      DateTime? updatedAt,
      DateTime? lastMatchedAt,
      int matchCount});
}

/// @nodoc
class _$NotificationRuleCopyWithImpl<$Res, $Val extends NotificationRule>
    implements $NotificationRuleCopyWith<$Res> {
  _$NotificationRuleCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of NotificationRule
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? conditions = null,
    Object? actions = null,
    Object? frequency = null,
    Object? scope = null,
    Object? connectionId = freezed,
    Object? sessionName = freezed,
    Object? enabled = null,
    Object? createdAt = null,
    Object? updatedAt = freezed,
    Object? lastMatchedAt = freezed,
    Object? matchCount = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      conditions: null == conditions
          ? _value.conditions
          : conditions // ignore: cast_nullable_to_non_nullable
              as List<NotificationCondition>,
      actions: null == actions
          ? _value.actions
          : actions // ignore: cast_nullable_to_non_nullable
              as List<NotificationAction>,
      frequency: null == frequency
          ? _value.frequency
          : frequency // ignore: cast_nullable_to_non_nullable
              as NotificationFrequency,
      scope: null == scope
          ? _value.scope
          : scope // ignore: cast_nullable_to_non_nullable
              as RuleScope,
      connectionId: freezed == connectionId
          ? _value.connectionId
          : connectionId // ignore: cast_nullable_to_non_nullable
              as String?,
      sessionName: freezed == sessionName
          ? _value.sessionName
          : sessionName // ignore: cast_nullable_to_non_nullable
              as String?,
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastMatchedAt: freezed == lastMatchedAt
          ? _value.lastMatchedAt
          : lastMatchedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      matchCount: null == matchCount
          ? _value.matchCount
          : matchCount // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$NotificationRuleImplCopyWith<$Res>
    implements $NotificationRuleCopyWith<$Res> {
  factory _$$NotificationRuleImplCopyWith(_$NotificationRuleImpl value,
          $Res Function(_$NotificationRuleImpl) then) =
      __$$NotificationRuleImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String? description,
      List<NotificationCondition> conditions,
      List<NotificationAction> actions,
      NotificationFrequency frequency,
      RuleScope scope,
      String? connectionId,
      String? sessionName,
      bool enabled,
      DateTime createdAt,
      DateTime? updatedAt,
      DateTime? lastMatchedAt,
      int matchCount});
}

/// @nodoc
class __$$NotificationRuleImplCopyWithImpl<$Res>
    extends _$NotificationRuleCopyWithImpl<$Res, _$NotificationRuleImpl>
    implements _$$NotificationRuleImplCopyWith<$Res> {
  __$$NotificationRuleImplCopyWithImpl(_$NotificationRuleImpl _value,
      $Res Function(_$NotificationRuleImpl) _then)
      : super(_value, _then);

  /// Create a copy of NotificationRule
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? conditions = null,
    Object? actions = null,
    Object? frequency = null,
    Object? scope = null,
    Object? connectionId = freezed,
    Object? sessionName = freezed,
    Object? enabled = null,
    Object? createdAt = null,
    Object? updatedAt = freezed,
    Object? lastMatchedAt = freezed,
    Object? matchCount = null,
  }) {
    return _then(_$NotificationRuleImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      conditions: null == conditions
          ? _value._conditions
          : conditions // ignore: cast_nullable_to_non_nullable
              as List<NotificationCondition>,
      actions: null == actions
          ? _value._actions
          : actions // ignore: cast_nullable_to_non_nullable
              as List<NotificationAction>,
      frequency: null == frequency
          ? _value.frequency
          : frequency // ignore: cast_nullable_to_non_nullable
              as NotificationFrequency,
      scope: null == scope
          ? _value.scope
          : scope // ignore: cast_nullable_to_non_nullable
              as RuleScope,
      connectionId: freezed == connectionId
          ? _value.connectionId
          : connectionId // ignore: cast_nullable_to_non_nullable
              as String?,
      sessionName: freezed == sessionName
          ? _value.sessionName
          : sessionName // ignore: cast_nullable_to_non_nullable
              as String?,
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastMatchedAt: freezed == lastMatchedAt
          ? _value.lastMatchedAt
          : lastMatchedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      matchCount: null == matchCount
          ? _value.matchCount
          : matchCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$NotificationRuleImpl extends _NotificationRule
    with DiagnosticableTreeMixin {
  const _$NotificationRuleImpl(
      {required this.id,
      required this.name,
      this.description,
      required final List<NotificationCondition> conditions,
      final List<NotificationAction> actions = const [NotificationAction.inApp],
      this.frequency = NotificationFrequency.always,
      this.scope = RuleScope.global,
      this.connectionId,
      this.sessionName,
      this.enabled = true,
      required this.createdAt,
      this.updatedAt,
      this.lastMatchedAt,
      this.matchCount = 0})
      : _conditions = conditions,
        _actions = actions,
        super._();

  factory _$NotificationRuleImpl.fromJson(Map<String, dynamic> json) =>
      _$$NotificationRuleImplFromJson(json);

  /// ルールID
  @override
  final String id;

  /// ルール名
  @override
  final String name;

  /// ルールの説明
  @override
  final String? description;

  /// 通知条件リスト（AND条件）
  final List<NotificationCondition> _conditions;

  /// 通知条件リスト（AND条件）
  @override
  List<NotificationCondition> get conditions {
    if (_conditions is EqualUnmodifiableListView) return _conditions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_conditions);
  }

  /// 通知アクション
  final List<NotificationAction> _actions;

  /// 通知アクション
  @override
  @JsonKey()
  List<NotificationAction> get actions {
    if (_actions is EqualUnmodifiableListView) return _actions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_actions);
  }

  /// 通知頻度
  @override
  @JsonKey()
  final NotificationFrequency frequency;

  /// ルールのスコープ
  @override
  @JsonKey()
  final RuleScope scope;

  /// 対象の接続ID（scope == connection の場合）
  @override
  final String? connectionId;

  /// 対象のセッション名（scope == session の場合）
  @override
  final String? sessionName;

  /// ルールが有効か
  @override
  @JsonKey()
  final bool enabled;

  /// 作成日時
  @override
  final DateTime createdAt;

  /// 更新日時
  @override
  final DateTime? updatedAt;

  /// 最後にマッチした日時
  @override
  final DateTime? lastMatchedAt;

  /// マッチ回数
  @override
  @JsonKey()
  final int matchCount;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'NotificationRule(id: $id, name: $name, description: $description, conditions: $conditions, actions: $actions, frequency: $frequency, scope: $scope, connectionId: $connectionId, sessionName: $sessionName, enabled: $enabled, createdAt: $createdAt, updatedAt: $updatedAt, lastMatchedAt: $lastMatchedAt, matchCount: $matchCount)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'NotificationRule'))
      ..add(DiagnosticsProperty('id', id))
      ..add(DiagnosticsProperty('name', name))
      ..add(DiagnosticsProperty('description', description))
      ..add(DiagnosticsProperty('conditions', conditions))
      ..add(DiagnosticsProperty('actions', actions))
      ..add(DiagnosticsProperty('frequency', frequency))
      ..add(DiagnosticsProperty('scope', scope))
      ..add(DiagnosticsProperty('connectionId', connectionId))
      ..add(DiagnosticsProperty('sessionName', sessionName))
      ..add(DiagnosticsProperty('enabled', enabled))
      ..add(DiagnosticsProperty('createdAt', createdAt))
      ..add(DiagnosticsProperty('updatedAt', updatedAt))
      ..add(DiagnosticsProperty('lastMatchedAt', lastMatchedAt))
      ..add(DiagnosticsProperty('matchCount', matchCount));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NotificationRuleImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            const DeepCollectionEquality()
                .equals(other._conditions, _conditions) &&
            const DeepCollectionEquality().equals(other._actions, _actions) &&
            (identical(other.frequency, frequency) ||
                other.frequency == frequency) &&
            (identical(other.scope, scope) || other.scope == scope) &&
            (identical(other.connectionId, connectionId) ||
                other.connectionId == connectionId) &&
            (identical(other.sessionName, sessionName) ||
                other.sessionName == sessionName) &&
            (identical(other.enabled, enabled) || other.enabled == enabled) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.lastMatchedAt, lastMatchedAt) ||
                other.lastMatchedAt == lastMatchedAt) &&
            (identical(other.matchCount, matchCount) ||
                other.matchCount == matchCount));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      const DeepCollectionEquality().hash(_conditions),
      const DeepCollectionEquality().hash(_actions),
      frequency,
      scope,
      connectionId,
      sessionName,
      enabled,
      createdAt,
      updatedAt,
      lastMatchedAt,
      matchCount);

  /// Create a copy of NotificationRule
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NotificationRuleImplCopyWith<_$NotificationRuleImpl> get copyWith =>
      __$$NotificationRuleImplCopyWithImpl<_$NotificationRuleImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$NotificationRuleImplToJson(
      this,
    );
  }
}

abstract class _NotificationRule extends NotificationRule {
  const factory _NotificationRule(
      {required final String id,
      required final String name,
      final String? description,
      required final List<NotificationCondition> conditions,
      final List<NotificationAction> actions,
      final NotificationFrequency frequency,
      final RuleScope scope,
      final String? connectionId,
      final String? sessionName,
      final bool enabled,
      required final DateTime createdAt,
      final DateTime? updatedAt,
      final DateTime? lastMatchedAt,
      final int matchCount}) = _$NotificationRuleImpl;
  const _NotificationRule._() : super._();

  factory _NotificationRule.fromJson(Map<String, dynamic> json) =
      _$NotificationRuleImpl.fromJson;

  /// ルールID
  @override
  String get id;

  /// ルール名
  @override
  String get name;

  /// ルールの説明
  @override
  String? get description;

  /// 通知条件リスト（AND条件）
  @override
  List<NotificationCondition> get conditions;

  /// 通知アクション
  @override
  List<NotificationAction> get actions;

  /// 通知頻度
  @override
  NotificationFrequency get frequency;

  /// ルールのスコープ
  @override
  RuleScope get scope;

  /// 対象の接続ID（scope == connection の場合）
  @override
  String? get connectionId;

  /// 対象のセッション名（scope == session の場合）
  @override
  String? get sessionName;

  /// ルールが有効か
  @override
  bool get enabled;

  /// 作成日時
  @override
  DateTime get createdAt;

  /// 更新日時
  @override
  DateTime? get updatedAt;

  /// 最後にマッチした日時
  @override
  DateTime? get lastMatchedAt;

  /// マッチ回数
  @override
  int get matchCount;

  /// Create a copy of NotificationRule
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NotificationRuleImplCopyWith<_$NotificationRuleImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

NotificationEvent _$NotificationEventFromJson(Map<String, dynamic> json) {
  return _NotificationEvent.fromJson(json);
}

/// @nodoc
mixin _$NotificationEvent {
  /// イベントID
  String get id => throw _privateConstructorUsedError;

  /// マッチしたルールID
  String get ruleId => throw _privateConstructorUsedError;

  /// マッチしたルール名
  String get ruleName => throw _privateConstructorUsedError;

  /// 接続ID
  String get connectionId => throw _privateConstructorUsedError;

  /// 接続名
  String get connectionName => throw _privateConstructorUsedError;

  /// セッション名
  String? get sessionName => throw _privateConstructorUsedError;

  /// ウィンドウ名
  String? get windowName => throw _privateConstructorUsedError;

  /// ペインインデックス
  int? get paneIndex => throw _privateConstructorUsedError;

  /// マッチしたテキスト
  String get matchedText => throw _privateConstructorUsedError;

  /// マッチしたパターン
  String get pattern => throw _privateConstructorUsedError;

  /// 発生日時
  DateTime get timestamp => throw _privateConstructorUsedError;

  /// 既読か
  bool get read => throw _privateConstructorUsedError;

  /// 消音されたか
  bool get dismissed => throw _privateConstructorUsedError;

  /// Serializes this NotificationEvent to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of NotificationEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NotificationEventCopyWith<NotificationEvent> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NotificationEventCopyWith<$Res> {
  factory $NotificationEventCopyWith(
          NotificationEvent value, $Res Function(NotificationEvent) then) =
      _$NotificationEventCopyWithImpl<$Res, NotificationEvent>;
  @useResult
  $Res call(
      {String id,
      String ruleId,
      String ruleName,
      String connectionId,
      String connectionName,
      String? sessionName,
      String? windowName,
      int? paneIndex,
      String matchedText,
      String pattern,
      DateTime timestamp,
      bool read,
      bool dismissed});
}

/// @nodoc
class _$NotificationEventCopyWithImpl<$Res, $Val extends NotificationEvent>
    implements $NotificationEventCopyWith<$Res> {
  _$NotificationEventCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of NotificationEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? ruleId = null,
    Object? ruleName = null,
    Object? connectionId = null,
    Object? connectionName = null,
    Object? sessionName = freezed,
    Object? windowName = freezed,
    Object? paneIndex = freezed,
    Object? matchedText = null,
    Object? pattern = null,
    Object? timestamp = null,
    Object? read = null,
    Object? dismissed = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      ruleId: null == ruleId
          ? _value.ruleId
          : ruleId // ignore: cast_nullable_to_non_nullable
              as String,
      ruleName: null == ruleName
          ? _value.ruleName
          : ruleName // ignore: cast_nullable_to_non_nullable
              as String,
      connectionId: null == connectionId
          ? _value.connectionId
          : connectionId // ignore: cast_nullable_to_non_nullable
              as String,
      connectionName: null == connectionName
          ? _value.connectionName
          : connectionName // ignore: cast_nullable_to_non_nullable
              as String,
      sessionName: freezed == sessionName
          ? _value.sessionName
          : sessionName // ignore: cast_nullable_to_non_nullable
              as String?,
      windowName: freezed == windowName
          ? _value.windowName
          : windowName // ignore: cast_nullable_to_non_nullable
              as String?,
      paneIndex: freezed == paneIndex
          ? _value.paneIndex
          : paneIndex // ignore: cast_nullable_to_non_nullable
              as int?,
      matchedText: null == matchedText
          ? _value.matchedText
          : matchedText // ignore: cast_nullable_to_non_nullable
              as String,
      pattern: null == pattern
          ? _value.pattern
          : pattern // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      read: null == read
          ? _value.read
          : read // ignore: cast_nullable_to_non_nullable
              as bool,
      dismissed: null == dismissed
          ? _value.dismissed
          : dismissed // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$NotificationEventImplCopyWith<$Res>
    implements $NotificationEventCopyWith<$Res> {
  factory _$$NotificationEventImplCopyWith(_$NotificationEventImpl value,
          $Res Function(_$NotificationEventImpl) then) =
      __$$NotificationEventImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String ruleId,
      String ruleName,
      String connectionId,
      String connectionName,
      String? sessionName,
      String? windowName,
      int? paneIndex,
      String matchedText,
      String pattern,
      DateTime timestamp,
      bool read,
      bool dismissed});
}

/// @nodoc
class __$$NotificationEventImplCopyWithImpl<$Res>
    extends _$NotificationEventCopyWithImpl<$Res, _$NotificationEventImpl>
    implements _$$NotificationEventImplCopyWith<$Res> {
  __$$NotificationEventImplCopyWithImpl(_$NotificationEventImpl _value,
      $Res Function(_$NotificationEventImpl) _then)
      : super(_value, _then);

  /// Create a copy of NotificationEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? ruleId = null,
    Object? ruleName = null,
    Object? connectionId = null,
    Object? connectionName = null,
    Object? sessionName = freezed,
    Object? windowName = freezed,
    Object? paneIndex = freezed,
    Object? matchedText = null,
    Object? pattern = null,
    Object? timestamp = null,
    Object? read = null,
    Object? dismissed = null,
  }) {
    return _then(_$NotificationEventImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      ruleId: null == ruleId
          ? _value.ruleId
          : ruleId // ignore: cast_nullable_to_non_nullable
              as String,
      ruleName: null == ruleName
          ? _value.ruleName
          : ruleName // ignore: cast_nullable_to_non_nullable
              as String,
      connectionId: null == connectionId
          ? _value.connectionId
          : connectionId // ignore: cast_nullable_to_non_nullable
              as String,
      connectionName: null == connectionName
          ? _value.connectionName
          : connectionName // ignore: cast_nullable_to_non_nullable
              as String,
      sessionName: freezed == sessionName
          ? _value.sessionName
          : sessionName // ignore: cast_nullable_to_non_nullable
              as String?,
      windowName: freezed == windowName
          ? _value.windowName
          : windowName // ignore: cast_nullable_to_non_nullable
              as String?,
      paneIndex: freezed == paneIndex
          ? _value.paneIndex
          : paneIndex // ignore: cast_nullable_to_non_nullable
              as int?,
      matchedText: null == matchedText
          ? _value.matchedText
          : matchedText // ignore: cast_nullable_to_non_nullable
              as String,
      pattern: null == pattern
          ? _value.pattern
          : pattern // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      read: null == read
          ? _value.read
          : read // ignore: cast_nullable_to_non_nullable
              as bool,
      dismissed: null == dismissed
          ? _value.dismissed
          : dismissed // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$NotificationEventImpl
    with DiagnosticableTreeMixin
    implements _NotificationEvent {
  const _$NotificationEventImpl(
      {required this.id,
      required this.ruleId,
      required this.ruleName,
      required this.connectionId,
      required this.connectionName,
      this.sessionName,
      this.windowName,
      this.paneIndex,
      required this.matchedText,
      required this.pattern,
      required this.timestamp,
      this.read = false,
      this.dismissed = false});

  factory _$NotificationEventImpl.fromJson(Map<String, dynamic> json) =>
      _$$NotificationEventImplFromJson(json);

  /// イベントID
  @override
  final String id;

  /// マッチしたルールID
  @override
  final String ruleId;

  /// マッチしたルール名
  @override
  final String ruleName;

  /// 接続ID
  @override
  final String connectionId;

  /// 接続名
  @override
  final String connectionName;

  /// セッション名
  @override
  final String? sessionName;

  /// ウィンドウ名
  @override
  final String? windowName;

  /// ペインインデックス
  @override
  final int? paneIndex;

  /// マッチしたテキスト
  @override
  final String matchedText;

  /// マッチしたパターン
  @override
  final String pattern;

  /// 発生日時
  @override
  final DateTime timestamp;

  /// 既読か
  @override
  @JsonKey()
  final bool read;

  /// 消音されたか
  @override
  @JsonKey()
  final bool dismissed;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'NotificationEvent(id: $id, ruleId: $ruleId, ruleName: $ruleName, connectionId: $connectionId, connectionName: $connectionName, sessionName: $sessionName, windowName: $windowName, paneIndex: $paneIndex, matchedText: $matchedText, pattern: $pattern, timestamp: $timestamp, read: $read, dismissed: $dismissed)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'NotificationEvent'))
      ..add(DiagnosticsProperty('id', id))
      ..add(DiagnosticsProperty('ruleId', ruleId))
      ..add(DiagnosticsProperty('ruleName', ruleName))
      ..add(DiagnosticsProperty('connectionId', connectionId))
      ..add(DiagnosticsProperty('connectionName', connectionName))
      ..add(DiagnosticsProperty('sessionName', sessionName))
      ..add(DiagnosticsProperty('windowName', windowName))
      ..add(DiagnosticsProperty('paneIndex', paneIndex))
      ..add(DiagnosticsProperty('matchedText', matchedText))
      ..add(DiagnosticsProperty('pattern', pattern))
      ..add(DiagnosticsProperty('timestamp', timestamp))
      ..add(DiagnosticsProperty('read', read))
      ..add(DiagnosticsProperty('dismissed', dismissed));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NotificationEventImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.ruleId, ruleId) || other.ruleId == ruleId) &&
            (identical(other.ruleName, ruleName) ||
                other.ruleName == ruleName) &&
            (identical(other.connectionId, connectionId) ||
                other.connectionId == connectionId) &&
            (identical(other.connectionName, connectionName) ||
                other.connectionName == connectionName) &&
            (identical(other.sessionName, sessionName) ||
                other.sessionName == sessionName) &&
            (identical(other.windowName, windowName) ||
                other.windowName == windowName) &&
            (identical(other.paneIndex, paneIndex) ||
                other.paneIndex == paneIndex) &&
            (identical(other.matchedText, matchedText) ||
                other.matchedText == matchedText) &&
            (identical(other.pattern, pattern) || other.pattern == pattern) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.read, read) || other.read == read) &&
            (identical(other.dismissed, dismissed) ||
                other.dismissed == dismissed));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      ruleId,
      ruleName,
      connectionId,
      connectionName,
      sessionName,
      windowName,
      paneIndex,
      matchedText,
      pattern,
      timestamp,
      read,
      dismissed);

  /// Create a copy of NotificationEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NotificationEventImplCopyWith<_$NotificationEventImpl> get copyWith =>
      __$$NotificationEventImplCopyWithImpl<_$NotificationEventImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$NotificationEventImplToJson(
      this,
    );
  }
}

abstract class _NotificationEvent implements NotificationEvent {
  const factory _NotificationEvent(
      {required final String id,
      required final String ruleId,
      required final String ruleName,
      required final String connectionId,
      required final String connectionName,
      final String? sessionName,
      final String? windowName,
      final int? paneIndex,
      required final String matchedText,
      required final String pattern,
      required final DateTime timestamp,
      final bool read,
      final bool dismissed}) = _$NotificationEventImpl;

  factory _NotificationEvent.fromJson(Map<String, dynamic> json) =
      _$NotificationEventImpl.fromJson;

  /// イベントID
  @override
  String get id;

  /// マッチしたルールID
  @override
  String get ruleId;

  /// マッチしたルール名
  @override
  String get ruleName;

  /// 接続ID
  @override
  String get connectionId;

  /// 接続名
  @override
  String get connectionName;

  /// セッション名
  @override
  String? get sessionName;

  /// ウィンドウ名
  @override
  String? get windowName;

  /// ペインインデックス
  @override
  int? get paneIndex;

  /// マッチしたテキスト
  @override
  String get matchedText;

  /// マッチしたパターン
  @override
  String get pattern;

  /// 発生日時
  @override
  DateTime get timestamp;

  /// 既読か
  @override
  bool get read;

  /// 消音されたか
  @override
  bool get dismissed;

  /// Create a copy of NotificationEvent
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NotificationEventImplCopyWith<_$NotificationEventImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
