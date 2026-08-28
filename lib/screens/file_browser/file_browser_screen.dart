// ignore_for_file: use_build_context_synchronously

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/file_browser_provider.dart';
import '../../providers/file_transfer_provider.dart';
import '../../providers/markdown_preview_provider.dart';
import '../../services/sftp/file_entry.dart';
import '../../services/sftp/overwrite_choice.dart';
import '../../services/sftp/transfer_progress.dart';
import '../../theme/design_colors.dart';
import '../../widgets/dialogs/overwrite_confirm_dialog.dart';
import '../../widgets/file_transfer/transfer_progress_row.dart';
import 'markdown_preview_screen.dart';
import 'widgets/file_action_menu.dart';
import 'widgets/file_list_tile.dart';
import 'widgets/path_bar.dart';

/// SFTPファイルブラウザ画面
///
/// tmuxペインに1:1で紐づき、ペインのCWDを初期ディレクトリとして使用する。
class FileBrowserScreen extends ConsumerStatefulWidget {
  final String connectionId;
  final String? paneId;

  const FileBrowserScreen({super.key, required this.connectionId, this.paneId});

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(fileBrowserProvider.notifier).initialize(widget.paneId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fileBrowserProvider);
    final transferState = ref.watch(fileTransferProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(fileBrowserProvider.notifier).refresh(),
        color: DesignColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(context, state, isDark, colorScheme),
            SliverToBoxAdapter(
              child: PathBar(
                currentPath: state.currentPath,
                onPathSelected: (path) {
                  ref
                      .read(fileBrowserProvider.notifier)
                      .navigateToDirectory(path);
                },
              ),
            ),
            if (transferState.phase == FileTransferPhase.uploading)
              SliverToBoxAdapter(
                child: _buildTransferPanel(context, transferState),
              ),
            _buildBody(context, state, isDark),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDirectoryDialog(context),
        child: const Icon(Icons.create_new_folder),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    FileBrowserState state,
    bool isDark,
    ColorScheme colorScheme,
  ) {
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
          onPressed: transferInProgress
              ? null
              : () => _handleUpload(context, state.currentPath),
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

  /// アップロード導線（#41）: file_picker 複数選択 → 衝突確認 → 並列転送。
  Future<void> _handleUpload(BuildContext context, String remoteDir) async {
    final l10n = context.l10n;
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: FileType.any);
    } catch (_) {
      files = [];
    }
    if (!mounted || files.isEmpty) return;

    final notifier = ref.read(fileTransferProvider.notifier);
    await notifier.prepare(files: files, remoteDir: remoteDir);
    if (!mounted) return;

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
      if (!mounted) return;
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
    if (!mounted) return;
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
          content: Text(
            l10n.fileUploadSuccessMulti(doneItems.length, remoteDir),
          ),
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

