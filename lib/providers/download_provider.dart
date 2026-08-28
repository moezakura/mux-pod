import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
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
import '../services/sftp/transfer_format.dart';
import '../services/sftp/transfer_progress.dart';
import '../services/ssh/ssh_client.dart';
import 'settings_provider.dart';
import 'ssh_provider.dart';

/// ダウンロード転送のフェーズ。
enum DownloadPhase {
  /// 待機中（何もしていない状態）。
  idle,

  /// 保存先選択・事前スキャン中。
  selecting,

  /// 順次ダウンロードキュー実行中。
  downloading,

  /// 単一ダウンロードの Save-As エクスポート待ち（ユーザーの保存先選択中）。
  exporting,

  /// 同名衝突の上書き確認待ち（事前スキャンで検出）。
  awaitingOverwrite,

  /// ユーザーキャンセルで中断・確定済み。
  cancelled,

  /// 全アイテムの処理完了（一部失敗・スキップ含む）。
  completed,

  /// SSH 切断等でエラー確定。
  error,
}

/// ダウンロード 1 アイテムの状態。
class DownloadItemState {
  final String remotePath;

  /// サニタイズ済みの表示名（basename）。
  final String name;

  /// 総バイト数。0 以下はサイズ未知（基盤契約・未知は不確定表示）。
  final int totalBytes;

  /// 転送済みバイト数（累積）。
  final int bytesReceived;

  /// 端末上の保存先を表す表示用パス。
  ///
  /// - 単一（[startSingleTmpDownload]）: 当初は tmp の実パス。Save-As エクスポート完了後に
  ///   戻り値パス（例: `Download/sample.txt`）へ更新される。
  /// - 一括（[startDownloads]）: サニタイズ済みの name のみ（実パスは
  ///   [DownloadDestination] が管理）。
  final String localPath;

  /// 転送エラー（書込 I/O エラー含む）で失敗したか。
  final bool isError;

  /// 上書き確認で「スキップ」決定されたか（キューから除外）。
  final bool isSkipped;

  /// 転送が正常に完了したか（集計 completedCount の正確化のための拡張）。
  final bool isCompleted;

  /// 失敗理由（アイテム単位のエラー詳細）。
  final String? errorMessage;

  /// `destination.open(name, overwrite:)` に渡す上書きフラグ。
  ///
  /// 既定は `false`（新規作成・保存先実装による採番）。上書き決定・リネーム採番時に
  /// `true` になる（SAF 側の自動採番を抑止し、決定した名前を確実に使う）。
  final bool overwrite;

  const DownloadItemState({
    required this.remotePath,
    required this.name,
    required this.localPath,
    this.totalBytes = 0,
    this.bytesReceived = 0,
    this.isError = false,
    this.isSkipped = false,
    this.isCompleted = false,
    this.errorMessage,
    this.overwrite = false,
  });

  DownloadItemState copyWith({
    String? name,
    String? localPath,
    int? totalBytes,
    int? bytesReceived,
    bool? isError,
    bool? isSkipped,
    bool? isCompleted,
    String? errorMessage,
    bool? overwrite,
  }) {
    return DownloadItemState(
      remotePath: remotePath,
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      isError: isError ?? this.isError,
      isSkipped: isSkipped ?? this.isSkipped,
      isCompleted: isCompleted ?? this.isCompleted,
      errorMessage: errorMessage ?? this.errorMessage,
      overwrite: overwrite ?? this.overwrite,
    );
  }
}

/// ダウンロード転送全体の状態。
class DownloadState {
  final DownloadPhase phase;
  final List<DownloadItemState> items;

  /// バッチ全体（または切断・開始失敗）のエラーメッセージ。
  final String? errorMessage;

  /// 同名衝突で上書き確認待ちになったアイテム（awaitingOverwrite 中のみ非空）。
  final List<DownloadItemState> collidingItems;

  /// 直近の転送速度表示（`formatTransferSpeed` 済み・フィールド実装）。
  /// EMA 状態は [DownloadNotifier] が保持するため純 getter では導出できない。
  final String speedLabel;

  const DownloadState({
    this.phase = DownloadPhase.idle,
    this.items = const [],
    this.errorMessage,
    this.collidingItems = const [],
    this.speedLabel = '',
  });

  /// 転送済みバイト数（全アイテム累積）。
  int get receivedBytes => items.fold(0, (s, i) => s + i.bytesReceived);

