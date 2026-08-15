import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:uuid/uuid.dart';

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

  /// ファイル名をサニタイズ（安全な文字のみ許可）
  ///
  /// [a-zA-Z0-9._-] 以外の文字は `_` に置換する。
  static String sanitizeFilename(String raw) {
    if (raw.isEmpty) return 'unnamed';
    return raw.replaceAll(_safeCharsRegex, '_');
  }

  /// タイムスタンプ + UUID短縮でユニークファイル名を生成
  ///
  /// 例: img_20260403_143025_a3f2.png
  static String generateFilename(String prefix, String extension) {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    final shortUuid = _uuid.v4().substring(0, 4);
    final sanitizedExt = extension.startsWith('.')
        ? extension.substring(1)
        : extension;
    return '${sanitizeFilename(prefix)}${timestamp}_$shortUuid.$sanitizedExt';
  }

  /// リモートディレクトリの存在確認・作成
  Future<void> ensureDirectory(SftpClient sftp, String remotePath) async {
    try {
      await sftp.stat(remotePath);
    } on SftpStatusError {
      await sftp.mkdir(remotePath);
    }
  }

  /// ファイルアップロード
  ///
  /// [sftp] SFTPクライアント
  /// [remoteDir] リモートディレクトリパス（末尾/なし可）
  /// [filename] ファイル名
  /// [bytes] アップロードするバイトデータ
  /// [onProgress] 進捗コールバック (0.0 ~ 1.0)
  Future<SftpUploadResult> upload({
    required SftpClient sftp,
    required String remoteDir,
    required String filename,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  }) async {
    final dir = remoteDir.endsWith('/')
        ? remoteDir.substring(0, remoteDir.length - 1)
        : remoteDir;
    final remotePath = '$dir/$filename';

    await ensureDirectory(sftp, dir);

    SftpFile? file;
    try {
      file = await sftp.open(
        remotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );

      final totalBytes = bytes.length;
      var written = 0;

      // チャンク分割でストリーム書き込み（進捗追跡用）
      const chunkSize = 32 * 1024; // 32KB
      final chunks = <Uint8List>[];
      for (var offset = 0; offset < totalBytes; offset += chunkSize) {
        final end = (offset + chunkSize > totalBytes)
            ? totalBytes
            : offset + chunkSize;
        chunks.add(bytes.sublist(offset, end));
      }

      final stream = Stream.fromIterable(chunks).map((chunk) {
        written += chunk.length;
        onProgress?.call(totalBytes > 0 ? written / totalBytes : 1.0);
        return chunk;
      });

      final writer = file.write(stream);
      await writer.done;

      return SftpUploadResult(remotePath: remotePath, bytesWritten: totalBytes);
    } catch (e) {
      // 部分ファイルのクリーンアップ試行
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

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