  /// 転送中パネル（基盤 TransferProgressRow × アクティブ行 + 全体カウンタ）。
  Widget _buildTransferPanel(
    BuildContext context,
    FileTransferState transferState,
  ) {
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

  Widget _buildBody(BuildContext context, FileBrowserState state, bool isDark) {
    if (state.isLoading) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(context.l10n.fileLoading),
            ],
          ),
        ),
      );
    }

    if (state.error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 48,
                  color: DesignColors.error,
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.fileErrorOccurred,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? DesignColors.textPrimary
                        : DesignColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? DesignColors.textMuted
                        : DesignColors.textMutedLight,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () =>
                      ref.read(fileBrowserProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(context.l10n.fileRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final entries = state.displayEntries;

    if (entries.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open,
                size: 48,
                color: isDark
                    ? DesignColors.textMuted
                    : DesignColors.textMutedLight,
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.fileEmptyDirectory,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark
                      ? DesignColors.textMuted
                      : DesignColors.textMutedLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 80),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          // 先頭に親ディレクトリ「..」を表示（ルート以外）
          if (state.currentPath != '/') {
            if (index == 0) {
              return ListTile(
                leading: const Icon(Icons.subdirectory_arrow_left, size: 24),
                title: const Text('..', style: TextStyle(fontSize: 14)),
                onTap: () =>
                    ref.read(fileBrowserProvider.notifier).navigateUp(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
              );
            }
            final entry = entries[index - 1];
            return FileListTile(
              entry: entry,
              onTap: () => _handleEntryTap(context, entry),
              onLongPress: () => _showActionMenu(context, entry),
            );
          }

          final entry = entries[index];
          return FileListTile(
            entry: entry,
            onTap: () => _handleEntryTap(context, entry),
            onLongPress: () => _showActionMenu(context, entry),
          );
        }, childCount: entries.length + (state.currentPath != '/' ? 1 : 0)),
      ),
    );
  }

  void _handleEntryTap(BuildContext context, FileEntry entry) {
    if (entry.isDirectory) {
      ref
          .read(fileBrowserProvider.notifier)
          .navigateToDirectory(entry.fullPath);
    } else if (FileActionMenu.isMarkdown(entry)) {
      // .md/.markdown タップ = プレビュー遷移（合意#2/#3）。
      // 遷移前サイズチェック・load は呼ばない（H-3）。
      _openMarkdownPreview(context, entry);
    } else {
      _showActionMenu(context, entry);
    }
  }

  /// .md / .markdown のプレビュー画面へ遷移する（タップ・メニュー open 共通）。
  ///
  /// 遷移前に [maxPreviewBytes]（20MB）超過をチェックし、超過時は警告
  /// SnackBar のみ表示して遷移しない（合意#1・[MarkdownPreviewScreen] を
  /// build しないため load も開始されない・H-3）。
  void _openMarkdownPreview(BuildContext context, FileEntry entry) {
    final size = entry.size;
    if (size != null && size > maxPreviewBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10n.mdFileTooLargeTitle}: '
            '${context.l10n.mdFileTooLargeMessage(_toMbCeil(size))}',
          ),
          backgroundColor: DesignColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MarkdownPreviewScreen(
          connectionId: widget.connectionId,
          entry: entry,
        ),
      ),
    );
  }

  /// バイト数を実サイズの MB に切り上げる（mdFileTooLargeMessage の size 用）。
  static int _toMbCeil(int bytes) => (bytes / (1024 * 1024)).ceil();

  Future<void> _showActionMenu(BuildContext context, FileEntry entry) async {
    final action = await FileActionMenu.show(context, entry);
    if (action == null || !mounted) return;

    switch (action) {
      case FileAction.open:
        // 合意#2: ディレクトリは従来どおり遷移・.md/.markdown はプレビュー遷移
        // （タップと同義）・対象外ファイルは何もしない（従来の誤った
        // navigateToDirectory 呼び出しを除去。メニュー側で open 非表示のため
        // 通常は到達しない防御的分岐）。
        if (entry.isDirectory) {
          ref
              .read(fileBrowserProvider.notifier)
              .navigateToDirectory(entry.fullPath);
        } else if (FileActionMenu.isMarkdown(entry)) {
          _openMarkdownPreview(context, entry);
        }
      case FileAction.rename:
        await _showRenameDialog(context, entry);
      case FileAction.delete:
        await _showDeleteConfirmDialog(context, entry);
    }
  }

  Future<void> _showRenameDialog(BuildContext context, FileEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.fileRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(border: const OutlineInputBorder()),
          style: TextStyle(
            color: isDark
                ? DesignColors.textPrimary
                : DesignColors.textPrimaryLight,
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.appCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.l10n.fileRenameConfirm),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newName != null &&
        newName.isNotEmpty &&
        newName != entry.name &&
        mounted) {
      final success = await ref
          .read(fileBrowserProvider.notifier)
          .rename(entry, newName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? context.l10n.fileRenameSuccess
                  : context.l10n.fileRenameFailure,
            ),
            backgroundColor: success
                ? DesignColors.success
                : DesignColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteConfirmDialog(
    BuildContext context,
    FileEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.fileDeleteConfirmTitle),
        content: Text(
          context.l10n.fileDeleteConfirmMessage(
            entry.isDirectory
                ? context.l10n.fileTypeDirectory
                : context.l10n.fileTypeFile,
            entry.name,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.appCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: DesignColors.error),
            child: Text(context.l10n.fileDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref
          .read(fileBrowserProvider.notifier)
          .delete(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? context.l10n.fileDeleteSuccess
                  : context.l10n.fileDeleteFailure,
            ),
            backgroundColor: success
                ? DesignColors.success
                : DesignColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showCreateDirectoryDialog(BuildContext context) async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.fileNewFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.l10n.fileFolderNameHint,
            border: const OutlineInputBorder(),
          ),
          style: TextStyle(
            color: isDark
                ? DesignColors.textPrimary
                : DesignColors.textPrimaryLight,
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.appCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.l10n.fileCreate),
          ),
        ],
      ),
    );

    controller.dispose();

    if (name != null && name.isNotEmpty && mounted) {
      final success = await ref
          .read(fileBrowserProvider.notifier)
          .createDirectory(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? context.l10n.fileCreateFolderSuccess
                  : context.l10n.fileCreateFolderFailure,
            ),
            backgroundColor: success
                ? DesignColors.success
                : DesignColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
}

class _SortSelection {
  final SortOption? option;
  final bool isDirectionToggle;

  const _SortSelection({this.option, this.isDirectionToggle = false});
}