  /// 総バイト数（未知=0 は除外・表示用）。
  int get totalBytes =>
      items.fold(0, (s, i) => s + (i.totalBytes > 0 ? i.totalBytes : 0));

  /// 正常完了アイテム数。
  int get completedCount =>
      items.where((i) => i.isCompleted && !i.isError).length;

  /// 失敗アイテム数。
  int get failedCount => items.where((i) => i.isError).length;

  /// スキップされたアイテム数。
  int get skippedCount => items.where((i) => i.isSkipped).length;

  /// 全体進捗率（0.0〜1.0）。**既知サイズ分の累積/総和**で部分進捗を表示し、
  /// 既知サイズが無い場合は null（不確定表示・基盤契約 totalBytes<=0=サイズ未知）。
  double? get fraction {
    var knownTotal = 0;
    var knownReceived = 0;
    for (final i in items) {
      if (i.totalBytes <= 0) continue;
      knownTotal += i.totalBytes;
      knownReceived += i.bytesReceived > i.totalBytes
          ? i.totalBytes
          : i.bytesReceived;
    }
    if (knownTotal <= 0) return null;
    return knownReceived / knownTotal;
  }

  DownloadState copyWith({
    DownloadPhase? phase,
    List<DownloadItemState>? items,
    String? errorMessage,
    bool clearError = false,
    List<DownloadItemState>? collidingItems,
    String? speedLabel,
  }) {
    return DownloadState(
      phase: phase ?? this.phase,
      items: items ?? this.items,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      collidingItems: collidingItems ?? this.collidingItems,
      speedLabel: speedLabel ?? this.speedLabel,
    );
  }
}

/// SFTP ダウンロードの状態管理（非 AutoDispose 専用）。
///
/// - 順次キュー（アイテム単位 try/catch・失敗は isError 記録して続行・最終 completed）
/// - 一括: [DownloadDestination] に複数ファイルを書込（名前ベース・上書き/リネーム決定は
///   [DownloadItemState.overwrite] として `open()` へ伝搬）。キュー完了時・reset() で
///   destination を 1 回だけ dispose（iOS スコープ解放等）。
/// - 単一: tmp 領域（`sftp_download/`）へ書込 → Save-As エクスポート（[SaveAsExporter]）
///   → tmp 削除。エクスポート結果で phase=completed/cancelled/error。
/// - 先頭で必ず新規 [TransferCancelToken] を生成（使い回しは再入即キャンセルのバグ）
/// - 同名衝突は転送開始前に事前スキャン（awaitingOverwrite → applyOverwriteDecisions）
/// - SSH 切断監視（connectionStateStream listen・キャンセル×切断は phase ガードで一意ロック）
/// - 進捗は毎チャンク内部累積し、**state 反映は 100ms 間引き**（基盤 R12: 間引きは転送
///   タスク層の責務）。速度は [TransferSpeedEma]（α=0.3）+ [formatTransferSpeed]。
/// - `sftp.close()` は絶対に呼ばない（キャッシュ共有の呼び出し側 close 禁止契約）。
class DownloadNotifier extends Notifier<DownloadState> {
  DownloadNotifier({
    DateTime Function()? clock,
    this.progressThrottle = const Duration(milliseconds: 100),
    TransferNotificationService? notificationService,
    SaveAsExporter? exporter,
  }) {
    _clock = clock ?? DateTime.now;
    _ema = TransferSpeedEma(clock: _clock);
    _notification = notificationService ?? _notification;
    _exporter = exporter ?? const FfdSaveAsExporter();
  }

  final SftpDownloadService _service = SftpDownloadService();

  /// 転送通知の更新窓口（テストでは FakeSshForegroundTaskService を注入）。
  /// 既定は既存の SshForegroundTaskService（シングルトン）。
  TransferNotificationService _notification = SshForegroundTaskService();

  /// 「名前を付けて保存」エクスポーター（テストでは FakeSaveAsExporter を注入）。
  /// 既定は flutter_file_dialog 実装の [FfdSaveAsExporter]。
  SaveAsExporter _exporter = const FfdSaveAsExporter();

  /// 設定言語から解決したローカライズ文字列（通知テキストに使用・既存流儀）。
  AppLocalizations get _l10n =>
      l10nForLanguage(ref.read(settingsProvider).language);

  /// 速度算出・間引き判定用の clock（テスト注入可）。
  DateTime Function() _clock = DateTime.now;

  /// state 反映（進捗）の最小間隔。100ms 間引きは転送タスク層（本 Notifier）の責務。
  final Duration progressThrottle;

