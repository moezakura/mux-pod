import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_lookup.dart';
import '../services/background/foreground_task_service.dart';
import '../services/download/download_destination.dart';
import '../services/download/file_destination.dart';
import '../services/download/save_as_exporter.dart';
import '../services/sftp/file_entry.dart';
import '../services/sftp/overwrite_choice.dart';
import '../services/sftp/sftp_download_service.dart';
import 'download_batch_session.dart';
import 'download_collision_resolver.dart';
import 'download_notification_sink.dart';
import 'download_progress_tracker.dart';
import 'download_publish_handler.dart';
import 'download_run_queue.dart';
import 'download_state.dart';
import 'settings_provider.dart';
import 'ssh_provider.dart';

export 'download_state.dart';

/// SFTP ダウンロードの状態管理（非 AutoDispose 専用）・構成ルート。
///
/// フローを編成し [DownloadState] へ反映する。順次キュー・衝突事前スキャン・単一 tmp +
/// Save-As・世代管理（HIGH#1）・100ms 間引き（R12）・SSH 切断監視。機械的・状態的
/// ロジックと不変条件（M1-M4）の詳細は各コラボレータ（[DownloadBatchSession] /
/// [DownloadQueueRunner] / [DownloadProgressTracker] / [DownloadCollisionResolver] /
/// [DownloadNotificationSink]）の doc を参照。
class DownloadNotifier extends Notifier<DownloadState> {
  DownloadNotifier({
    DateTime Function()? clock,
    this.progressThrottle = const Duration(milliseconds: 100),
    TransferNotificationService? notificationService,
    SaveAsExporter? exporter,
  }) {
    _clock = clock ?? DateTime.now;
    _exporter = exporter ?? const FfdSaveAsExporter();
    _notificationSink = DownloadNotificationSink(
      notificationService: notificationService,
    );
    _progressTracker = DownloadProgressTracker(
      progressThrottle: progressThrottle,
      clock: _clock,
    );
  }

  final SftpDownloadService _service = SftpDownloadService();

  /// 「名前を付けて保存」エクスポーター（テストでは FakeSaveAsExporter を注入）。
  late SaveAsExporter _exporter;

  /// 速度算出・間引き判定用の clock（テスト注入可）。
  late DateTime Function() _clock;

  /// state 反映（進捗）の最小間隔。100ms 間引きは転送タスク層の責務。
  final Duration progressThrottle;

  /// バッチ世代・トークン・アイテム・予約名・保存先の所有者。
  late final DownloadBatchSession _session = DownloadBatchSession(
    onItemsPublished: (items) => state = state.copyWith(items: items),
  );

  /// 進捗の間引き判定・EMA 速度・速度ラベル。
  late final DownloadProgressTracker _progressTracker;

  /// 通知テキストの組み立て・発行（fire-and-forget）。
  late final DownloadNotificationSink _notificationSink;

  /// 名前衝突の解決（状態を持たない・reserved は session から受ける）。
  final DownloadCollisionResolver _collisionResolver =
      const DownloadCollisionResolver();

  /// 順次キュー実行（イベントは [_queueCallbacks] で報告）。
  late final DownloadQueueRunner _queueRunner = DownloadQueueRunner(
    service: _service,
  );

  /// キューイベントの state 反映 + 通知（publish 処理）ヘルパー。
  late final DownloadPublishHandler _publisher = DownloadPublishHandler(
    session: _session,
    progressTracker: _progressTracker,
    notificationSink: _notificationSink,
    clock: _clock,
    l10n: () => _l10n,
    readState: () => state,
    publishState: (s) => state = s,
  );

  /// キューイベントの shell 側ハンドラ群。
  late final DownloadQueueCallbacks _queueCallbacks = DownloadQueueCallbacks(
    onProgress: _publisher.onProgress,
    onItemBoundary: _publisher.onItemBoundary,
    onBatchCompleted: _publisher.onBatchCompleted,
    onBatchFailed: _publisher.onBatchFailed,
    onConnectionLost: _publisher.onConnectionLost,
  );

