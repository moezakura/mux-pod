import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/file_browser_provider.dart';
import '../../services/sftp/file_entry.dart';
import '../../providers/file_transfer_provider.dart';

/// file_browser 画面内部の AppBar（通常 + 複数選択モード）。
///
/// 複数選択モード時は件数 + 一括ダウンロード + 解除を表示し、通常時は
/// アップロード / 隠しファイルトグル / ソートメニューを表示する。
/// 転送中判定（アップロード無効化）とソート・隠しファイルの反映は
/// provider を watch/read するため ConsumerWidget で実装する。
class FileBrowserAppBar extends ConsumerWidget {
  const FileBrowserAppBar({
    super.key,
    required this.state,
    required this.isDark,
    required this.colorScheme,
    required this.selectMode,
    required this.selectedCount,
    required this.onUpload,
    required this.onBatchDownload,
    required this.onExitSelection,
  });

  /// 画面ルートの watch 値（現在パス・ソート状態・隠しファイル表示）。
  final FileBrowserState state;

  final bool isDark;

  final ColorScheme colorScheme;

  /// 複数選択モード中か。
  final bool selectMode;

  /// 選択中エントリ数（複数選択モードのタイトル・一括DL 有効判定）。
  final int selectedCount;

  /// アップロード開始（root が現在パスを閉包して runFileBrowserUpload を呼ぶ）。
  final VoidCallback onUpload;

  /// 一括ダウンロード開始。
  final VoidCallback onBatchDownload;

  /// 複数選択モード終了。
  final VoidCallback onExitSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 複数選択モード: 件数 + 一括DL（0 件で無効）+ 解除。通常 actions は非表示。
    if (selectMode) {
      return SliverAppBar(
        floating: true,
        pinned: true,
        backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        title: Text(
          context.l10n.fileSelectedCount(selectedCount),
          style: GoogleFonts.spaceGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, size: 22),
            tooltip: context.l10n.fileBatchDownload,
            onPressed: selectedCount == 0 ? null : onBatchDownload,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 22),
            tooltip: context.l10n.fileClearSelection,
            onPressed: onExitSelection,
          ),
        ],
      );
    }

    final transferState = ref.watch(fileTransferProvider);
    final transferInProgress =
        transferState.phase == FileTransferPhase.uploading;
    final dirName = state.currentPath == '/'
        ? '/'
        : state.currentPath.split('/').where((s) => s.isNotEmpty).lastOrNull ??
              '/';

    return SliverAppBar(
      floating: true,
      pinned: true,
      backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
      surfaceTintColor: Colors.transparent,
      title: Text(
        dirName,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        // アップロード（#41・転送中は無効化）
        IconButton(
          icon: const Icon(Icons.upload_file, size: 22),
          onPressed: transferInProgress ? null : onUpload,
          tooltip: context.l10n.fileUploadAction,
        ),
        // 隠しファイルトグル
        IconButton(
          icon: Icon(
            state.showHidden ? Icons.visibility : Icons.visibility_off,
            size: 22,
          ),
          onPressed: () =>
              ref.read(fileBrowserProvider.notifier).toggleShowHidden(),
          tooltip: state.showHidden
              ? context.l10n.fileHideHiddenFiles
              : context.l10n.fileShowHiddenFiles,
        ),
        // ソートメニュー
        PopupMenuButton<_SortSelection>(
          icon: const Icon(Icons.sort, size: 22),
          tooltip: context.l10n.fileSort,
          onSelected: (selection) {
            if (selection.isDirectionToggle) {
              ref
                  .read(fileBrowserProvider.notifier)
                  .setSort(state.sortOption, ascending: !state.sortAscending);
            } else {
              ref.read(fileBrowserProvider.notifier).setSort(selection.option!);
            }
          },
          itemBuilder: (context) => [
            for (final option in SortOption.values)
              PopupMenuItem(
                value: _SortSelection(option: option),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: state.sortOption == option
                          ? const Icon(Icons.check, size: 18)
                          : null,
                    ),
                    Text(_sortOptionLabel(context, option)),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: const _SortSelection(isDirectionToggle: true),
              child: Row(
                children: [
                  const SizedBox(width: 24),
                  Icon(
                    state.sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.sortAscending
                        ? context.l10n.fileSortAscending
                        : context.l10n.fileSortDescending,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _sortOptionLabel(BuildContext context, SortOption option) {
  final l10n = context.l10n;
  return switch (option) {
    SortOption.name => l10n.fileSortName,
    SortOption.size => l10n.fileSortSize,
    SortOption.date => l10n.fileSortDate,
    SortOption.type => l10n.fileSortType,
  };
}

/// ソートメニュー項目（option 選択 or 方向トグル）。
class _SortSelection {
  final SortOption? option;
  final bool isDirectionToggle;

  const _SortSelection({this.option, this.isDirectionToggle = false});
}