  TransferSpeedEma _ema = TransferSpeedEma();
  TransferCancelToken? _token;
  StreamSubscription<SshConnectionState>? _connectionSub;
  List<DownloadItemState> _items = [];
  DateTime? _lastProgressAt;

  /// 現在のバッチの保存先（startDownloads/startSingleTmpDownload が設定・キュー完了時に
  /// dispose する）。
  DownloadDestination? _destination;

  /// バッチ（世代）ごとの保存先 dispose 済みフラグ。
  ///
  /// キュー finally と reset() の二重 dispose を防ぐ。フィールド（[._destination]）では
  /// なく「世代」で管理することで、旧バッチの finally が新バッチの保存先（置換後の
  /// フィールド）を誤破棄しない（M1: クロスバッチ誤破棄の構造的排除）。
  final Set<int> _disposedBatches = {};

  /// バッチ無効化カウンタ。startDownloads で新バッチ開始、reset() で無効化し、
  /// 古いバッチの在途コールバック（進捗・完了・キュー後処理）を安全に abort させる
  /// （レビュー HIGH#1: 転送中 reset の RangeError/TypeError 防止）。
  int _generation = 0;

  @override
  DownloadState build() {
    ref.onDispose(() {
      _connectionSub?.cancel();
    });
    return const DownloadState();
  }

  /// ダウンロード一式を開始する（一括・[DownloadDestination] ベース）。
  ///
  /// 先頭で必ず新規 [TransferCancelToken] を生成し、**同名衝突を事前スキャン**する
  /// （`await destination.exists(name)`・Sync API 禁止）。衝突あり →
  /// `phase=awaitingOverwrite` + [DownloadState.collidingItems] 公開（転送は開始しない）／
  /// なし → 順次キューを開始する。失敗は throw せず state へ反映する。
  Future<void> startDownloads(
    List<FileEntry> entries,
    DownloadDestination destination,
  ) async {
    if (state.phase == DownloadPhase.downloading) {
      // 再入ガード: 採用されない保存先を解放してリークを防ぐ（M2・ベストエフォート）。
      unawaited(_disposeOrphan(destination));
      return;
    }

    // awaitingOverwrite 中に新バッチが開始された場合、未 dispose の旧保存先（iOS
    // スコープ等）を解放してから置換する（M2: 参照を失うだけのリーク防止）。
    if (state.phase == DownloadPhase.awaitingOverwrite &&
        _destination != null) {
      unawaited(
        _disposeDestination(batch: _generation, destination: _destination),
      );
    }

    // 先頭で必ず新規トークンを生成（1 度キャンセル→次バッチ即キャンセルの再入バグ防止）。
    // 保存先は SSH 検査より先にフィールドへ設定し、非接続/error return 経路でも必ず
    // _disposeDestination() する（M2: ピッカーが iOS startScope 済みでもスコープ解放）。
    _generation++; // 新バッチ開始（旧バッチの在途コールバックを無効化）。
    _token = TransferCancelToken();
    _ema.reset();
    _lastProgressAt = null;
    _destination = destination;

    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      state = DownloadState(
        phase: DownloadPhase.error,
        errorMessage: _l10n.fileDownloadError,
      );
      unawaited(_disposeDestination()); // 本バッチの保存先を解放（M2）。
      return;
    }

    // ディレクトリは防御的除外（UI 側でファイルのみ・シンボリックリンク除外済み前提）。
    // サニタイズ後にバッチ内で宛先名が重複する場合は自動リネーム（_1 接尾辞・reserved
    // 管理）で安全側に倒す（レビュー LOW#3: 無言の last-writer-wins 防止）。
    // localPath は表示用の name のみ（実パスは destination が管理）。
    final seen = <String>{};
    final items = <DownloadItemState>[];
    for (final e in entries.where((entry) => !entry.isDirectory)) {
      final name = SftpDownloadService.sanitizeLocalName(e.fullPath);
      var resolved = name;
      if (!seen.add(resolved)) {
        resolved = await _firstAvailableName(name, reserved: seen);
        seen.add(resolved);
      }
      items.add(
        DownloadItemState(
          remotePath: e.fullPath,
          name: resolved,
          localPath: resolved,
        ),
      );
    }
    _items = items;
    state = DownloadState(phase: DownloadPhase.selecting, items: _items);

