import 'package:flutter_muxpod/services/background/foreground_task_service.dart';

/// [TransferNotificationService] のテスト二重。
///
/// 通知更新の呼び出し履歴を [updateCalls] に記録し、DL プロバイダの通知連携
/// （進捗 / 完了 / 失敗 / キャンセル）を検証する。
///
/// - [serviceRunning] = false で「サービス未起動」を模擬（実サービスは `_isRunning`
///   ガードで no-op する挙動を再現・updateCalls に記録しない）。
/// - [throwOnUpdate] = true で「通知更新の throw」を模擬（呼び出し側（DownloadNotifier）
///   の握りつぶし no-op を検証できる）。
class FakeSshForegroundTaskService implements TransferNotificationService {
  /// 呼び出し履歴（title/text の順で記録）。
  final List<({String? title, String? text})> updateCalls = [];

  /// `stopService()` が呼ばれた回数（転送中に停止しないことの検証用）。
  int stopCalls = 0;

  /// false にすると更新を no-op にする（サービス未起動の模擬）。
  bool serviceRunning = true;

  /// true にすると更新が throw する（呼び出し側の握りつぶしを検証）。
  bool throwOnUpdate = false;

  @override
  Future<void> updateTransferNotification({String? title, String? text}) async {
    if (throwOnUpdate) {
      throw StateError('notification update failed');
    }
    if (!serviceRunning) return; // 未起動は no-op（実サービス同等）。
    updateCalls.add((title: title, text: text));
  }

  @override
  Future<void> stopService() async {
    stopCalls++;
  }
}