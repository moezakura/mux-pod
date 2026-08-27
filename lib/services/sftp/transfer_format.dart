/// 転送速度の表示フォーマット（B/s・KB/s・MB/s・GB/s）。
///
/// バイト数の表示は `FileEntry.formattedSize`（`lib/services/sftp/file_entry.dart`）
/// を流用するため、このライブラリは**速度専用**のフォーマッタを提供する
/// （棲み分け。バイトフォーマッタは再実装しない）。
library;

/// 速度（B/s）を人間が読める形式（`B/s` / `KB/s` / `MB/s` / `GB/s`）に整形する。
///
/// `FileEntry.formattedSize`（4 段階 if 分岐 + `toStringAsFixed(1)`）の書き方を
/// 踏襲（`lib/services/sftp/file_entry.dart:92-101`）。
String formatTransferSpeed(double bytesPerSec) {
  if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(1)} B/s';
  if (bytesPerSec < 1024 * 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  }
  if (bytesPerSec < 1024 * 1024 * 1024) {
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  return '${(bytesPerSec / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
}