    // 同名衝突の事前スキャン（転送開始前に一括確認・転送中のダイアログ排除）。
    final colliding = <DownloadItemState>[];
    for (final item in _items) {
      if (await _existsInDestination(item.name)) colliding.add(item);
    }
    if (colliding.isNotEmpty) {
      state = DownloadState(
        phase: DownloadPhase.awaitingOverwrite,
        items: _items,
        collidingItems: colliding,
      );
      return;
    }

    state = DownloadState(phase: DownloadPhase.downloading, items: _items);
    await _runQueue(sshClient);
  }

  /// 単一ファイルを tmp 領域へダウンロードし、Save-As でユーザー選択先へエクスポートする。
  ///
  /// フロー:
  /// 1. `getTemporaryDirectory()/sftp_download/<sanitizeLocalName>` へ書込
  ///    （衝突回避のため常に `_1` から採番・実装は [_firstAvailablePath] を参照）。
  /// 2. `phase=downloading` → 順次キュー（再入ガード・generation・切断監視・EMA・
  ///    100ms 間引き）。単一バッチではキューの中間 completed publish を抑止し（M3）、
  ///    最終確定（completed/cancelled/error）は本メソッドに集約する。
  /// 3. 全成功時のみ `phase=exporting` → [SaveAsExporter.export] でユーザー保存先選択。
  ///    - 非 null: `localPath` を戻り値（保存先パスの path 部）で更新 → completed +
  ///      `notifDownloadComplete(1,0,0)`
  ///    - null（Save-As キャンセル）: cancelled + `notifDownloadCancelled`
  ///    - throw: error + `fileDownloadError`
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

    // 先頭で必ず新規トークンを生成（1 度キャンセル→次バッチ即キャンセルの再入バグ防止）。
    final batch = ++_generation; // 新バッチ開始（旧バッチの在途コールバックを無効化）。
    _token = TransferCancelToken();
    _ema.reset();
    _lastProgressAt = null;

    // tmp 領域（app の一時ディレクトリ配下）へダウンロード。衝突回避のため常に `_1`
    // から採番する（前回クラッシュの残骸を上書きしない・実装 [_firstAvailablePath]）。
    final tmpDir = Directory(
      '${(await getTemporaryDirectory()).path}/sftp_download',
    );
    await tmpDir.create(recursive: true);
    final baseName = SftpDownloadService.sanitizeLocalName(entry.fullPath);
    final tmpPath = _firstAvailablePath('${tmpDir.path}/$baseName');
    // 採番後の basename を保存名とする（destination.open の宛先 = tmpPath を一致させる）。
    final tmpName = tmpPath.substring(tmpPath.lastIndexOf('/') + 1);

    final item = DownloadItemState(
      remotePath: entry.fullPath,
      name: tmpName,
      localPath: tmpPath,
    );
    _items = [item];
    _destination = FileDestination(tmpDir.path);
    state = DownloadState(phase: DownloadPhase.downloading, items: _items);
    // M3: 単一バッチは _runQueue の中間 completed publish を抑止する（最終確定は本
    // メソッドに集約）。これにより Save-As 確定前の中間 completed（一時完了表示）と
    // 二重 notifDownloadComplete が解消される。
    await _runQueue(sshClient, publishCompletion: false);

    if (batch != _generation) return; // reset 等で無効化 → export しない。

    // 全成功時のみ Save-As エクスポートへ。転送失敗（未完了・エラー）の最終確定（error）
    // もここで行う（M3: _runQueue は中間 phase を publish しないため）。
    final done = _items[0];
    if (!done.isCompleted || done.isError || (_token?.isCancelled ?? true)) {
      // tmp 残骸の防御的削除（通常は sink.deletePartial で削除済み・ベストエフォート）。
      await _deleteTmpBestEffort(tmpPath);
      // キャンセル/切断時は cancel()/切断ハンドラが phase を確定済みのため上書きしない
      // （downloading のまま残るのは転送失敗のみ・単一バッチの最終確定）。
      if (batch == _generation && state.phase == DownloadPhase.downloading) {
        state = DownloadState(
          phase: DownloadPhase.error,
          items: _items,
          errorMessage: _l10n.fileDownloadError,
        );
        unawaited(_notify(_l10n.fileDownloadError));
      }
      return;
    }

    state = DownloadState(
      phase: DownloadPhase.exporting,
      items: _items,
      speedLabel: state.speedLabel,
    );
    String? exported;
    try {
      exported = await _exporter.export(tmpPath);
    } catch (_) {
      // エクスポート失敗（保存先 I/O エラー等）は phase=error へ。
      if (batch == _generation) {
        state = DownloadState(
          phase: DownloadPhase.error,
          items: _items,
          errorMessage: _l10n.fileDownloadError,
        );
        unawaited(_notify(_l10n.fileDownloadError));
      }
      return;
    } finally {
      // export 後は成功/失敗にかかわらず tmp を削除（ベストエフォート）。
      await _deleteTmpBestEffort(tmpPath);
    }
    if (batch != _generation) return;

    if (exported == null) {
      // Save-As ダイアログのキャンセル → 転送中断（cancelled・確定済み）。
      state = DownloadState(phase: DownloadPhase.cancelled, items: _items);
      unawaited(_notify(_l10n.notifDownloadCancelled));
      return;
    }

    // localPath をエクスポート先（戻り値パス）で更新して completed。
    _updateItem(
      0,
      (it) => it.copyWith(localPath: exported),
      publish: false,
      batch: batch,
    );
    state = DownloadState(
      phase: DownloadPhase.completed,
      items: _items,
      speedLabel: state.speedLabel,
    );
    unawaited(_notify(_l10n.notifDownloadComplete(1, 0, 0)));
  }

  /// 上書き確認の決定を適用し、順次キューを開始する。
  ///
  /// [decisions] は `Map<name, OverwriteChoice>`（UI 側が applyToAll を展開済み）。
  /// `overwrite` は [DownloadItemState.overwrite]=true で保存先の同名を切り詰めて再利用、
  /// `rename` は `_1` 接尾辞で空き名を採番（`destination.exists` + バッチ内 reserved・
  /// LOW#3）して overwrite=true（決定した名前を SAF 側の自動採番で壊さない）。
  /// `skip` はキューから除外。
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
      // startDownloads がフィールドへ設定済みの保存先を解放（M2: iOS スコープ）。
      unawaited(_disposeDestination());
      return;
    }

    final updated = <DownloadItemState>[];
    for (final item in _items) {
      switch (decisions[item.name]) {
        case null:
          // 衝突なし（または決定なし）アイテムはそのまま（overwrite=false）。
          updated.add(item);
        case OverwriteChoice.overwrite:
          // ユーザー明示の上書き: 保存先の同名を切り詰めて再利用する。
          updated.add(item.copyWith(overwrite: true));
        case OverwriteChoice.rename:
          // バッチ内の他アイテム宛先も予約済みとして採番し、重複上書きを防ぐ（LOW#3）。
          final reserved = {for (final it in _items) it.name};
          final newName = await _firstAvailableName(
            item.name,
            reserved: reserved,
          );
          updated.add(
            item.copyWith(name: newName, localPath: newName, overwrite: true),
          );
        case OverwriteChoice.skip:
          updated.add(item.copyWith(isSkipped: true));
        case OverwriteChoice.cancel:
          // #40 batch モードでは不使用の値。安全側にバッチ中断（idle・転送開始しない）。
          _items = [];
          unawaited(_disposeDestination());
          state = const DownloadState();
          return;
      }
    }
    _items = updated;
    state = DownloadState(phase: DownloadPhase.downloading, items: _items);
    await _runQueue(sshClient);
  }

  /// ユーザーキャンセル（sync・冪等）。
  ///
  /// phase ガード（downloading 以外は no-op・2 重キャンセル・completed/error 後も無視）
  /// → トークン cancel → phase=cancelled。在途のダウンロードはチャンク境界で
  /// [TransferCancelledException]（部分削除はサービス側が実施）になる。
  void cancel() {
    if (state.phase != DownloadPhase.downloading) return;
    _token?.cancel();
    state = state.copyWith(phase: DownloadPhase.cancelled);
    unawaited(_notify(_l10n.notifDownloadCancelled));
  }

  /// idle へ戻す（トークン破棄・items クリア・EMA reset・切断監視の購読解除）。
  ///
  /// バッチを無効化（generation++）し、在途キュー（_runQueue）のローカルスナップショット
  /// との世代不一致検知で安全に abort させる（レビュー HIGH#1）。在途 download はトークン
  /// cancel で即中断（部分削除はサービス層が実施）。未 dispose の保存先はここでも
  /// 解放する（キュー finally との二重呼び出しはフラグで防止）。
  void reset() {
    final currentBatch = _generation; // 解放管理用: 旧バッチの世代。
    _generation++; // バッチ無効化（キューは次の検査点で abort）。
    _token?.cancel(); // 在途 download を即中断（部分削除はサービス層）。
    _connectionSub?.cancel();
    _connectionSub = null;
    _token = null; // 破棄（次回 startDownloads が新規生成）。
    _ema.reset();
    _lastProgressAt = null;
    _items = [];
    // 未 dispose なら解放（iOS スコープ等）。フィールドは先にクリアしてから明示世代で
    // 解放する（旧バッチの finally が新バッチの保存先へ触れない・M1）。
    final disposed = _destination;
    _destination = null;
    unawaited(_disposeDestination(batch: currentBatch, destination: disposed));
    state = const DownloadState();
  }

  /// 順次ダウンロードキューを実行する。
  ///
  /// - バッチ開始時に**トークン/世代をローカルスナップショット**し、reset() 等による
  ///   バッチ無効化を世代不一致で検知して安全に abort する（在途 download 完了時の
  ///   `_updateItem`／`!token.isCancelled` が古いバッチへ触れない・HIGH#1）。
  /// - SSH 切断監視: downloading 中に disconnected/error を受けたらトークン cancel +
  ///   phase=error（部分削除はサービス側が実施）。
  /// - キャンセル×切断の競合は phase ガードで一意ロック（先に確定した方が優先・
  ///   サービス側 catch も既に cancelled なら error へ上書きしない）。
  /// - アイテム単位 try/catch: 失敗は isError 記録 + 部分削除（サービス済み）+ 続行。
  /// - 各アイテムは `destination.open(name, overwrite:)` で [DownloadSink] を開き、
  ///   `openSink` としてサービスへ渡す。キュー終了時（finally）に**自分のスナップ
  ///   ショット**の destination を 1 回だけ dispose（iOS スコープ解放・世代管理・M1）。
  /// - [publishCompletion] は一括（true・default）では完了 publish + 通知を、単一
  ///   （false・M3）では抑止し、最終確定を呼び出し側（[startSingleTmpDownload]）に
  ///   委ねる（中間 completed のリーク・二重通知防止）。
  /// - `openSftp()` 失敗は例外を投げず phase=error へ遷移（MEDIUM#2・契約「throw
  ///   しない」）し、保存先も解放する（M2）。
  Future<void> _runQueue(
    SshClient sshClient, {
    bool publishCompletion = true,
  }) async {
    final batch = _generation; // バッチスナップショット（reset 検知用）。
    final token = _token; // トークンスナップショット（_token! の null 参照を回避）。
    final destination = _destination; // 保存先スナップショット（キュー中に解放されない）。
    if (token == null || destination == null) return;

    final SftpClient sftp;
    try {
      sftp = await sshClient.openSftp();
    } catch (_) {
      // openSftp 失敗（isConnected 検査と openSftp の間の切断レース等）: 契約どおり
      // 例外を UI に投げず、phase=error に遷移する（膠着を防ぐ・MEDIUM#2）。
      if (batch == _generation) {
        state = DownloadState(
          phase: DownloadPhase.error,
          items: _items,
          errorMessage: _l10n.fileDownloadError,
        );
        unawaited(_notify(_l10n.fileDownloadError));
      }
      // finally に入る前に return するため、保存先もここで解放する（M2）。
      await _disposeDestination(batch: batch, destination: destination);
      return;
    }
    // NOTE: sftp.close() は呼ばない（キャッシュ共有の SftpClient は呼び出し側で
    // close() を呼んではならない契約・ssh_client.dart）。
    final sub = sshClient.connectionStateStream.listen((connState) {
      // 世代ガード: 旧バッチ（キャンセル〜finally の窓）のリスナーが新バッチの
      // state を error に書き換えない（M4）。
      if (batch != _generation) return;
      if (connState != SshConnectionState.connected &&
          state.phase == DownloadPhase.downloading) {
        token.cancel();
        state = state.copyWith(
          phase: DownloadPhase.error,
          errorMessage: _l10n.fileDownloadError,
        );
        // 失敗理由の通知更新（次の SSH 状態変化まで維持）。
        unawaited(_notify(_l10n.notifDownloadFailed(_l10n.sshConnectionLost)));
      }
    });
    _connectionSub = sub;
    try {
      for (var i = 0; i < _items.length; i++) {
        if (batch != _generation) return; // reset 等で無効化されていたら abort。
        if (token.isCancelled) break;
        final item = _items[i];
        if (item.isSkipped) continue; // スキップ決定はキューから除外（転送しない）。
        try {
          final result = await _service.download(
            sftp: sftp,
            remotePath: item.remotePath,
            openSink: () =>
                destination.open(item.name, overwrite: item.overwrite),
            cancellation: token,
            onProgress: (done, total) => _onProgress(i, done, total, batch),
          );
          if (batch != _generation) return; // 在途完了が古いバッチへ触れない。
          // アイテム完了は即時反映（100ms 間引きの対象外）。
          _updateItem(
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
          if (batch != _generation) return;
          // アイテム単位の失敗（転送エラー・SSH 断・書込 I/O エラー＝ディスクフル含む）。
          // 部分削除はサービス層が実施済み。次のアイテムへ続行する。
          _updateItem(
            i,
            (it) => it.copyWith(isError: true, errorMessage: '$e'),
            publish: true,
            batch: batch,
          );
        }
        // アイテム境界: 速度区間をリセット（全体速度の過小表示防止・Concern 27）。
        _ema.reset();
        _lastProgressAt = null;
      }
      if (batch != _generation) return;
      if (!token.isCancelled) {
        // 単一バッチ（publishCompletion: false）は中間 completed を publish しない
        // （M3: 最終確定を startSingleTmpDownload に集約・二重通知も防止）。
        if (publishCompletion) {
          final hasErrors = _items.any((i) => i.isError);
          state = DownloadState(
            phase: DownloadPhase.completed,
            items: _items,
            errorMessage: hasErrors ? _l10n.fileDownloadError : null,
            speedLabel: state.speedLabel,
          );
          // 完了サマリ（成功 a / 失敗 b / スキップ c）を通知へ残す。
          unawaited(
            _notify(
              _l10n.notifDownloadComplete(
                state.completedCount,
                state.failedCount,
                state.skippedCount,
              ),
            ),
          );
        }
      }
      // キャンセル/切断時は既確定の phase（cancelled/error）を維持する。
    } finally {
      await sub.cancel();
      if (identical(_connectionSub, sub)) _connectionSub = null;
      // このバッチの保存先（スナップショット）を解放する。フィールドではなく自分の
      // スナップショットを対象にするため、旧バッチの finally が新バッチの保存先
      // （置換後の _destination）を破棄することはない（M1・世代管理）。
      await _disposeDestination(batch: batch, destination: destination);
    }
  }

  /// 進捗コールバック（毎チャンク呼ばれる）。
  ///
  /// 内部累積（_items）は毎チャンク更新して完了時の正確さを保証し、
  /// **state への反映（bytesReceived/fraction/speedLabel 含む state 更新全体）は
  /// 100ms 間引き**する（基盤 R12・間引き責務は転送タスク層＝本 Notifier）。
  /// アイテム完了時は [_updateItem] が即時反映する。
  void _onProgress(int index, int doneBytes, int totalBytes, int batch) {
    if (batch != _generation) return; // 古いバッチ（reset 後）の進捗は無視（HIGH#1）。
    final items = List<DownloadItemState>.of(_items);
    final prev = items[index];
    items[index] = prev.copyWith(
      bytesReceived: doneBytes,
      totalBytes: totalBytes > 0 ? totalBytes : prev.totalBytes,
    );
    _items = items;

    final now = _clock();
    final shouldPublish =
        _lastProgressAt == null ||
        now.difference(_lastProgressAt!) >= progressThrottle;
    if (!shouldPublish) return;
    _lastProgressAt = now;
    final cumulative = items.fold<int>(0, (s, i) => s + i.bytesReceived);
    final speed = _ema.update(cumulative, now: now);
    final speedLabel = formatTransferSpeed(speed);
    state = state.copyWith(items: items, speedLabel: speedLabel);
    // 進捗通知（100ms 間引き publish と同期・n/total・%・bytes・速度）。
    final fraction = state.fraction;
    final percent = fraction == null ? 0 : (fraction * 100).round();
    unawaited(
      _notify(
        _l10n.notifDownloadProgress(
          index + 1,
          items.length,
          percent,
          _bytesLabel(state.receivedBytes),
          speedLabel,
        ),
      ),
    );
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

  void _updateItem(
    int index,
    DownloadItemState Function(DownloadItemState) change, {
    required bool publish,
    required int batch,
  }) {
    if (batch != _generation) return; // 古いバッチ（reset 後）には書き込まない（HIGH#1）。
    final items = List<DownloadItemState>.of(_items);
    items[index] = change(items[index]);
    _items = items;
    if (publish) {
      state = state.copyWith(items: items);
    }
  }

  /// 保存先のリソースを解放する（バッチ単位・1 回だけ・クロスバッチ誤破棄防止 M1）。
  ///
  /// [_runQueue] は自分が保持するスナップショット（batch + destination）を明示して
  /// 呼ぶ。reset()・エラー return 等はバッチ/保存先を省略し、現在のフィールドを対象に
  /// する（既定は現在世代）。
  ///
  /// - 同一バッチ（世代）の二重 dispose は [_disposedBatches] で抑止（キュー finally と
  ///   reset() の両立）。
  /// - フィールド（[_destination]）のクリアは「現在世代かつ同一オブジェクト」の場合のみ
  ///   行うため、旧バッチの finally は新バッチのフィールド（置換済みの保存先）を
  ///   null 化しない。
  /// - 失敗はベストエフォート（握りつぶし）。
  Future<void> _disposeDestination({
    int? batch,
    DownloadDestination? destination,
  }) async {
    final b = batch ?? _generation;
    if (_disposedBatches.contains(b)) return; // このバッチは dispose 済み。
    final target = destination ?? _destination;
    if (target == null) return;
    _disposedBatches.add(b);
    try {
      await target.dispose();
    } catch (_) {
      // スコープ解放失敗はベストエフォート（転送結果に影響させない）。
    }
    if (b == _generation && identical(_destination, target)) {
      _destination = null;
    }
  }

  /// バッチに採用されなかった保存先（再入ガード等）を解放する（ベストエフォート）。
  Future<void> _disposeOrphan(DownloadDestination destination) async {
    try {
      await destination.dispose();
    } catch (_) {
      // 採用されない保存先の解放失敗は握りつぶし（転送結果に影響させない）。
    }
  }

  /// 保存先に [name] のファイルが存在するか（ベストエフォート・失敗は false 扱い）。
  ///
  /// 存在確認の失敗（iOS スコープ未開始等）は「非衝突」として扱い、実際の `open()`
  /// 失敗としてアイテム単位で顕在化させる。
  Future<bool> _existsInDestination(String name) async {
    final destination = _destination;
    if (destination == null) return false;
    try {
      return await destination.exists(name);
    } catch (_) {
      return false;
    }
  }

  /// tmp ファイル削除（ベストエフォート・throw しない）。
  Future<void> _deleteTmpBestEffort(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // 残骸は握りつぶし（削除失敗は転送結果に影響させない）。
    }
  }

  /// `name.ext` → `name_1.ext` → `name_2.ext`…の順で保存先に存在せず、[reserved] にも
  /// 含まれない空き名を採番する（`destination.exists` ベース・Sync API 禁止）。
  Future<String> _firstAvailableName(
    String name, {
    Set<String>? reserved,
  }) async {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = '${base}_1$ext';
    for (
      var n = 2;
      await _existsInDestination(candidate) ||
          (reserved?.contains(candidate) ?? false);
      n++
    ) {
      candidate = '${base}_$n$ext';
    }
    return candidate;
  }

  /// `name.ext` → `name_1.ext` → `name_2.ext`…の順で空き名を採番する。
  ///
  /// **最初の候補は常に `name_1.ext`** であり、`name.ext` そのものは存在検査しない
  /// （実装は常に `_1` から採番する仕様・一括の [_firstAvailableName] と同様）。例:
  /// `data.bin` が未存在でも `data_1.bin` を返す（衝突回避は `_1` 採番で常に成立）。
  /// ファイル実パスベース（単一 tmp ダウンロード用）。[reserved] は同一バッチ内で既に
  /// 割当済みの宛先集合（バッチ内重複の自動リネームでも使用・LOW#3）。
  String _firstAvailablePath(String localPath, {Set<String>? reserved}) {
    final dot = localPath.lastIndexOf('.');
    final base = dot > 0 ? localPath.substring(0, dot) : localPath;
    final ext = dot > 0 ? localPath.substring(dot) : '';
    var candidate = '${base}_1$ext';
    for (
      var n = 2;
      File(candidate).existsSync() || (reserved?.contains(candidate) ?? false);
      n++
    ) {
      candidate = '${base}_$n$ext';
    }
    return candidate;
  }
}

/// ダウンロード状態プロバイダー（非 AutoDispose・画面破棄後も転送継続）。
final downloadProvider = NotifierProvider<DownloadNotifier, DownloadState>(
  DownloadNotifier.new,
);
