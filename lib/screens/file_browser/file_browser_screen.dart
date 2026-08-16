// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/file_browser_provider.dart';
import '../../l10n/l10n_ext.dart';
import '../../services/sftp/file_entry.dart';
import '../../theme/design_colors.dart';
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
    } else {
      _showActionMenu(context, entry);
    }
  }

  Future<void> _showActionMenu(BuildContext context, FileEntry entry) async {
    final action = await FileActionMenu.show(context, entry);
    if (action == null || !mounted) return;

    switch (action) {
      case FileAction.open:
        ref
            .read(fileBrowserProvider.notifier)
            .navigateToDirectory(entry.fullPath);
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
