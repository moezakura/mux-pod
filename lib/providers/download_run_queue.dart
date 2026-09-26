import '../services/background/transfer_activity.dart';
import 'package:dartssh2/dartssh2.dart';

import '../services/sftp/sftp_download_service.dart';
import '../services/sftp/transfer_progress.dart';
import '../services/ssh/ssh_client.dart';
import 'download_batch_session.dart';
import 'download_state.dart';

/// キュー実行のイベントを shell へ報告するコールバック群。
///
/// state / l10n / 通知には触れず、発生したイベントだけを報告する
/// （shell が [DownloadState] 反映・[DownloadNotificationSink] 発行を行う）。
class DownloadQueueCallbacks {
  const DownloadQueueCallbacks({
    required this.onProgress,
    required this.onItemBoundary,
    required this.onBatchCompleted,
    required this.onBatchFailed,
    required this.onConnectionLost,
  });

  /// アイテム進捗（毎チャンク・累積 done/total）。
  ///
  /// [batch] はこのキューのバッチ世代スナップショット。reset 等で世代が進んだ
  /// 在途コールバックを無視するための世代ガードは、報告を受けた側（shell）が
  /// [DownloadBatchSession.updateItem] 経由で行う（HIGH#1）。
  final void Function(int batch, int index, int doneBytes, int totalBytes)
  onProgress;

  /// アイテム境界（速度区間のリセット）。
  final void Function() onItemBoundary;

  /// キュー完了の publish（[DownloadQueueRunner.run] の `publishCompletion` 時のみ）。
  final void Function() onBatchCompleted;

  /// openSftp 失敗（契約: throw しない・phase=error 遷移・MEDIUM#2）。
  final void Function() onBatchFailed;

  /// SSH 切断検知（downloading 中の phase ガードと確定は shell が行う）。
  final void Function() onConnectionLost;
}

/// 1 バッチの順次 SFTP ダウンロードキュー（openSftp・SSH 切断監視・アイテム単位
/// try/catch・publishCompletion 方針）を実行する。
///
/// 状態遷移（[DownloadState]）・l10n・通知には触れず、進捗・アイテム更新・完了・
/// エラー・切断を [DownloadQueueCallbacks] で報告する。不変条件は所有側の
/// [DownloadBatchSession]（世代ガード付き [DownloadBatchSession.updateItem] 等）と
/// 世代スナップショットの照合で維持する（M1/M2/M4・HIGH#1）。
///
/// - バッチ開始時に**トークン/世代/保存先をローカルスナップショット**し、reset() 等に
///   よるバッチ無効化を世代不一致で検知して安全に abort する（在途 download 完了時の
///   items 更新／`!token.isCancelled` が古いバッチへ触れない・HIGH#1）。
/// - SSH 切断監視: downloading 中に disconnected/error を受けたら [DownloadQueueCallbacks.onConnectionLost]
///   を報告する（トークン cancel + phase=error は shell が実施・部分削除はサービス側）。
/// - キャンセル×切断の競合は phase ガードで一意ロック（shell 側・先に確定した方が優先・
///   サービス側 catch も既に cancelled なら error へ上書きしない）。
/// - アイテム単位 try/catch: 失敗は isError 記録 + 部分削除（サービス済み）+ 続行。
/// - 各アイテムは `destination.open(name, overwrite:)` で [DownloadSink] を開き、
///   `openSink` としてサービスへ渡す。キュー終了時（finally）に**自分のスナップ
///   ショット**の destination を 1 回だけ dispose（iOS スコープ解放・世代管理・M1）。
/// - [publishCompletion] は一括（true・default）では完了 publish を報告し、単一
///   （false・M3）では抑止し、最終確定を呼び出し側（[DownloadNotifier.startSingleTmpDownload]）
///   に委ねる（中間 completed のリーク・二重通知防止）。
/// - `openSftp()` 失敗は例外を投げず [DownloadQueueCallbacks.onBatchFailed] を報告して
///   phase=error へ遷移（MEDIUM#2・契約「throw しない」）し、保存先も解放する（M2）。
class DownloadQueueRunner {
  DownloadQueueRunner({SftpDownloadService? service})
    : _service = service ?? SftpDownloadService();

  final SftpDownloadService _service;

