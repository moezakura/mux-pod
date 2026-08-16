import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../l10n/app_localizations.dart';

/// SSH接続をバックグラウンドで維持するためのForeground Serviceを管理
class SshForegroundTaskService {
  static final SshForegroundTaskService _instance =
      SshForegroundTaskService._internal();
  factory SshForegroundTaskService() => _instance;
  SshForegroundTaskService._internal();

  bool _isInitialized = false;
  bool _isRunning = false;
  String? _currentConnectionName;

  /// サービスが実行中かどうか
  bool get isRunning => _isRunning;

  /// 現在接続中の接続名
  String? get currentConnectionName => _currentConnectionName;

  /// Foreground Taskを初期化
  ///
  /// [l10n] 通知チャンネル名/説明の解決に使用するローカライズ済み文字列。
  /// チャンネルは登録後に変更できないため、最初の初期化時に設定言語の
  /// [AppLocalizations] を渡すこと。
  Future<void> initialize({required AppLocalizations l10n}) async {
    if (_isInitialized) return;
    if (!Platform.isAndroid) {
      _isInitialized = true;
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'muxpod_ssh_foreground',
        channelName: l10n.notifChannelName,
        channelDescription: l10n.notifChannelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        visibility: NotificationVisibility.VISIBILITY_SECRET,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
  }

  /// 通知権限を要求
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;

    // Android 13以降は通知権限が必要
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // バッテリー最適化の除外をリクエスト（オプション）
    final batteryOptimization =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!batteryOptimization) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    return await FlutterForegroundTask.checkNotificationPermission() ==
        NotificationPermission.granted;
  }

  /// SSH接続時にForeground Serviceを開始
  ///
  /// [l10n] 通知タイトル/本文とチャンネル名/説明の解決に使用する
  /// ローカライズ済み文字列。呼び出し元は
  /// `l10nForLanguage(ref.read(settingsProvider).language)` で渡すこと。
  Future<bool> startService({
    required String connectionName,
    required String host,
    required AppLocalizations l10n,
  }) async {
    if (!Platform.isAndroid) return true;
    if (_isRunning) return true;

    await initialize(l10n: l10n);

    final hasPermission = await requestPermissions();
    if (!hasPermission) {
      return false;
    }

    _currentConnectionName = connectionName;

    final result = await FlutterForegroundTask.startService(
      notificationTitle: l10n.notifSshConnectedTitle(connectionName),
      notificationText: l10n.notifHost(host),
      callback: _startCallback,
    );

    _isRunning = result is ServiceRequestSuccess;
    return _isRunning;
  }

  /// 通知テキストを更新
  Future<void> updateNotification({String? title, String? text}) async {
    if (!Platform.isAndroid || !_isRunning) return;

    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  /// SSH切断時にForeground Serviceを停止
  Future<void> stopService() async {
    if (!Platform.isAndroid || !_isRunning) return;

    await FlutterForegroundTask.stopService();
    _isRunning = false;
    _currentConnectionName = null;
  }

  /// サービスが実行可能か確認
  Future<bool> canStartService() async {
    if (!Platform.isAndroid) return false;

    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    return permission == NotificationPermission.granted;
  }
}

/// Foreground Task開始時のコールバック（必須だが、SSH接続はメインisolateで管理）
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_SshTaskHandler());
}

/// SSH接続維持用のTaskHandler
class _SshTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // SSH接続はメインisolateで管理されるため、ここでは何もしない
    // このHandlerはForeground Serviceを維持するためだけに存在
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 定期実行イベント（使用しない）
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // サービス終了時の処理（必要に応じてクリーンアップ）
  }

  @override
  void onNotificationButtonPressed(String id) {
    // 通知ボタンがタップされた時（使用しない）
  }

  @override
  void onNotificationPressed() {
    // 通知がタップされた時 - アプリを前面に持ってくる
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    // 通知がスワイプで削除された時
  }
}