  /// 設定言語から解決したローカライズ文字列（通知テキストに使用・既存流儀）。
  AppLocalizations get _l10n =>
      l10nForLanguage(ref.read(settingsProvider).language);

  @override
  DownloadState build() {
    ref.onDispose(() {
      _session.cancelConnectionSub();
    });
    return const DownloadState();
  }

  /// ダウンロード一式を開始する（一括・[DownloadDestination] ベース）。
  ///
  /// 先頭で必ず新規 [TransferCancelToken] を生成し、**同名衝突を事前スキャン**する
  /// （Sync API 禁止）。衝突あり → awaitingOverwrite + [DownloadState.collidingItems]
  /// 公開（転送は開始しない）／なし → 順次キュー開始。失敗は throw せず state へ反映。
  Future<void> startDownloads(
    List<FileEntry> entries,
    DownloadDestination destination,
  ) async {
    if (state.phase == DownloadPhase.downloading) {
      // 再入ガード: 採用されない保存先を解放（M2・ベストエフォート）。
      unawaited(_session.disposeOrphan(destination));
      return;
    }
    // awaitingOverwrite 中の旧保存先を解放してから置換（M2: 参照喪失リーク防止）。
    if (state.phase == DownloadPhase.awaitingOverwrite &&
        _session.destination != null) {
      unawaited(
        _session.disposeDestination(
          batch: _session.generation,
          destination: _session.destination,
        ),
      );
    }
    // 新規トークン生成（使い回しは再入即キャンセルのバグ）。保存先は検査前に設定し
    // 非接続/error return 経路でも必ず解放（M2）。
    _session.begin(); // 新バッチ開始（旧バッチの在途コールバックを無効化）。
    _progressTracker.reset();
    _session.setDestination(destination);

    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      state = DownloadState(
        phase: DownloadPhase.error,
        errorMessage: _l10n.fileDownloadError,
      );
      unawaited(_session.disposeDestination()); // 本バッチの保存先を解放（M2）。
      return;
    }

    // ディレクトリは防御的除外。バッチ内宛先名の重複は自動リネーム（_1 採番・reserved
    // 管理・LOW#3）。localPath は表示用の name のみ（実パスは destination 管理）。
    final items = <DownloadItemState>[];
    for (final e in entries.where((entry) => !entry.isDirectory)) {
      final name = SftpDownloadService.sanitizeLocalName(e.fullPath);
      var resolved = name;
      if (!_session.reservedNames.add(resolved)) {
        resolved = await _collisionResolver.firstAvailableName(
          name,
          reserved: _session.reservedNames,
          existsIn: _session.existsInDestination,
        );
        _session.reservedNames.add(resolved);
      }
      items.add(
        DownloadItemState(
          remotePath: e.fullPath,
          name: resolved,
          localPath: resolved,
        ),
      );
    }
    _session.setItems(items);
    state = DownloadState(
      phase: DownloadPhase.selecting,
      items: _session.items,
    );

    // 同名衝突の事前スキャン（転送開始前に一括確認・転送中のダイアログ排除）。
    final colliding = await _collisionResolver.preScan(
      _session.items,
      existsIn: _session.existsInDestination,
    );
    if (colliding.isNotEmpty) {
      state = DownloadState(
        phase: DownloadPhase.awaitingOverwrite,
        items: _session.items,
        collidingItems: colliding,
      );
      return;
    }

