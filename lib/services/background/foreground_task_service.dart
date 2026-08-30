import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../l10n/app_localizations.dart';

/// 転送（ダウンロード）通知の更新窓口。
///
/// [DownloadNotifier]（lib/providers/download_provider.dart）が利用し、テストでは
/// 差し替え可能にするための抽象（テスト二重: fake_ssh_foreground_task_service.dart）。
abstract class TransferNotificationService {
  /// 転送進捗 / 完了 / 失敗 / キャンセルの通知テキストを更新する（テキスト更新のみ）。
  /// [title] / [text] が null の項目は「未更新」扱い。
  /// サービス未起動・更新失敗（`ServiceNotStartedException` 等）は no-op（ベストエフォート）。
  Future<void> updateTransferNotification({String? title, String? text});

  /// サービス停止。
  ///
  /// **DownloadNotifier は絶対に呼ばない**（転送中は SSH 維持用サービスを停止しない）。
  /// SSH 切断時の停止は既存の ssh_provider 経路のみ。インターフェースに含めるのは
  /// 「転送中に stopService されない」ことを回帰テストで機械担保するための観測点。
  Future<void> stopService();
}

/// SSH接続をバックグラウンドで維持するためのForeground Serviceを管理
class SshForegroundTaskService implements TransferNotificationService {
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

  /// 転送（ダウンロード）の通知テキストを更新する（[TransferNotificationService]）。
  ///
  /// 進捗 / 完了サマリ / 失敗理由 / キャンセルのテキストのみを更新する
  /// （flutter_foreground_task 8.17.0 の `updateService` はテキスト更新のみで
  /// 進捗バー API は無い）。`_isRunning` ガードでサービス未起動は no-op、
  /// `ServiceNotStartedException`（停止競合等）は握りつぶして no-op にする
  /// （転送自体を不成立にしない・ベストエフォート）。
  @override
  Future<void> updateTransferNotification({String? title, String? text}) async {
    if (!Platform.isAndroid || !_isRunning) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } on ServiceNotStartedException {
      // サービス未起動（停止競合）は握りつぶし no-op。
    }
  }

  /// SSH切断時にForeground Serviceを停止
  @override
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
