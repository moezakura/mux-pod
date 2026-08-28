import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'transfer_progress.dart';

/// SFTPアップロード結果
class SftpUploadResult {
  final String remotePath;
  final int bytesWritten;

  const SftpUploadResult({
    required this.remotePath,
    required this.bytesWritten,
  });
}

/// SFTPアップロードサービス
class SftpService {
  static const _uuid = Uuid();
  static final _safeCharsRegex = RegExp(r'[^a-zA-Z0-9._-]');

  /// [uploadStream] の既定チャンクサイズ（書き込み要求の粒度）。
  ///
  /// dartssh2 の SftpFileWriter は内部で 16KB パケットに再分割するため、
  /// この値は進捗通知の粒度とバッファ量のバランスを決める。
  static const int defaultChunkSize = 256 * 1024;

  /// ファイル名をサニタイズ（安全な文字のみ許可）
  ///
  /// [a-zA-Z0-9._-] 以外の文字は `_` に置換する。
  ///
  /// ※ #41 の汎用アップロード（[uploadStream]）では日本語名を保持するため
  /// この関数を使わず [safeRemotePath] でパス構造のみを防御する。
  static String sanitizeFilename(String raw) {
    if (raw.isEmpty) return 'unnamed';
    return raw.replaceAll(_safeCharsRegex, '_');
  }

  /// タイムスタンプ + UUID短縮でユニークファイル名を生成
  ///
  /// 例: img_20260403_143025_a3f2.png
  static String generateFilename(String prefix, String extension) {
    final timestamp = _timestamp();
    final shortUuid = _uuid.v4().substring(0, 4);
    final sanitizedExt = extension.startsWith('.')
        ? extension.substring(1)
        : extension;
    return '${sanitizeFilename(prefix)}${timestamp}_$shortUuid.$sanitizedExt';
  }

  /// 元のファイル名ベースでユニークファイル名を生成（#41 リネーム選択用）。
  ///
  /// 元名（日本語等の多バイト名を含む）の拡張子を保持し、
  /// `名前_YYYYMMDD_HHMMSS_uuid4.拡張子` 形式で衝突を回避する。
  /// 例: report.pdf -> report_20260403_143025_a3f2.pdf
  static String generateUniqueName(String originalName) {
    final base = p.basename(originalName);
    final dotIndex = base.lastIndexOf('.');
    final hasExtension = dotIndex > 0 && dotIndex < base.length - 1;
    final stem = hasExtension ? base.substring(0, dotIndex) : base;
    final extension = hasExtension ? base.substring(dotIndex) : '';
    final separator = stem.isEmpty || stem.endsWith('_') || stem.endsWith('-')
        ? ''
        : '_';
    final timestamp = _timestamp();
    final shortUuid = _uuid.v4().substring(0, 4);
    return '$stem$separator${timestamp}_$shortUuid$extension';
  }

  /// リモートディレクトリとファイル名を安全に連結する（パストラバーサル防御）。
  ///
  /// - ファイル名は [p.basename] でパス構造（`/`・`..`）を除去する
  /// - ディレクトリは [p.normalize] で正規化する
  /// - 日本語等の多バイトファイル名はそのまま保持される（🤝#3）
  static String safeRemotePath(String remoteDir, String filename) {
    final dir = p.normalize(remoteDir.isEmpty ? '.' : remoteDir);
    return p.join(dir, p.basename(filename));
  }

  /// リモートパスにファイル/ディレクトリが存在するか（衝突検出用）。
  ///
  /// 存在する場合 true、SftpStatusError（No such file 等）の場合 false。
  static Future<bool> remoteFileExists(
    SftpClient sftp,
    String remotePath,
  ) async {
    try {
      await sftp.stat(remotePath);
      return true;
    } on SftpStatusError {
      return false;
    }
  }

  /// リモートディレクトリの存在確認・作成
  Future<void> ensureDirectory(SftpClient sftp, String remotePath) async {
    try {
      await sftp.stat(remotePath);
    } on SftpStatusError {
      await sftp.mkdir(remotePath);
    }
  }

  /// バイト全体をアップロード（既存API・#29 画像フロー互換）。
  ///
  /// 内部は [uploadStream] への移譲。進捗コールバックは従来どおり
  /// 0.0〜1.0 の double。
  Future<SftpUploadResult> upload({
    required SftpClient sftp,
    required String remoteDir,
    required String filename,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  }) {
    return uploadStream(
      sftp: sftp,
      remoteDir: remoteDir,
      filename: filename,
      source: Stream.value(bytes),
      totalBytes: bytes.length,
      onProgress: onProgress == null
          ? null
          : (progress) => onProgress(progress.fraction ?? 1.0),
    );
  }