  Future<void> run({
    required SshClient sshClient,
    required DownloadBatchSession session,
    required DownloadQueueCallbacks callbacks,
    bool publishCompletion = true,
  }) => TransferActivity.shared.run(
    () => _run(
      sshClient: sshClient,
      session: session,
      callbacks: callbacks,
      publishCompletion: publishCompletion,
    ),
  );

  Future<void> _run({
    required SshClient sshClient,
    required DownloadBatchSession session,
    required DownloadQueueCallbacks callbacks,
    bool publishCompletion = true,
  }) async {
    final batch = session.generation; // バッチスナップショット（reset 検知用）。
    final token = session.token; // トークンスナップショット（null 参照の回避）。
    final destination = session.destination; // 保存先スナップショット（キュー中に解放されない）。
    if (token == null || destination == null) return;

    final SftpClient sftp;
    try {
      sftp = await sshClient.openSftp();
    } catch (_) {
      // openSftp 失敗（isConnected 検査と openSftp の間の切断レース等）: 契約どおり
      // 例外を UI に投げず、phase=error に遷移する（膠着を防ぐ・MEDIUM#2）。
      if (session.isCurrent(batch)) {
        callbacks.onBatchFailed();
      }
      // finally に入る前に return するため、保存先もここで解放する（M2）。
      await session.disposeDestination(batch: batch, destination: destination);
      return;
    }
    // NOTE: sftp.close() は呼ばない（キャッシュ共有の SftpClient は呼び出し側で
    // close() を呼んではならない契約・ssh_client.dart）。
    final sub = sshClient.connectionStateStream.listen((connState) {
      // 世代ガード: 旧バッチ（キャンセル〜finally の窓）のリスナーが新バッチの
      // state を error に書き換えない（M4）。
      if (!session.isCurrent(batch)) return;
      if (connState != SshConnectionState.connected) {
        callbacks.onConnectionLost();
      }
    });
    session.setConnectionSub(sub);
    try {
      for (var i = 0; i < session.items.length; i++) {
        if (!session.isCurrent(batch)) return; // reset 等で無効化されていたら abort。
        if (token.isCancelled) break;
        final item = session.items[i];
        if (item.isSkipped) continue; // スキップ決定はキューから除外（転送しない）。
        try {
          final result = await _service.download(
            sftp: sftp,
            remotePath: item.remotePath,
            openSink: () =>
                destination.open(item.name, overwrite: item.overwrite),
            cancellation: token,
            onProgress: (done, total) =>
                callbacks.onProgress(batch, i, done, total),
          );
          if (!session.isCurrent(batch)) return; // 在途完了が古いバッチへ触れない。
          // アイテム完了は即時反映（100ms 間引きの対象外）。
          session.updateItem(
            i,
            (it) => it.copyWith(
              bytesReceived: result.bytesDownloaded,
              isCompleted: true,
              errorMessage: null,
            ),
            publish: true,
            batch: batch,
          );
        } on TransferCancelledException {
          // キャンセル/切断/reset。phase は cancel()/切断ハンドラ/reset() が確定済みのため
          // ここで上書きしない（キャンセル×切断の一意ロック・error を皆殺しにしない）。
          break;
        } catch (e) {
          if (!session.isCurrent(batch)) return;
          // アイテム単位の失敗（転送エラー・SSH 断・書込 I/O エラー＝ディスクフル含む）。
          // 部分削除はサービス層が実施済み。次のアイテムへ続行する。
          session.updateItem(
            i,
            (it) => it.copyWith(isError: true, errorMessage: '$e'),
            publish: true,
            batch: batch,
          );
        }
        // アイテム境界: 速度区間をリセット（全体速度の過小表示防止・Concern 27）。
        callbacks.onItemBoundary();
      }
      if (!session.isCurrent(batch)) return;
      if (!token.isCancelled) {
        // 単一バッチ（publishCompletion: false）は中間 completed を publish しない
        // （M3: 最終確定を startSingleTmpDownload に集約・二重通知も防止）。
        if (publishCompletion) {
          callbacks.onBatchCompleted();
        }
      }
      // キャンセル/切断時は既確定の phase（cancelled/error）を維持する。
    } finally {
      await sub.cancel();
      session.clearConnectionSub(sub);
      // このバッチの保存先（スナップショット）を解放する。フィールドではなく自分の
      // スナップショットを対象にするため、旧バッチの finally が新バッチの保存先
      // （置換後の _destination）を破棄することはない（M1・世代管理）。
      await session.disposeDestination(batch: batch, destination: destination);
    }
  }
}
