import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';
import '../../services/sftp/file_entry.dart';
import '../../services/sftp/transfer_format.dart';
import '../../services/sftp/transfer_progress.dart';

/// 単一転送の進捗を表示する行（label + プログレスバー + バイト + 速度 + キャンセル）。
///
/// #40（ダウンロード）/ #41（アップロード）が共通で使う最小の進捗 UI。
/// バッチ集約（n/total・並列 i/N）は各 Issue がこの行の上に載せる。
class TransferProgressRow extends StatelessWidget {
  final TransferProgress progress;
  final String? label;
  final VoidCallback? onCancel;

  const TransferProgressRow({
    super.key,
    required this.progress,
    this.label,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fraction = progress.fraction;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (onCancel != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.fileTransferCancel,
                  onPressed: onCancel,
                ),
            ],
          ),
          const SizedBox(height: 6),
          // fraction null（サイズ未知）は value: null で不定表示（C-12 / image_transfer_button 踏襲）。
          LinearProgressIndicator(
            value: fraction,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatBytesLabel(l10n),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                l10n.fileTransferSpeed(
                  formatTransferSpeed(progress.bytesPerSec),
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// バイト表示（`done / total`、サイズ未知なら done のみ）を生成する。
  ///
  /// バイトフォーマッタは再実装せず `FileEntry.formattedSize` を流用する
  /// （棲み分け。`transfer_format.dart` は速度専用。「4 / 10 MB」等の表記は
  /// l10n の `fileTransferOf({done},{total})` を使う）。
  String _formatBytesLabel(AppLocalizations l10n) {
    final done = _formatBytes(progress.doneBytes);
    if (progress.totalBytes <= 0) return done;
    final total = _formatBytes(progress.totalBytes);
    return l10n.fileTransferOf(done, total);
  }

  String _formatBytes(int bytes) {
    // FileEntry.formattedSize を流用するため、size のみを持つ一時エントリを生成。
    return FileEntry(
      name: '',
      fullPath: '',
      isDirectory: false,
      size: bytes,
    ).formattedSize;
  }
}