  /// ストリーム入力の汎用アップロード（#41）。
  ///
  /// - [source]: ローカルファイルの読み込みストリーム（例: XFile.openRead()）。
  ///   全量メモリ展開せず、[chunkSize] 単位に遅延分割して書き込む（OOM 回避）。
  /// - [totalBytes]: 事前取得した総バイト数。0 以下は「サイズ未知」扱い
  ///   （進捗は速度のみ表示）。
  /// - [cancelToken]: キャンセル要求。検知時に `SftpFileWriter.abort()` で
  ///   書き込みを即時中断し、部分ファイルを削除して
  ///   [TransferCancelledException] を投げる。
  /// - [onProgress]: 進捗通知。[progressInterval] 間引き＋
  ///   [TransferSpeedEma] による速度付き（終了時は必ず最終値を通知）。
  ///
  /// 失敗時（キャンセル・エラー共通）は部分ファイルを削除して rethrow する。
  Future<SftpUploadResult> uploadStream({
    required SftpClient sftp,
    required String remoteDir,
    required String filename,
    required Stream<Uint8List> source,
    required int totalBytes,
    int chunkSize = defaultChunkSize,
    TransferCancelToken? cancelToken,
    void Function(TransferProgress progress)? onProgress,
    Duration progressInterval = const Duration(milliseconds: 100),
  }) async {
    final effectiveChunkSize = chunkSize <= 0 ? defaultChunkSize : chunkSize;
    final remotePath = safeRemotePath(remoteDir, filename);
    await ensureDirectory(sftp, p.dirname(remotePath));

    SftpFile? file;
    try {
      file = await sftp.open(
        remotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );

      final speedEma = TransferSpeedEma();
      final stopwatch = Stopwatch()..start();
      // 初回は必ず通知するため、前回通知時刻を十分過去に初期化する。
      var lastNotifyElapsed = -progressInterval.inMilliseconds;
      final effectiveTotal = totalBytes > 0 ? totalBytes : 0;

      void handleProgress(int ackedBytes) {
        if (onProgress == null) return;
        final elapsed = stopwatch.elapsedMilliseconds;
        if (elapsed - lastNotifyElapsed < progressInterval.inMilliseconds &&
            ackedBytes < effectiveTotal) {
          return;
        }
        lastNotifyElapsed = elapsed;
        onProgress(
          TransferProgress.fromBytes(
            ackedBytes,
            totalBytes: effectiveTotal,
            bytesPerSec: speedEma.update(ackedBytes),
          ),
        );
      }

      // ストリーム内で例外を投げると dartssh2 側 subscribe で未ハンドルに
      // なるため、キャンセル/ソースエラーはシグナルで外へ伝える。
      final cancelSignal = Completer<void>();
      final errorSignal = Completer<Object>();
      Object? sourceError;

      final chunked = _chunkedUploadStream(
        source: source,
        chunkSize: effectiveChunkSize,
        cancelToken: cancelToken,
        onCancelled: () {
          if (!cancelSignal.isCompleted) cancelSignal.complete();
        },
        onError: (error) {
          sourceError = error;
          if (!errorSignal.isCompleted) errorSignal.complete(error);
        },
      );

      final writer = file.write(chunked, onProgress: handleProgress);

      final outcome = Completer<_UploadOutcome>();
      writer.done.then(
        (_) {
          if (!outcome.isCompleted) outcome.complete(_UploadOutcome.done);
        },
        onError: (Object error) {
          sourceError = error;
          if (!outcome.isCompleted) {
            outcome.complete(_UploadOutcome.sourceError);
          }
        },
      );
      cancelSignal.future.then((_) {
        if (!outcome.isCompleted) outcome.complete(_UploadOutcome.cancelled);
      });
      errorSignal.future.then((_) {
        if (!outcome.isCompleted) outcome.complete(_UploadOutcome.sourceError);
      });

      switch (await outcome.future) {
        case _UploadOutcome.cancelled:
          // 書き込みを即時中断する（done 完了後の二重 complete は無視）。
          try {
            await writer.abort();
          } catch (_) {
            // already completed
          }
          throw const TransferCancelledException();
        case _UploadOutcome.sourceError:
          throw sourceError!;
        case _UploadOutcome.done:
          if (cancelToken?.isCancelled ?? false) {
            // ストリーム終端とキャンセルが競合した場合もキャンセル扱い
            throw const TransferCancelledException();
          }
          if (onProgress != null) {
            // 最終進捗（100%）は間引きせず必ず通知する。
            onProgress(
              TransferProgress.fromBytes(
                writer.progress,
                totalBytes: effectiveTotal > 0
                    ? effectiveTotal
                    : writer.progress,
                bytesPerSec: speedEma.update(writer.progress),
              ),
            );
          }
          return SftpUploadResult(
            remotePath: remotePath,
            bytesWritten: writer.progress,
          );
      }
    } catch (_) {
      // 部分ファイルのクリーンアップ試行（キャンセル・エラー共通）
      try {
        await sftp.remove(remotePath);
      } catch (_) {
        // クリーンアップ失敗は無視
      }
      rethrow;
    } finally {
      await file?.close();
    }
  }

  /// 読み込みストリームを [chunkSize] 単位に再構成するジェネレータ。
  ///
  /// - 各データ到着時に [cancelToken] を検査し、キャンセルされていれば
  ///   ストリームを閉じて [onCancelled] を呼ぶ（中断自体は abort で行う）
  /// - ソースのエラーは再送出せず [onError] へ渡す
  /// - async* の yield は購読側（SftpFileWriter）の pause/resume に追従する
  ///   ため、バックプレッシャーがソースまで伝達される
  Stream<Uint8List> _chunkedUploadStream({
    required Stream<Uint8List> source,
    required int chunkSize,
    required TransferCancelToken? cancelToken,
    required void Function() onCancelled,
    required void Function(Object error) onError,
  }) async* {
    final buffer = BytesBuilder(copy: false);
    try {
      await for (final data in source) {
        if (cancelToken?.isCancelled ?? false) {
          onCancelled();
          return;
        }
        buffer.add(data);
        while (buffer.length >= chunkSize) {
          final joined = buffer.takeBytes();
          buffer.add(joined.sublist(chunkSize));
          yield Uint8List.sublistView(joined, 0, chunkSize);
        }
      }
      if (cancelToken?.isCancelled ?? false) {
        onCancelled();
        return;
      }
      if (buffer.isNotEmpty) {
        yield buffer.takeBytes();
      }
    } catch (error) {
      onError(error);
    }
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${_pad(now.month)}${_pad(now.day)}_'
        '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');
}

/// [SftpService.uploadStream] の内部終了状態。
enum _UploadOutcome { done, cancelled, sourceError }
