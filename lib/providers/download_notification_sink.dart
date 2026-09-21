import '../l10n/app_localizations.dart';
import '../services/background/foreground_task_service.dart';
import '../services/sftp/file_entry.dart';

/// 転送通知テキスト（l10n 解決・バイト表示含む）の組み立てと fire-and-forget 発行を行う。
///
/// shell（[DownloadNotifier]）はセマンティックなイベント（進捗・完了・キャンセル・
/// 失敗・エラー）を渡すだけで、テキスト組み立て・文言・バイト表示はここに一元化する
/// （M3 の二重通知防止・文言差の混入防止）。発行失敗は握りつぶし（転送に影響させない）。
class DownloadNotificationSink {
  DownloadNotificationSink({TransferNotificationService? notificationService})
    : _notification = notificationService ?? SshForegroundTaskService();

  /// 転送通知の更新窓口（テストでは FakeSshForegroundTaskService を注入）。
  /// 既定は既存の SshForegroundTaskService（シングルトン）。
  final TransferNotificationService _notification;

  /// 進捗通知（100ms 間引き publish と同期・n/total・%・bytes・速度）。
  Future<void> progress({
    required AppLocalizations l10n,
    required int index,
    required int count,
    required int percent,
    required int receivedBytes,
    required String speedLabel,
  }) async {
    await _notify(
      l10n.notifDownloadProgress(
        index + 1,
        count,
        percent,
        _bytesLabel(receivedBytes),
        speedLabel,
      ),
    );
  }

  /// 完了サマリ（成功 [completed] / 失敗 [failed] / スキップ [skipped]）。
  Future<void> complete({
    required AppLocalizations l10n,
    required int completed,
    required int failed,
    required int skipped,
  }) async {
    await _notify(l10n.notifDownloadComplete(completed, failed, skipped));
  }

  /// ユーザーキャンセル通知。
  Future<void> cancelled({required AppLocalizations l10n}) async {
    await _notify(l10n.notifDownloadCancelled);
  }

  /// 失敗理由の通知更新（[error] は sshConnectionLost 等の詳細メッセージ）。
  Future<void> failed({
    required AppLocalizations l10n,
    required String error,
  }) async {
    await _notify(l10n.notifDownloadFailed(error));
  }

  /// バッチ全体エラー通知（fileDownloadError）。
  Future<void> error({required AppLocalizations l10n}) async {
    await _notify(l10n.fileDownloadError);
  }

  /// 転送通知をベストエフォートで更新する（失敗は握りつぶし・転送に影響させない）。
  Future<void> _notify(String? text) async {
    try {
      await _notification.updateTransferNotification(text: text);
    } catch (_) {
      // 通知更新の失敗（サービス未起動含む）は no-op（転送自体を不成立にしない）。
    }
  }

  /// バイト表示（Concern 4: 既存 [FileEntry.formattedSize] を流用・再実装しない）。
  String _bytesLabel(int bytes) => FileEntry(
    name: '',
    fullPath: '',
    isDirectory: false,
    size: bytes,
  ).formattedSize;
}
