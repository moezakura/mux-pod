import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pattern_matcher.dart';

/// 通知の優先度
enum NotificationPriority {
  low,
  normal,
  high,
  urgent,
}

/// 通知ルール
class NotificationRule {
  /// ルールID
  final String id;

  /// ルール名
  final String name;

  /// マッチパターン
  final String pattern;

  /// 正規表現かどうか
  final bool isRegex;

  /// 有効かどうか
  final bool enabled;

  /// 大文字小文字を区別するか
  final bool caseSensitive;

  /// サウンドファイル名（nullでデフォルト）
  final String? sound;

  /// バイブレーションするか
  final bool vibrate;

  /// 優先度
  final NotificationPriority priority;

  /// 対象セッション（nullですべて）
  final String? targetSession;

  /// レート制限（秒）- 同じルールの通知間隔
  final int rateLimitSeconds;

  /// 作成日時
  final DateTime createdAt;

  /// 最終マッチ日時
  DateTime? lastMatchedAt;

  NotificationRule({
    required this.id,
    required this.name,
    required this.pattern,
    this.isRegex = false,
    this.enabled = true,
    this.caseSensitive = false,
    this.sound,
    this.vibrate = true,
    this.priority = NotificationPriority.normal,
    this.targetSession,
    this.rateLimitSeconds = 5,
    DateTime? createdAt,
    this.lastMatchedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  NotificationRule copyWith({
    String? id,
    String? name,
    String? pattern,
    bool? isRegex,
    bool? enabled,
    bool? caseSensitive,
    String? sound,
    bool? vibrate,
    NotificationPriority? priority,
    String? targetSession,
    int? rateLimitSeconds,
    DateTime? createdAt,
    DateTime? lastMatchedAt,
  }) {
    return NotificationRule(
      id: id ?? this.id,
      name: name ?? this.name,
      pattern: pattern ?? this.pattern,
      isRegex: isRegex ?? this.isRegex,
      enabled: enabled ?? this.enabled,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      sound: sound ?? this.sound,
      vibrate: vibrate ?? this.vibrate,
      priority: priority ?? this.priority,
      targetSession: targetSession ?? this.targetSession,
      rateLimitSeconds: rateLimitSeconds ?? this.rateLimitSeconds,
      createdAt: createdAt ?? this.createdAt,
      lastMatchedAt: lastMatchedAt ?? this.lastMatchedAt,
    );
  }

  /// JSONに変換
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'pattern': pattern,
      'isRegex': isRegex,
      'enabled': enabled,
      'caseSensitive': caseSensitive,
      'sound': sound,
      'vibrate': vibrate,
      'priority': priority.index,
      'targetSession': targetSession,
      'rateLimitSeconds': rateLimitSeconds,
      'createdAt': createdAt.toIso8601String(),
      'lastMatchedAt': lastMatchedAt?.toIso8601String(),
    };
  }

