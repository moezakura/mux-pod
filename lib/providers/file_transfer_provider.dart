import 'dart:async';

import 'package:dartssh2/dartssh2.dart' show SftpClient;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sftp/sftp_service.dart';
import '../services/sftp/transfer_progress.dart';
import '../services/ssh/ssh_connection_state.dart';
import 'settings_provider.dart';
import 'ssh_provider.dart';

/// ファイル転送（#41・SFTP ブラウザ画面起点）のフェーズ。
enum FileTransferPhase {
  /// 待機中（転送なし）
  idle,

  /// 衝突確認中（prepare 完了・UI がダイアログで解決を確認する）
  confirming,

  /// 転送中（並列・設定の同時数上限）
  uploading,

  /// 全ファイル確定（成功 / 部分失敗は items で表現）
  completed,

  /// ユーザーキャンセルにより中断
  cancelled,

  /// 準備エラー（SSH 未接続など）
  error,
}

/// 個別ファイルの転送状態。
enum FileTransferItemStatus { pending, uploading, done, failed, skipped }

/// 衝突確認ダイアログ（基盤 showOverwriteConfirmDialog）の結果。
enum ConflictResolution {
  /// 未解決（UI 確認前）
  none,

  /// 上書き
  overwrite,

  /// 自動リネーム
  rename,
}

/// 転送対象 1 ファイルの状態（イミュータブル・copyWith で更新）。
class FileTransferItem {
  /// ローカル側の表示名（元名・日本語保持）。
  final String fileName;

  /// 事前取得した総バイト数。
  final int totalBytes;

  /// prepare 時点でリモート送信先に同名が存在するか。
  final bool conflict;

  /// UI が確定した衝突の解決方法。
  final ConflictResolution resolution;

  /// 転送状態。
  final FileTransferItemStatus status;

  /// 最新の進捗（uploading 中）。
  final TransferProgress? progress;

  /// 確定した送信先リモートパス（成功時）。
  final String? remotePath;

  /// 失敗理由（failed 時）。
  final Object? error;

  const FileTransferItem({
    required this.fileName,
    required this.totalBytes,
    this.conflict = false,
    this.resolution = ConflictResolution.none,
    this.status = FileTransferItemStatus.pending,
    this.progress,
    this.remotePath,
    this.error,
  });

  bool get isSettled =>
      status == FileTransferItemStatus.done ||
      status == FileTransferItemStatus.failed ||
      status == FileTransferItemStatus.skipped;

  FileTransferItem copyWith({
    ConflictResolution? resolution,
    FileTransferItemStatus? status,
    TransferProgress? progress,
    String? remotePath,
    Object? error,
  }) {
    return FileTransferItem(
      fileName: fileName,
      totalBytes: totalBytes,
      conflict: conflict,
      resolution: resolution ?? this.resolution,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      remotePath: remotePath ?? this.remotePath,
      error: error ?? this.error,
    );
  }
}

/// ファイル転送全体の状態。
class FileTransferState {
  final FileTransferPhase phase;
  final List<FileTransferItem> items;

  /// 送信先ディレクトリ（SFTP ブラウザで現在閲覧中のパス）。
  final String? remoteDir;

  /// 準備エラーの種別（error 時。UI 側で l10n 化する構造化キー）。
  final String? errorMessage;

  const FileTransferState({
    this.phase = FileTransferPhase.idle,
    this.items = const [],
    this.remoteDir,
    this.errorMessage,
  });

  /// 確定済み（成功/失敗/スキップ）ファイル数。
  int get settledCount => items.where((item) => item.isSettled).length;

  /// 成功したファイル数。
  int get doneCount =>
      items.where((item) => item.status == FileTransferItemStatus.done).length;

  /// 衝突が未解決（確認が必要）な項目のインデックス。
  List<int> get conflictIndexes => [
    for (var i = 0; i < items.length; i++)
      if (items[i].conflict &&
          items[i].resolution == ConflictResolution.none &&
          items[i].status == FileTransferItemStatus.pending)
        i,
  ];

  bool get hasConflicts => conflictIndexes.isNotEmpty;

