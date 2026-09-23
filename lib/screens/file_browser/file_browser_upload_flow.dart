// ignore_for_file: use_build_context_synchronously

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/file_browser_provider.dart';
import '../../providers/file_transfer_provider.dart';
import '../../services/sftp/overwrite_choice.dart';
import '../../services/sftp/transfer_progress.dart';
import '../../theme/design_colors.dart';
import '../../widgets/dialogs/overwrite_confirm_dialog.dart';
import '../../widgets/file_transfer/transfer_progress_row.dart';

/// アップロード導線（#41）: file_picker 複数選択 → 衝突確認 → 並列転送。
///
/// root State から `WidgetRef` と `BuildContext`（保存先・完了後の SnackBar /
/// 一覧 refresh 用）を引数で受ける。`State.mounted` の相当判定は
/// `context.mounted` で行う（4 箇所）。
Future<void> runFileBrowserUpload(
  BuildContext context,
  WidgetRef ref,
  String remoteDir,
) async {
  final l10n = context.l10n;
  List<PlatformFile> files;
  try {
    files = await FilePicker.pickFiles(type: FileType.any);
  } catch (_) {
    files = [];
  }
  if (!context.mounted || files.isEmpty) return;

  final notifier = ref.read(fileTransferProvider.notifier);
  await notifier.prepare(files: files, remoteDir: remoteDir);
  if (!context.mounted) return;

  var transferState = ref.read(fileTransferProvider);
  if (transferState.phase == FileTransferPhase.error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.fileUploadSshUnavailable),
        backgroundColor: DesignColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    notifier.reset();
    return;
  }

  // 衝突確認（基盤 showOverwriteConfirmDialog・single モード）。
  // dismiss(null) と cancel はどちらも全体中止（基盤契約 C-8）。
  while (ref.read(fileTransferProvider).hasConflicts) {
    final index = ref.read(fileTransferProvider).conflictIndexes.first;
    final item = ref.read(fileTransferProvider).items[index];
    final result = await showOverwriteConfirmDialog(
      context,
      fileName: item.fileName,
      mode: OverwriteDialogMode.single,
    );
    if (!context.mounted) return;
    if (result == null || result.choice == OverwriteChoice.cancel) {
      notifier.reset();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.fileUploadCancelled),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    notifier.setConflictResolution(
      index,
      result.choice == OverwriteChoice.overwrite
          ? ConflictResolution.overwrite
          : ConflictResolution.rename,
    );
  }

  await notifier.start();
  if (!context.mounted) return;
  transferState = ref.read(fileTransferProvider);

  // 結果フィードバック（アップロード先パス付き）
  final doneItems = transferState.items
      .where((item) => item.status == FileTransferItemStatus.done)
      .toList();
  final failedCount = transferState.items
      .where((item) => item.status == FileTransferItemStatus.failed)
      .length;
  if (transferState.phase == FileTransferPhase.cancelled) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.fileUploadCancelled),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } else if (doneItems.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.fileUploadAllFailed),
        backgroundColor: DesignColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  } else if (failedCount > 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.fileUploadPartialFailure(
            failedCount,
            transferState.items.length,
          ),
        ),
        backgroundColor: DesignColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  } else if (doneItems.length == 1) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.fileUploadSuccessSingle(doneItems.first.remotePath ?? ''),
        ),
        backgroundColor: DesignColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.fileUploadSuccessMulti(doneItems.length, remoteDir)),
        backgroundColor: DesignColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  if (doneItems.isNotEmpty) {
    // アップロード済みファイルを一覧へ反映
    await ref.read(fileBrowserProvider.notifier).refresh();
  }
}

/// 転送中パネル（upload 専用・基盤 TransferProgressRow × アクティブ行 +
/// 全体カウンタ）。ダウンロードの進捗は showTransferProgressSheet の別経路。
class FileBrowserUploadPanel extends ConsumerWidget {
  const FileBrowserUploadPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transferState = ref.watch(fileTransferProvider);
    final l10n = context.l10n;
    final activeIndexes = [
      for (var i = 0; i < transferState.items.length; i++)
        if (transferState.items[i].status == FileTransferItemStatus.uploading)
          i,
    ];

    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.fileUploadCount(
                      transferState.settledCount,
                      transferState.items.length,
                    ),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      ref.read(fileTransferProvider.notifier).cancelAll(),
                  icon: const Icon(Icons.close, size: 16),
                  label: Text(l10n.fileUploadCancelAll),
                ),
              ],
            ),
          ),
          for (final index in activeIndexes)
            TransferProgressRow(
              key: ValueKey('transfer-row-$index'),
              progress:
                  transferState.items[index].progress ??
                  TransferProgress(
                    doneBytes: 0,
                    totalBytes: transferState.items[index].totalBytes,
                  ),
              label: transferState.items[index].fileName,
              onCancel: () =>
                  ref.read(fileTransferProvider.notifier).cancelFile(index),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
