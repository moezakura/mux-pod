import 'dart:async';

import '../l10n/app_localizations.dart';
import 'download_batch_session.dart';
import 'download_notification_sink.dart';
import 'download_progress_tracker.dart';
import 'download_state.dart';

/// キューイベント（進捗・完了・エラー・切断・items publish）の [DownloadState] 反映と
/// 通知発行を行うヘルパー（shell の state 反映部・設計書リスク 5 の追加分離）。
///
/// shell（[DownloadNotifier]）は state の読み書きと l10n 解決を関数で注入し、本クラスは
/// 「イベント → state 反映 + 通知」の publish 手順だけを持つ。不変条件（HIGH#1 の世代
/// ガード・M3 の publish 抑止・キャンセル×切断の phase ガード）は従来の shell 実装と
/// 同一の判定を維持する。
class DownloadPublishHandler {
  DownloadPublishHandler({
    required this.session,
    required this.progressTracker,
    required this.notificationSink,
    required this.clock,
    required this.l10n,
    required this.readState,
    required this.publishState,
  });

  /// バッチ世代・トークン・アイテム・予約名・保存先の所有者。
  final DownloadBatchSession session;

  /// 進捗の間引き判定・EMA 速度・速度ラベル。
  final DownloadProgressTracker progressTracker;

  /// 通知テキストの組み立て・発行（fire-and-forget）。
  final DownloadNotificationSink notificationSink;

  /// 速度算出・間引き判定用の clock。
  final DateTime Function() clock;

  /// 設定言語から解決したローカライズ文字列。
  final AppLocalizations Function() l10n;

  /// 現在の [DownloadState] を読む（phase ガード・導出値用）。
  final DownloadState Function() readState;

  /// [DownloadState] を反映する（shell の state 代入）。
  final void Function(DownloadState state) publishState;

  /// session の items publish を [DownloadState.items] へ反映する。
  void publishItems(List<DownloadItemState> items) {
    publishState(readState().copyWith(items: items));
  }

  /// 進捗コールバック（毎チャンク）。内部累積（session.items）は毎チャンク更新して
  /// 完了時の正確さを保証し、**state への反映は 100ms 間引き**する（基盤 R12）。
  void onProgress(int batch, int index, int doneBytes, int totalBytes) {
    if (!session.updateItem(
      index,
      (prev) => prev.copyWith(
        bytesReceived: doneBytes,
        totalBytes: totalBytes > 0 ? totalBytes : prev.totalBytes,
      ),
      publish: false,
      batch: batch,
    )) {
      return; // 古いバッチ（reset 後）の進捗は無視（HIGH#1）。
    }
    final now = clock();
    final cumulative = session.items.fold<int>(
      0,
      (s, i) => s + i.bytesReceived,
    );
    final sample = progressTracker.update(cumulative, totalBytes, now);
    if (!sample.shouldPublish) return;
    publishState(
      readState().copyWith(items: session.items, speedLabel: sample.speedLabel),
    );
    // 進捗通知（100ms 間引き publish と同期・n/total・%・bytes・速度）。
    final st = readState();
    final fraction = st.fraction;
    final percent = fraction == null ? 0 : (fraction * 100).round();
    unawaited(
      notificationSink.progress(
        l10n: l10n(),
        index: index,
        count: session.items.length,
        percent: percent,
        receivedBytes: st.receivedBytes,
        speedLabel: sample.speedLabel,
      ),
    );
  }

  /// アイテム境界: 速度区間をリセット（全体速度の過小表示防止）。
  void onItemBoundary() {
    progressTracker.reset();
  }

  /// 完了 publish（一括バッチのみ・M3）。
  void onBatchCompleted() {
    final hasErrors = session.items.any((i) => i.isError);
    final st = readState();
    publishState(
      DownloadState(
        phase: DownloadPhase.completed,
        items: session.items,
        errorMessage: hasErrors ? l10n().fileDownloadError : null,
        speedLabel: st.speedLabel,
      ),
    );
    // 完了サマリ（成功 a / 失敗 b / スキップ c）を通知へ残す。
    unawaited(
      notificationSink.complete(
        l10n: l10n(),
        completed: st.completedCount,
        failed: st.failedCount,
        skipped: st.skippedCount,
      ),
    );
  }

  /// openSftp 失敗（契約: throw しない・phase=error 遷移・MEDIUM#2）。
  void onBatchFailed() {
    publishState(
      DownloadState(
        phase: DownloadPhase.error,
        items: session.items,
        errorMessage: l10n().fileDownloadError,
      ),
    );
    unawaited(notificationSink.error(l10n: l10n()));
  }

  /// SSH 切断検知。世代ガードはキュー側が実施済み。phase ガードで一意ロック
  /// （キャンセル×切断の競合）し、トークン cancel + phase=error + 失敗理由通知へ反映。
  void onConnectionLost() {
    if (readState().phase != DownloadPhase.downloading) return;
    session.token?.cancel();
    publishState(
      readState().copyWith(
        phase: DownloadPhase.error,
        errorMessage: l10n().fileDownloadError,
      ),
    );
    // 失敗理由の通知更新（次の SSH 状態変化まで維持）。
    unawaited(
      notificationSink.failed(l10n: l10n(), error: l10n().sshConnectionLost),
    );
  }
}