  FileTransferState copyWith({
    FileTransferPhase? phase,
    List<FileTransferItem>? items,
    String? remoteDir,
    String? errorMessage,
  }) {
    return FileTransferState(
      phase: phase ?? this.phase,
      items: items ?? this.items,
      remoteDir: remoteDir ?? this.remoteDir,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 汎用ファイル転送を管理する Notifier（#41）。
///
/// 既存の画像転送（ImageTransferNotifier / #29）とは独立して共存する。
/// UI（FileBrowserScreen）は prepare → （衝突があれば基盤
/// showOverwriteConfirmDialog で解決を setConflictResolution）→ start の順で使う。
class FileTransferNotifier extends Notifier<FileTransferState> {
  final _sftpService = SftpService();

  /// prepare で受け取ったローカルファイル（start で消費）。
  List<PlatformFile> _pendingFiles = [];

  /// ファイル毎のキャンセルトークン（start で生成）。
  final List<TransferCancelToken> _cancelTokens = [];

  /// 全体キャンセル（cancelAll / SSH 切断で使用）。
  TransferCancelToken? _globalToken;

  StreamSubscription? _connectionSub;

  @override
  FileTransferState build() {
    ref.onDispose(() {
      _connectionSub?.cancel();
      _globalToken?.cancel();
    });
    return const FileTransferState();
  }

  /// 選択済みファイルを準備し、送信先との衝突を検出する。
  ///
  /// 成功すると phase=confirming になる（conflict が無ければ UI は即 start してよい）。
  Future<void> prepare({
    required List<PlatformFile> files,
    required String remoteDir,
  }) async {
    if (files.isEmpty) {
      return;
    }

    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      state = state.copyWith(
        phase: FileTransferPhase.error,
        errorMessage: 'ssh-not-available',
      );
      return;
    }

    final sftp = await sshClient.openSftp();

    final items = <FileTransferItem>[];
    for (final file in files) {
      final size = await file.length();
      final remotePath = SftpService.safeRemotePath(remoteDir, file.name);
      final exists = await SftpService.remoteFileExists(sftp, remotePath);
      items.add(
        FileTransferItem(
          fileName: file.name,
          totalBytes: size,
          conflict: exists,
        ),
      );
    }

    _pendingFiles = List.of(files);
    state = FileTransferState(
      phase: FileTransferPhase.confirming,
      items: items,
      remoteDir: remoteDir,
    );
  }

  /// 衝突確認ダイアログの結果を記録する（UI が呼ぶ）。
  void setConflictResolution(int index, ConflictResolution resolution) {
    if (index < 0 || index >= state.items.length) return;
    final items = List<FileTransferItem>.of(state.items);
    items[index] = items[index].copyWith(resolution: resolution);
    state = state.copyWith(items: items);
  }

  /// 転送を開始する（並列数は設定値・1..8 に制限）。
  Future<void> start() async {
    if (state.phase != FileTransferPhase.confirming) return;

    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      state = state.copyWith(
        phase: FileTransferPhase.error,
        errorMessage: 'ssh-not-available',
      );
      return;
    }
    final sftp = await sshClient.openSftp();

    final settings = ref.read(settingsProvider);
    final remoteDir = state.remoteDir!;
    final files = List.of(_pendingFiles);
    final initialItems = List<FileTransferItem>.of(state.items);

    // 最終ファイル名の確定:
    // - 衝突なし → 元名のまま
    // - 衝突 + overwrite → 元名（truncate 上書き）
    // - 衝突 + rename / 設定 autoRename → generateUniqueName
    // - 衝突 + none（prompt のまま未確認で start）→ 安全側のスキップ扱い
    // ※ バッチ内の重複名は後続を自動リネームして誤上書きを防ぐ
    final claimedNames = <String>{};
    final finalNames = <String>[];
    var items = List<FileTransferItem>.of(initialItems);
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      var name = item.fileName;
      var status = FileTransferItemStatus.pending;
      if (item.conflict) {
        switch (item.resolution) {
          case ConflictResolution.overwrite:
            name = item.fileName;
          case ConflictResolution.rename:
            name = SftpService.generateUniqueName(item.fileName);
          case ConflictResolution.none:
            if (settings.uploadConflictPolicy ==
                TransferConflictPolicy.autoRename) {
              name = SftpService.generateUniqueName(item.fileName);
            } else {
              // 確認を経ずに開始された衝突は安全側（スキップ）に倒す
              status = FileTransferItemStatus.skipped;
            }
        }
      }
      while (claimedNames.contains(name) &&
          status == FileTransferItemStatus.pending) {
        name = SftpService.generateUniqueName(name);
      }
      claimedNames.add(name);
      finalNames.add(name);
      if (status != items[i].status) {
        items[i] = items[i].copyWith(status: status);
      }
    }

    _globalToken = TransferCancelToken();
    _cancelTokens
      ..clear()
      ..addAll(List.generate(items.length, (_) => TransferCancelToken()));

    state = state.copyWith(phase: FileTransferPhase.uploading, items: items);

    // SSH 切断監視（image_transfer / file_browser と同じパターン）。
    _connectionSub?.cancel();
    _connectionSub = sshClient.connectionStateStream.listen((connState) {
      if (connState == SshConnectionState.disconnected ||
          connState == SshConnectionState.error) {
        if (state.phase == FileTransferPhase.uploading) {
          _globalToken?.cancel();
        }
      }
    });

    try {
      final queue = <int>[
        for (var i = 0; i < items.length; i++)
          if (items[i].status == FileTransferItemStatus.pending) i,
      ];
      final concurrency = settings.uploadConcurrency.clamp(1, 8);
      final workerCount = concurrency > queue.length
          ? queue.length
          : concurrency;

      Future<void> worker() async {
        while (queue.isNotEmpty) {
          if (_globalToken?.isCancelled ?? false) return;
          final index = queue.removeAt(0);
          await _uploadOne(
            sftp: sftp,
            remoteDir: remoteDir,
            finalName: finalNames[index],
            file: files[index],
            totalBytes: initialItems[index].totalBytes,
            index: index,
            cancelToken: _cancelTokens[index],
            globalToken: _globalToken!,
            chunkSize: settings.uploadChunkKb * 1024,
          );
        }
      }

      await Future.wait(List.generate(workerCount, (_) => worker()));
    } finally {
      _connectionSub?.cancel();
      _connectionSub = null;
    }

    // 全体確定（未完の項目はスキップ扱い。全体キャンセル時は cancelled）。
    items = List.of(state.items);
    for (var i = 0; i < items.length; i++) {
      if (items[i].status == FileTransferItemStatus.pending ||
          items[i].status == FileTransferItemStatus.uploading) {
        items[i] = items[i].copyWith(status: FileTransferItemStatus.skipped);
      }
    }
    final cancelled = _globalToken?.isCancelled ?? false;
    state = state.copyWith(
      phase: cancelled
          ? FileTransferPhase.cancelled
          : FileTransferPhase.completed,
      items: items,
    );
  }

