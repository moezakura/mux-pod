import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/download_provider.dart';
import '../../../services/sftp/transfer_progress.dart';
import '../../../theme/design_colors.dart';
import '../../../widgets/file_transfer/transfer_progress_row.dart';

/// ダウンロード進捗シートを表示する。
///
/// - ヘッダー: 全体進捗（`fraction`・サイズ未知は不定表示）+ 件数（処理済み n / 全件）
///   + 全体速度（`state.speedLabel`）。
/// - 各アイテムは基盤 [TransferProgressRow]（label・バー・bytes・速度・キャンセル）を使用。
///   失敗アイテムは赤字のエラー表記・スキップは「スキップ」表記を付加。
/// - シート単位のキャンセルボタン → `downloadProvider.cancel()`。
/// - phase が downloading 以外（completed / cancelled / error）に遷移したら自動で閉じる。
/// - シートを閉じても転送は継続する（downloadProvider は非 AutoDispose・報告は
///   terminal_screen の常駐 SnackBar が担う）。
Future<void> showTransferProgressSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => const _TransferProgressSheet(),
  );
}

class _TransferProgressSheet extends ConsumerWidget {
  const _TransferProgressSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadProvider);

    // 転送終了（completed / cancelled / error）でシートを自動クローズ。
    // ビルド中の pop を避けるため post-frame で実施し、already-mounted を防止する。
    if (state.phase == DownloadPhase.completed ||
        state.phase == DownloadPhase.cancelled ||
        state.phase == DownloadPhase.error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }

    final l10n = context.l10n;
    final total = state.items.length;
    final done =
        state.completedCount + state.failedCount + state.skippedCount;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ドラッグハンドル
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ヘッダー: タイトル + 件数 + 全体速度
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.fileDownload,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    l10n.fileTransferOf('$done', '$total'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 全体進捗（fraction null＝サイズ未知は不定表示）
                  LinearProgressIndicator(
                    value: state.fraction,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 6),
                  // 全体速度
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      state.speedLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            // アイテム一覧（基盤 TransferProgressRow を使用）
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: state.items.length,
                itemBuilder: (context, index) {
                  final item = state.items[index];
                  return _buildItemRow(context, item);
                },
              ),
            ),
            const Divider(height: 1),
            // シート単位のキャンセル
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: OutlinedButton.icon(
                onPressed: () {
                  ref.read(downloadProvider.notifier).cancel();
                },
                icon: const Icon(Icons.close, size: 18),
                label: Text(l10n.fileTransferCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, DownloadItemState item) {
    final l10n = context.l10n;

    Widget row = TransferProgressRow(
      progress: TransferProgress(
        doneBytes: item.bytesReceived,
        totalBytes: item.totalBytes,
      ),
      label: item.isSkipped ? '${item.name}（${l10n.fileSkipAction}）' : item.name,
    );

    // 失敗アイテム: 赤字のエラー表記を付加（エラー赤字・L2-2）。
    if (item.isError) {
      row = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              item.errorMessage ?? l10n.fileDownloadError,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: DesignColors.error,
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    }
    return row;
  }
}