  /// JSONから生成
  factory NotificationRule.fromJson(Map<String, dynamic> json) {
    return NotificationRule(
      id: json['id'] as String,
      name: json['name'] as String,
      pattern: json['pattern'] as String,
      isRegex: json['isRegex'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
      caseSensitive: json['caseSensitive'] as bool? ?? false,
      sound: json['sound'] as String?,
      vibrate: json['vibrate'] as bool? ?? true,
      priority: NotificationPriority.values[json['priority'] as int? ?? 1],
      targetSession: json['targetSession'] as String?,
      rateLimitSeconds: json['rateLimitSeconds'] as int? ?? 5,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastMatchedAt: json['lastMatchedAt'] != null
          ? DateTime.parse(json['lastMatchedAt'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationRule &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 通知イベント
class NotificationEvent {
  /// 発火したルール
  final NotificationRule rule;

  /// マッチ結果
  final MatchResult matchResult;

  /// セッション名
  final String? sessionName;

  /// ウィンドウ名
  final String? windowName;

  /// ペインID
  final String? paneId;

  /// 発生日時
  final DateTime timestamp;

  const NotificationEvent({
    required this.rule,
    required this.matchResult,
    this.sessionName,
    this.windowName,
    this.paneId,
    required this.timestamp,
  });
}

/// 通知エンジン
///
/// パターンマッチングによる通知機能を提供する。
class NotificationEngine {
  final List<NotificationRule> _rules = [];
  final FlutterLocalNotificationsPlugin _notifications;
  final StreamController<NotificationEvent> _eventController;

  /// グローバルに通知が有効かどうか
  bool globalEnabled = true;

  /// 通知コールバック（システム通知とは別に処理したい場合）
  void Function(NotificationEvent event)? onNotification;

  /// SharedPreferencesのキー
  static const String _rulesStorageKey = 'notification_rules';

  /// 通知チャンネルID
  static const String _channelId = 'muxpod_notifications';
  static const String _channelName = 'MuxPod Notifications';
  static const String _channelDescription = 'Pattern match notifications';

  /// 通知ID カウンター
  int _notificationIdCounter = 0;

  NotificationEngine({
    FlutterLocalNotificationsPlugin? notifications,
  })  : _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
        _eventController = StreamController<NotificationEvent>.broadcast();

  /// 通知イベントストリーム
  Stream<NotificationEvent> get events => _eventController.stream;

  /// ルール一覧
  List<NotificationRule> get rules => List.unmodifiable(_rules);

  /// 有効なルール一覧
  List<NotificationRule> get enabledRules =>
      _rules.where((r) => r.enabled).toList();

  // ===== 初期化 =====

  /// 通知エンジンを初期化
  Future<void> initialize() async {
    // Android の初期化設定
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS の初期化設定
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    // Android 通知チャンネルを作成
    await _createNotificationChannel();

    // 保存されたルールを読み込み
    await loadRules();
  }

  /// 通知チャンネルを作成（Android用）
  Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 通知タップハンドラ
  void _handleNotificationTap(NotificationResponse response) {
    // 通知がタップされた時の処理
    // payload には通知の追加情報が含まれる
  }

  // ===== ルール管理 =====

  /// ルールを追加
  void addRule(NotificationRule rule) {
    // 既存のルールがある場合は更新
    final index = _rules.indexWhere((r) => r.id == rule.id);
    if (index >= 0) {
      _rules[index] = rule;
    } else {
      _rules.add(rule);
    }
  }

  /// ルールを削除
  void removeRule(String ruleId) {
    _rules.removeWhere((r) => r.id == ruleId);
  }

  /// ルールを更新
  void updateRule(NotificationRule rule) {
    final index = _rules.indexWhere((r) => r.id == rule.id);
    if (index >= 0) {
      _rules[index] = rule;
    }
  }

  /// ルールを取得
  NotificationRule? getRule(String ruleId) {
    try {
      return _rules.firstWhere((r) => r.id == ruleId);
    } catch (e) {
      return null;
    }
  }

  /// ルールの有効/無効を切り替え
  void toggleRule(String ruleId) {
    final rule = getRule(ruleId);
    if (rule != null) {
      updateRule(rule.copyWith(enabled: !rule.enabled));
    }
  }

  /// すべてのルールをクリア
  void clearRules() {
    _rules.clear();
  }

  /// ルールを並び替え
  void reorderRules(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final rule = _rules.removeAt(oldIndex);
    _rules.insert(newIndex, rule);
  }

  // ===== 永続化 =====

  /// ルールを保存
  Future<void> saveRules() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _rules.map((r) => r.toJson()).toList();
    await prefs.setString(_rulesStorageKey, jsonEncode(jsonList));
  }

  /// ルールを読み込み
  Future<void> loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_rulesStorageKey);

    if (jsonString != null) {
      try {
        final jsonList = jsonDecode(jsonString) as List<dynamic>;
        _rules.clear();
        _rules.addAll(
          jsonList.map((json) => NotificationRule.fromJson(json as Map<String, dynamic>)),
        );
      } catch (e) {
        // パースエラーの場合は空のリストのまま
      }
    }
  }

  // ===== テキスト処理 =====

  /// テキストを処理して通知をチェック
  ///
  /// [text] 処理するテキスト
  /// [sessionName] セッション名（フィルタリング用）
  /// [windowName] ウィンドウ名
  /// [paneId] ペインID
  Future<void> processText(
    String text, {
    String? sessionName,
    String? windowName,
    String? paneId,
  }) async {
    if (!globalEnabled || text.isEmpty) return;

    // ANSIコードを除去
    final plainText = PatternMatcher.stripAnsiCodes(text);

    for (final rule in _rules) {
      if (!rule.enabled) continue;

      // セッションフィルタ
      if (rule.targetSession != null &&
          rule.targetSession != sessionName) {
        continue;
      }

      // レート制限チェック
      if (rule.lastMatchedAt != null) {
        final elapsed = DateTime.now().difference(rule.lastMatchedAt!);
        if (elapsed.inSeconds < rule.rateLimitSeconds) {
          continue;
        }
      }

      // パターンマッチ
      final options = MatchOptions(
        caseSensitive: rule.caseSensitive,
      );

      final matchResult = PatternMatcher.matchWithDetails(
        rule.pattern,
        plainText,
        rule.isRegex,
        options: options,
        contextLines: 1,
      );

      if (matchResult != null) {
        // 最終マッチ時刻を更新
        final index = _rules.indexOf(rule);
        if (index >= 0) {
          _rules[index] = rule.copyWith(lastMatchedAt: DateTime.now());
        }

        // 通知イベントを作成
        final event = NotificationEvent(
          rule: rule,
          matchResult: matchResult,
          sessionName: sessionName,
          windowName: windowName,
          paneId: paneId,
          timestamp: DateTime.now(),
        );

        // コールバック呼び出し
        onNotification?.call(event);

        // ストリームに送信
        _eventController.add(event);

        // システム通知を表示
        await _showNotification(event);
      }
    }
  }

  /// システム通知を表示
  Future<void> _showNotification(NotificationEvent event) async {
    final rule = event.rule;

    // 通知の重要度を変換
    Importance importance;
    Priority priority;

    switch (rule.priority) {
      case NotificationPriority.low:
        importance = Importance.low;
        priority = Priority.low;
        break;
      case NotificationPriority.normal:
        importance = Importance.defaultImportance;
        priority = Priority.defaultPriority;
        break;
      case NotificationPriority.high:
        importance = Importance.high;
        priority = Priority.high;
        break;
      case NotificationPriority.urgent:
        importance = Importance.max;
        priority = Priority.max;
        break;
    }

    // 通知タイトル
    final title = rule.name;

    // 通知本文
    final body = _buildNotificationBody(event);

    // Android 通知詳細
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: importance,
      priority: priority,
      playSound: rule.sound != null,
      enableVibration: rule.vibrate,
      ticker: title,
    );

    // iOS 通知詳細
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    // バイブレーション
    if (rule.vibrate) {
      HapticFeedback.mediumImpact();
    }

    // 通知を表示
    await _notifications.show(
      _nextNotificationId(),
      title,
      body,
      details,
      payload: jsonEncode({
        'ruleId': rule.id,
        'sessionName': event.sessionName,
        'windowName': event.windowName,
        'paneId': event.paneId,
      }),
    );
  }

  /// 通知本文を構築
  String _buildNotificationBody(NotificationEvent event) {
    final parts = <String>[];

    if (event.sessionName != null) {
      parts.add('Session: ${event.sessionName}');
    }
    if (event.windowName != null) {
      parts.add('Window: ${event.windowName}');
    }

    // マッチした行の一部を表示（長すぎる場合は切り詰め）
    String matchedLine = event.matchResult.lineContent;
    if (matchedLine.length > 100) {
      matchedLine = '${matchedLine.substring(0, 100)}...';
    }
    parts.add(matchedLine);

    return parts.join('\n');
  }

  /// 次の通知IDを取得
  int _nextNotificationId() {
    _notificationIdCounter = (_notificationIdCounter + 1) % 1000000;
    return _notificationIdCounter;
  }

  // ===== 通知権限 =====

  /// 通知権限をリクエスト
  Future<bool> requestPermission() async {
    final android = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }

    return true;
  }

  /// 通知権限があるか確認
  Future<bool> hasPermission() async {
    final android = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }

    return true;
  }

