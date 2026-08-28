/// ファイルサイズが上限を超えたときにスローされる例外。
///
/// Markdown プレビュー（20MB・`maxPreviewBytes`）と相対画像取得（5MB・
/// 画像用上限）の両方で [SftpBrowserService.readFileAsBytes] が投げる。
/// 呼び出し側（Provider）はこの例外を捕捉して「サイズ超過」表示に分岐する。
class PreviewTooLargeException implements Exception {
  /// 対象パス（`validatePath` による正規化後）。
  final String path;

  /// サーバーが報告したサイズ（`stat()` で不明な場合は null）。
  final int? size;

  /// 上限バイト数。超過したことを表す。
  final int maxBytes;

  const PreviewTooLargeException({
    required this.path,
    this.size,
    required this.maxBytes,
  });

  @override
  String toString() {
    final sizeText = size == null ? 'size unknown' : 'size=$size';
    return 'PreviewTooLargeException: $path ($sizeText) exceeds maxBytes=$maxBytes';
  }
}