    state = DownloadState(
      phase: DownloadPhase.downloading,
      items: _session.items,
    );
    await _queueRunner.run(
      sshClient: sshClient,
      session: _session,
      callbacks: _queueCallbacks,
    );
  }

  /// 単一ファイルを tmp 領域へダウンロードし、Save-As でユーザー選択先へエクスポートする。
  ///
  /// 1. `getTemporaryDirectory()/sftp_download/<sanitizeLocalName>` へ書込（常に `_1` から採番）。
  /// 2. `phase=downloading` → 順次キュー。単一バッチはキューの中間 completed を publish
  ///    せず（M3）、最終確定（completed/cancelled/error）は本メソッドに集約する。
  /// 3. 全成功時のみ `phase=exporting` → [SaveAsExporter.export]（非 null: completed +
  ///    `notifDownloadComplete(1,0,0)` / null: cancelled / throw: error）。
  /// 4. エクスポート後は成功/失敗にかかわらず tmp ファイルを削除（ベストエフォート）。
  Future<void> startSingleTmpDownload(FileEntry entry) async {
    if (state.phase == DownloadPhase.downloading) return; // 再入ガード

    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      state = DownloadState(
        phase: DownloadPhase.error,
        errorMessage: _l10n.fileDownloadError,
      );
      return;
    }

    // 新規トークン生成（使い回しは再入即キャンセルのバグ）。
    _session.begin(); // 新バッチ開始（旧バッチの在途コールバックを無効化）。
    final batch = _session.generation;
    _progressTracker.reset();

    // tmp 領域へ書込。衝突回避のため常に `_1` から採番する（前回クラッシュの残骸を
    // 上書きしない・実装 firstAvailablePath）。
    final tmpDir = Directory(
      '${(await getTemporaryDirectory()).path}/sftp_download',
    );
    await tmpDir.create(recursive: true);
    final baseName = SftpDownloadService.sanitizeLocalName(entry.fullPath);
    final tmpPath = _collisionResolver.firstAvailablePath(
      '${tmpDir.path}/$baseName',
    );
    // 採番後の basename を保存名とする（open の宛先 = tmpPath を一致させる）。
    final tmpName = tmpPath.substring(tmpPath.lastIndexOf('/') + 1);

    final item = DownloadItemState(
      remotePath: entry.fullPath,
      name: tmpName,
      localPath: tmpPath,
    );
    _session.setItems([item]);
    _session.setDestination(FileDestination(tmpDir.path));
    state = DownloadState(
      phase: DownloadPhase.downloading,
      items: _session.items,
    );
    // M3: 単一バッチはキューの中間 completed publish を抑止（最終確定は本メソッドに
    // 集約。Save-As 確定前の中間 completed と二重 notifDownloadComplete が解消される）。
    await _queueRunner.run(
      sshClient: sshClient,
      session: _session,
      callbacks: _queueCallbacks,
      publishCompletion: false,
    );

    if (!_session.isCurrent(batch)) return; // reset 等で無効化 → export しない。

    // 全成功時のみ Save-As エクスポートへ。転送失敗の最終確定（error）もここで行う
    // （M3: キューは中間 phase を publish しないため）。
    final done = _session.items[0];
    if (!done.isCompleted ||
        done.isError ||
        (_session.token?.isCancelled ?? true)) {
      // tmp 残骸の防御的削除（通常は sink.deletePartial で削除済み・ベストエフォート）。
      await _deleteTmpBestEffort(tmpPath);
      // キャンセル/切断時は cancel()/切断ハンドラが phase を確定済みのため上書きしない
      // （downloading のまま残るのは転送失敗のみ・単一バッチの最終確定）。
      if (_session.isCurrent(batch) &&
          state.phase == DownloadPhase.downloading) {
        state = DownloadState(
          phase: DownloadPhase.error,
          items: _session.items,
          errorMessage: _l10n.fileDownloadError,
        );
        unawaited(_notificationSink.error(l10n: _l10n));
      }
      return;
    }

    state = DownloadState(
      phase: DownloadPhase.exporting,
      items: _session.items,
      speedLabel: state.speedLabel,
    );
    String? exported;
    try {
      exported = await _exporter.export(tmpPath);
    } catch (_) {
      // エクスポート失敗（保存先 I/O エラー等）は phase=error へ。
      if (_session.isCurrent(batch)) {
        state = DownloadState(
          phase: DownloadPhase.error,
          items: _session.items,
          errorMessage: _l10n.fileDownloadError,
        );
        unawaited(_notificationSink.error(l10n: _l10n));
      }
      return;
    } finally {
      // export 後は成功/失敗にかかわらず tmp を削除（ベストエフォート）。
      await _deleteTmpBestEffort(tmpPath);
    }
    if (!_session.isCurrent(batch)) return;

    if (exported == null) {
      // Save-As キャンセル → 転送中断（cancelled・確定済み）。
      state = DownloadState(
        phase: DownloadPhase.cancelled,
        items: _session.items,
      );
      unawaited(_notificationSink.cancelled(l10n: _l10n));
      return;
    }

    // localPath をエクスポート先（戻り値パス）で更新して completed。
    _session.updateItem(
      0,
      (it) => it.copyWith(localPath: exported),
      publish: false,
      batch: batch,
    );
    state = DownloadState(
      phase: DownloadPhase.completed,
      items: _session.items,
      speedLabel: state.speedLabel,
    );
    unawaited(
      _notificationSink.complete(
        l10n: _l10n,
        completed: 1,
        failed: 0,
        skipped: 0,
      ),
    );
  }

  /// 上書き確認の決定を適用し、順次キューを開始する。
  ///
  /// `overwrite`: overwrite=true で保存先の同名を切り詰めて再利用。`rename`: `_1`
  /// 接尾辞で空き名を採番（destination.exists + バッチ内 reserved・LOW#3）して
  /// overwrite=true（SAF 側の自動採番で壊さない）。`skip`: キューから除外。
  Future<void> applyOverwriteDecisions(
    Map<String, OverwriteChoice> decisions,
  ) async {
    if (state.phase != DownloadPhase.awaitingOverwrite) return;

    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      state = DownloadState(
        phase: DownloadPhase.error,
        errorMessage: _l10n.fileDownloadError,
      );
      // startDownloads が設定済みの保存先を解放（M2: iOS スコープ）。
      unawaited(_session.disposeDestination());
      return;
    }

    final result = await _collisionResolver.resolveDecisions(
      decisions: decisions,
      items: _session.items,
      reserved: _session.reservedNames,
      existsIn: _session.existsInDestination,
    );
    if (result.cancelled) {
      // #40 batch モードでは不使用の値。安全側にバッチ中断（idle・転送開始しない）。
      _session.setItems(const []);
      unawaited(_session.disposeDestination());
      state = const DownloadState();
      return;
    }
    _session.setItems(result.items);
    state = DownloadState(
      phase: DownloadPhase.downloading,
      items: _session.items,
    );
    await _queueRunner.run(
      sshClient: sshClient,
      session: _session,
      callbacks: _queueCallbacks,
    );
  }

  /// ユーザーキャンセル（sync・冪等）。phase ガード（downloading 以外は no-op）→
  /// トークン cancel → phase=cancelled。在途ダウンロードはチャンク境界で
  /// [TransferCancelledException]（部分削除はサービス側が実施）になる。
  void cancel() {
    if (state.phase != DownloadPhase.downloading) return;
    _session.token?.cancel();
    state = state.copyWith(phase: DownloadPhase.cancelled);
    unawaited(_notificationSink.cancelled(l10n: _l10n));
  }

  /// idle へ戻す（トークン破棄・items クリア・EMA reset・切断監視の購読解除）。
  ///
  /// バッチを無効化（generation++）し、在途キュー（[DownloadQueueRunner.run]）の世代
  /// 不一致検知で安全に abort させる（HIGH#1）。在途 download はトークン cancel で即中断
  /// （部分削除はサービス層）。未 dispose の保存先もここで解放（キュー finally との
  /// 二重解放は dispose 済みフラグで防止・M1）。
  void reset() {
    final currentBatch = _session.generation; // 解放管理用: 旧バッチの世代。
    final disposed = _session.destination;
    _session.invalidate(); // バッチ無効化 + トークン cancel + 購読解除 + items クリア。
    _progressTracker.reset();
    // 明示世代で解放し、旧バッチの finally が新バッチの保存先へ触れない（M1）。
    unawaited(
      _session.disposeDestination(batch: currentBatch, destination: disposed),
    );
    state = const DownloadState();
  }

  /// tmp ファイル削除（ベストエフォート・throw しない）。
  Future<void> _deleteTmpBestEffort(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // 残骸は握りつぶし（削除失敗は転送結果に影響させない）。
    }
  }
}

/// ダウンロード状態プロバイダー（非 AutoDispose・画面破棄後も転送継続）。
final downloadProvider = NotifierProvider<DownloadNotifier, DownloadState>(
  DownloadNotifier.new,
);
