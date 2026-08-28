import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import 'transfer_progress.dart';

/// SFTP ダウンロード結果。
///
/// ダウンロード 1 件分の成果（リモート・ローカルパスと転送バイト数）を保持する。
class SftpDownloadResult {
  final String remotePath;
  final String localPath;
  final int bytesDownloaded;

  const SftpDownloadResult({
    required this.remotePath,
    required this.localPath,
    required this.bytesDownloaded,
  });
}

/// SFTP ダウンロードサービス。
///
/// `SftpFile.read()` の Stream を [defaultChunkSize]（64KB）チャンクで端末の
/// [IOSink] へ逐次書込し、メモリに全ロードしない（受入⑥）。
///
/// キャンセルは基盤の [TransferCancelToken] / [TransferCancelledException] を利用する
/// （#40 独自型は再定義しない）。**`sftp.close()` は絶対に呼ばない**
/// （`ssh_client.dart` の「呼び出し側で close() を呼んではならない」契約）。部分ファイル
/// の削除（キャンセル/失敗時）は「sink.close（flush）→ File.delete」の順で行い、削除
/// 失敗は握りつぶす（upload の `sftp.remove` cleanup と対称）。
class SftpDownloadService {
  /// 既定チャンクサイズ（64KB）。
  static const defaultChunkSize = 64 * 1024;

  /// リモートファイルを [localPath] へダウンロードする。
  ///
  /// - [sftp] は呼び出し側が所有するキャッシュ SftpClient。**このメソッドは
  ///   `sftp.close()` を呼ばない**（チャネル枯渇防止）。
  /// - [localPath] は呼び出し側がサニタイズ済み basename + 確定ディレクトリで
  ///   決定済みであること。
  /// - [cancellation] はキャンセル要求トークン。チャンク境界（および書込前）で
  ///   検査し、キャンセルされていれば [TransferCancelledException] を投げる。
  /// - [onProgress] は毎チャンク呼ばれる（引数は**累積** doneBytes と totalBytes。
  ///   `totalBytes <= 0` はサイズ未知＝基盤契約）。EMA 計算・100ms 間引きは
  ///   呼び出し側（転送タスク層）の責務。
  ///
  /// 失敗時は部分ファイルを削除（ベストエフォート）した上で例外を rethrow する。
  Future<SftpDownloadResult> download({
    required SftpClient sftp,
    required String remotePath,
    required String localPath,
    required TransferCancelToken cancellation,
    void Function(int doneBytes, int totalBytes)? onProgress,
    int chunkSize = defaultChunkSize,
    int maxPendingRequests = 128,
  }) async {
    // 1. サイズはベストエフォートで取得（失敗時 totalBytes=0＝サイズ未知）。
    var totalBytes = 0;
    try {
      totalBytes = (await sftp.stat(remotePath)).size ?? 0;
    } catch (_) {
      totalBytes = 0;
    }

    // 2. 書込前のトークン検査。0 バイトファイルではチャンクが 1 度も流れないため、
    //    ここで 1 回検査して空ファイルの残骸を残さない。
    if (cancellation.isCancelled) {
      throw const TransferCancelledException('Download cancelled');
    }

    final file = File(localPath);
    final sink = file.openWrite();
    SftpFile? sftpFile;
    var doneBytes = 0;
    try {
      sftpFile = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
      await for (final chunk in sftpFile.read(
        chunkSize: chunkSize,
        maxPendingRequests: maxPendingRequests,
      )) {
        // チャンク境界でトークン検査（キャンセル応答は 1 チャンク（64KB）以内）。
        if (cancellation.isCancelled) {
          throw const TransferCancelledException('Download cancelled');
        }
        sink.add(chunk);
        doneBytes += chunk.length;
        onProgress?.call(doneBytes, totalBytes);
      }
      // flush 兼 close。書込 I/O エラー（ディスクフル等）はここで顕在化し catch へ。
      await sink.close();
      return SftpDownloadResult(
        remotePath: remotePath,
        localPath: localPath,
        bytesDownloaded: doneBytes,
      );
    } catch (_) {
      // 部分ファイル削除: flush（ベストエフォート）→ File.delete（ベストエフォート）。
      // 削除失敗は握りつぶしログ（upload の sftp.remove cleanup と対称）。
      try {
        await sink.close();
      } catch (_) {
        // 握りつぶし（未フラッシュチャンクの不安定削除を回避するため flush は試行済み）。
      }
      try {
        await file.delete();
      } catch (_) {
        // 握りつぶし。削除できない残骸は呼び出し側（Provider）のエラー報告に委ねる。
      }
      rethrow;
    } finally {
      // ファイルハンドル close は正常に 1 回行う。sftp.close() は絶対に呼ばない。
      // close 失敗（SSH チャネル断等）が rethrow 元の例外（キャンセル/書込 I/O 等）を
      // 上書きしないよう握りつぶす（レビュー LOW#1）。
      try {
        await sftpFile?.close();
      } catch (_) {
        // 握りつぶし（close 失敗は部分削除済みの転送結果に影響させない）。
      }
    }
  }

  /// リモートパスから端末保存名をサニタイズする（throw しない）。
  ///
  /// リモート `basename(path)` のみを抽出し、`/`・`\`・制御文字を除去する。
  /// 空（または `.` / `..`）になった場合は `download_<yyyyMMdd_HHmmss>` に補完する。
  /// 非 ASCII 名（`音楽.mp3` 等）は保持する（サーバー向け `sanitizeFilename` の
  /// `[a-zA-Z0-9._-]` 置換は端末名を壊すため流用しない）。
  static String sanitizeLocalName(String remotePath) {
    // バックスラッシュもパス区切りとみなして basename を抽出（パストラバーサル防止）。
    final segments = remotePath
        .replaceAll(r'\', '/')
        .split('/')
        .where((s) => s.isNotEmpty);
    var name = segments.isEmpty ? '' : segments.last;
    // '/', '\', 制御文字（U+0000-U+001F・U+007F）を除去。
    name = name.replaceAll(RegExp(r'[/\\\x00-\x1F\x7F]'), '');
    if (name.isEmpty || name == '.' || name == '..') {
      name = 'download_${_timestamp()}';
    }
    return name;
  }

  static String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