  Future<void> _uploadOne({
    required SftpClient sftp,
    required String remoteDir,
    required String finalName,
    required PlatformFile file,
    required int totalBytes,
    required int index,
    required TransferCancelToken cancelToken,
    required TransferCancelToken globalToken,
    required int chunkSize,
  }) async {
    _updateItem(
      index,
      (item) => item.copyWith(status: FileTransferItemStatus.uploading),
    );
    try {
      final result = await _sftpService.uploadStream(
        sftp: sftp,
        remoteDir: remoteDir,
        filename: finalName,
        source: file.readAsByteStream(),
        totalBytes: totalBytes,
        chunkSize: chunkSize,
        cancelToken: _CombinedCancelToken(globalToken, cancelToken),
        onProgress: (progress) =>
            _updateItem(index, (item) => item.copyWith(progress: progress)),
      );
      _updateItem(
        index,
        (item) => item.copyWith(
          status: FileTransferItemStatus.done,
          remotePath: result.remotePath,
        ),
      );
    } on TransferCancelledException {
      _updateItem(
        index,
        (item) => item.copyWith(status: FileTransferItemStatus.skipped),
      );
    } catch (e) {
      _updateItem(
        index,
        (item) =>
            item.copyWith(status: FileTransferItemStatus.failed, error: e),
      );
    }
  }

  void _updateItem(
    int index,
    FileTransferItem Function(FileTransferItem) transform,
  ) {
    if (index < 0 || index >= state.items.length) return;
    final items = List<FileTransferItem>.of(state.items);
    items[index] = transform(items[index]);
    state = state.copyWith(items: items);
  }

  /// 全ファイルの転送をキャンセルする（部分ファイルはサービス側で削除）。
  void cancelAll() {
    _globalToken?.cancel();
    for (final token in _cancelTokens) {
      token.cancel();
    }
  }

  /// 指定ファイルのみキャンセルする。
  void cancelFile(int index) {
    if (index < 0 || index >= _cancelTokens.length) return;
    _cancelTokens[index].cancel();
  }

  /// 状態をリセットする（完了/キャンセル/エラー後）。
  void reset() {
    _globalToken?.cancel();
    _connectionSub?.cancel();
    _connectionSub = null;
    _pendingFiles = [];
    _cancelTokens.clear();
    state = const FileTransferState();
  }
}

/// 全体キャンセルとファイル個別キャンセルのいずれかで中止する複合トークン。
class _CombinedCancelToken extends TransferCancelToken {
  final TransferCancelToken global;
  final TransferCancelToken individual;

  _CombinedCancelToken(this.global, this.individual);

  @override
  bool get isCancelled => global.isCancelled || individual.isCancelled;

  @override
  void cancel() => individual.cancel();
}

/// ファイル転送プロバイダー。
final fileTransferProvider =
    NotifierProvider<FileTransferNotifier, FileTransferState>(
      FileTransferNotifier.new,
    );