  // ===== テスト用 =====

  /// テスト通知を送信
  Future<void> sendTestNotification(NotificationRule rule) async {
    final testEvent = NotificationEvent(
      rule: rule,
      matchResult: MatchResult(
        matchedText: 'test',
        start: 0,
        end: 4,
        lineContent: 'This is a test notification',
      ),
      sessionName: 'test-session',
      windowName: 'test-window',
      paneId: '%0',
      timestamp: DateTime.now(),
    );

    await _showNotification(testEvent);
  }

  // ===== クリーンアップ =====

  /// リソースを解放
  void dispose() {
    _eventController.close();
  }
}

/// プリセットルールを作成するユーティリティ
class NotificationPresets {
  NotificationPresets._();

  /// エラー検出ルール
  static NotificationRule error({String? targetSession}) {
    return NotificationRule(
      id: 'preset_error',
      name: 'Error Detection',
      pattern: PatternBuilder.error(),
      isRegex: true,
      priority: NotificationPriority.high,
      targetSession: targetSession,
    );
  }

  /// ビルド完了ルール
  static NotificationRule buildComplete({String? targetSession}) {
    return NotificationRule(
      id: 'preset_build',
      name: 'Build Complete',
      pattern: PatternBuilder.buildComplete(),
      isRegex: true,
      priority: NotificationPriority.normal,
      targetSession: targetSession,
    );
  }

  /// テスト完了ルール
  static NotificationRule testComplete({String? targetSession}) {
    return NotificationRule(
      id: 'preset_test',
      name: 'Test Complete',
      pattern: PatternBuilder.testComplete(),
      isRegex: true,
      priority: NotificationPriority.normal,
      targetSession: targetSession,
    );
  }

  /// メンションルール
  static NotificationRule mention(String username, {String? targetSession}) {
    return NotificationRule(
      id: 'preset_mention_$username',
      name: 'Mention @$username',
      pattern: PatternBuilder.mention(username),
      isRegex: true,
      priority: NotificationPriority.high,
      targetSession: targetSession,
    );
  }

  /// カスタムキーワードルール
  static NotificationRule keyword(
    String keyword, {
    String? name,
    String? targetSession,
    NotificationPriority priority = NotificationPriority.normal,
  }) {
    return NotificationRule(
      id: 'keyword_${keyword.toLowerCase().replaceAll(' ', '_')}',
      name: name ?? 'Keyword: $keyword',
      pattern: keyword,
      isRegex: false,
      priority: priority,
      targetSession: targetSession,
    );
  }
}
