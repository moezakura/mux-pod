import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_lookup.dart';
import '../services/background/foreground_task_service.dart';
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

  /// 端末上の保存先パス（呼び出し側がサニタイズ済み basename + 確定 dir で決定）。
  final String localPath;

  /// 転送エラー（書込 I/O エラー含む）で失敗したか。
  final bool isError;

  /// 上書き確認で「スキップ」決定されたか（キューから除外）。
  final bool isSkipped;

  /// 転送が正常に完了したか（集計 completedCount の正確化のための拡張）。
  final bool isCompleted;

  /// 失敗理由（アイテム単位のエラー詳細）。
  final String? errorMessage;

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
  });

  DownloadItemState copyWith({
    String? localPath,
    int? totalBytes,
    int? bytesReceived,
    bool? isError,
    bool? isSkipped,
    bool? isCompleted,
    String? errorMessage,
  }) {
    return DownloadItemState(
      remotePath: remotePath,
      name: name,
      localPath: localPath ?? this.localPath,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      isError: isError ?? this.isError,
      isSkipped: isSkipped ?? this.isSkipped,
      isCompleted: isCompleted ?? this.isCompleted,
      errorMessage: errorMessage ?? this.errorMessage,
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
  int get completedCount => items.where((i) => i.isCompleted && !i.isError).length;

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
  }) {
    _clock = clock ?? DateTime.now;
    _ema = TransferSpeedEma(clock: _clock);
    _notification = notificationService ?? _notification;
  }

  final SftpDownloadService _service = SftpDownloadService();

  /// 転送通知の更新窓口（テストでは FakeSshForegroundTaskService を注入）。
  /// 既定は既存の SshForegroundTaskService（シングルトン）。
  TransferNotificationService _notification = SshForegroundTaskService();

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

  /// ダウンロード一式を開始する。
  ///
  /// 先頭で必ず新規 [TransferCancelToken] を生成し、**同名衝突を事前スキャン**する。
  /// 衝突あり → `phase=awaitingOverwrite` + [DownloadState.collidingItems] 公開（転送は
  /// 開始しない）／なし → 順次キューを開始する。失敗は throw せず state へ反映する。
  Future<void> startDownloads(List<FileEntry> entries, String localDir) async {
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
    _generation++; // 新バッチ開始（旧バッチの在途コールバックを無効化）。
    _token = TransferCancelToken();
    _ema.reset();
    _lastProgressAt = null;
    final dir = localDir.endsWith('/') ? localDir : '$localDir/';
    // ディレクトリは防御的除外（UI 側でファイルのみ・シンボリックリンク除外済み前提）。
    // サニタイズ後にバッチ内で宛先が重複する場合は自動リネーム（_1 接尾辞）で
    // 安全側に倒す（レビュー LOW#3: 無言の last-writer-wins 防止）。
    final seen = <String>{};
    final items = <DownloadItemState>[];
    for (final e in entries.where((entry) => !entry.isDirectory)) {
      final name = SftpDownloadService.sanitizeLocalName(e.fullPath);
      var localPath = '$dir$name';
      if (!seen.add(localPath)) {
        localPath = _firstAvailablePath(localPath, reserved: seen);
        seen.add(localPath);
      }
      items.add(
        DownloadItemState(
          remotePath: e.fullPath,
          name: name,
          localPath: localPath,
        ),
      );
    }
    _items = items;
    state = DownloadState(phase: DownloadPhase.selecting, items: _items);

    // 同名衝突の事前スキャン（転送開始前に一括確認・転送中のダイアログ排除）。
    final colliding = <DownloadItemState>[
      for (final item in _items)
        if (File(item.localPath).existsSync()) item,
    ];
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

  /// 上書き確認の決定を適用し、順次キューを開始する。
  ///
  /// [decisions] は `Map<localPath, OverwriteChoice>`（UI 側が applyToAll を展開済み）。
  /// `rename` は `_1` 接尾辞で空き名を採番（スキャン後の予期せぬ衝突も同経路で自動
  /// リネーム＝安全側・上書きはユーザー明示のみ）。`skip` はキューから除外。
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
      return;
    }

    final updated = <DownloadItemState>[];
    for (final item in _items) {
      switch (decisions[item.localPath]) {
        case null:
        case OverwriteChoice.overwrite:
          updated.add(item);
        case OverwriteChoice.rename:
          // バッチ内の他アイテム宛先も予約済みとして採番し、重複上書きを防ぐ（LOW#3）。
          final reserved = {for (final it in _items) it.localPath};
          updated.add(
            item.copyWith(
              localPath: _firstAvailablePath(item.localPath, reserved: reserved),
            ),
          );
        case OverwriteChoice.skip:
          updated.add(item.copyWith(isSkipped: true));
        case OverwriteChoice.cancel:
          // #40 batch モードでは不使用の値。安全側にバッチ中断（idle・転送開始しない）。
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
  /// cancel で即中断（部分削除はサービス層が実施）。
  void reset() {
    _generation++; // バッチ無効化（キューは次の検査点で abort）。
    _token?.cancel(); // 在途 download を即中断（部分削除はサービス層）。
    _connectionSub?.cancel();
    _connectionSub = null;
    _token = null; // 破棄（次回 startDownloads が新規生成）。
    _ema.reset();
    _lastProgressAt = null;
    _items = [];
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
  /// - `openSftp()` 失敗は例外を投げず phase=error へ遷移（MEDIUM#2・契約「throw しない」）。
  Future<void> _runQueue(SshClient sshClient) async {
    final batch = _generation; // バッチスナップショット（reset 検知用）。
    final token = _token; // トークンスナップショット（_token! の null 参照を回避）。
    if (token == null) return;

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
      return;
    }
    // NOTE: sftp.close() は呼ばない（キャッシュ共有の SftpClient は呼び出し側で
    // close() を呼んではならない契約・ssh_client.dart）。
    final sub = sshClient.connectionStateStream.listen((connState) {
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
            localPath: item.localPath,
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
      // キャンセル/切断時は既確定の phase（cancelled/error）を維持する。
    } finally {
      await sub.cancel();
      if (identical(_connectionSub, sub)) _connectionSub = null;
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
    state = state.copyWith(
      items: items,
      speedLabel: speedLabel,
    );
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
  String _bytesLabel(int bytes) =>
      FileEntry(name: '', fullPath: '', isDirectory: false, size: bytes)
          .formattedSize;

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

  /// `name.ext` → `name_1.ext` → `name_2.ext`…の順で既存と衝突しない空き名を採番する。
  ///
  /// [reserved] は同一バッチ内で既に割当済みの宛先集合（バッチ内重複の自動リネーム
  /// でも使用・LOW#3）。
  String _firstAvailablePath(String localPath, {Set<String>? reserved}) {
    final dot = localPath.lastIndexOf('.');
    final base = dot > 0 ? localPath.substring(0, dot) : localPath;
    final ext = dot > 0 ? localPath.substring(dot) : '';
    var candidate = '${base}_1$ext';
    for (var n = 2;
        File(candidate).existsSync() || (reserved?.contains(candidate) ?? false);
        n++) {
      candidate = '${base}_$n$ext';
    }
    return candidate;
  }
}

/// ダウンロード状態プロバイダー（非 AutoDispose・画面破棄後も転送継続）。
final downloadProvider =
    NotifierProvider<DownloadNotifier, DownloadState>(DownloadNotifier.new);