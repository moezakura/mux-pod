// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/file_browser_provider.dart';
import '../../providers/download_provider.dart';
import '../../l10n/l10n_ext.dart';
import '../../services/sftp/file_entry.dart';
import '../../services/sftp/overwrite_choice.dart';
import '../../theme/design_colors.dart';
import '../../widgets/dialogs/overwrite_confirm_dialog.dart';
import 'widgets/file_action_menu.dart';
import 'widgets/file_list_tile.dart';
import 'widgets/path_bar.dart';
import 'widgets/save_destination_dialog.dart';
import 'widgets/transfer_progress_sheet.dart';

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
  /// ダウンロードフローのフェーズ駆動リスナー（T10/T11）。
  ///
  /// `startDownloads` はキュー完了まで await されるため、await ベースでは
  /// 「転送中」の進捗シートを開けない。フェーズ遷移を listen して
  /// awaitingOverwrite → 上書き確認導線 / downloading → 進捗シートを駆動する。
  ProviderSubscription<DownloadState>? _downloadFlowSub;

  /// 進捗シートの多重表示防止（already-mounted エラー回避）。
  bool _sheetOpen = false;

  /// 複数選択モード中か（長押しで突入・解除/フォルダ移動で終了）。
  bool _selectMode = false;

  /// 選択中のエントリ（screen ローカル Set・`FileEntry` は fullPath ベースの
  /// ==/hashCode のためトグルは fullPath 一致で動作・Pattern Map Concern 11）。
  final Set<FileEntry> _selectedEntries = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(fileBrowserProvider.notifier).initialize(widget.paneId);
    });
    _downloadFlowSub = ref.listenManual<DownloadState>(downloadProvider, (
      prev,
      next,
    ) {
      if (!mounted) return;
      // フェーズ遷移時のみ処理（進捗 publish では発火しない）。
      if (prev?.phase == next.phase) return;
      switch (next.phase) {
        case DownloadPhase.awaitingOverwrite:
          _handleAwaitingOverwrite();
        case DownloadPhase.downloading:
          _showDownloadProgressSheet();
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _downloadFlowSub?.close();
    _downloadFlowSub = null;
    super.dispose();
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
                  _exitSelectionMode(); // フォルダ移動 = 選択解除
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
    // 複数選択モード: 件数 + 一括DL（0 件で無効）+ 解除。通常 actions は非表示。
    if (_selectMode) {
      return SliverAppBar(
        floating: true,
        pinned: true,
        backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        title: Text(
          context.l10n.fileSelectedCount(_selectedEntries.length),
          style: GoogleFonts.spaceGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, size: 22),
            tooltip: context.l10n.fileBatchDownload,
            onPressed: _selectedEntries.isEmpty ? null : _handleBatchDownload,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 22),
            tooltip: context.l10n.fileClearSelection,
            onPressed: _exitSelectionMode,
          ),
        ],
      );
    }

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
                onTap: () {
                  _exitSelectionMode(); // フォルダ移動 = 選択解除
                  ref.read(fileBrowserProvider.notifier).navigateUp();
                },
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
              );
            }
            final entry = entries[index - 1];
            return _buildFileListTile(entry);
          }

          final entry = entries[index];
          return _buildFileListTile(entry);
        }, childCount: entries.length + (state.currentPath != '/' ? 1 : 0)),
      ),
    );
  }

  /// 一覧行を組み立てる。選択モード中はタップ＝トグル・長押し＝選択追加（ファイル）、
  /// 通常時はタップ＝既存挙動・長押し＝アクションメニュー。
  Widget _buildFileListTile(FileEntry entry) {
    return FileListTile(
      entry: entry,
      selectionMode: _selectMode,
      selected: _selectedEntries.contains(entry),
      onTap: () => _selectMode
          ? _handleSelectionTap(entry)
          : _handleEntryTap(context, entry),
      onLongPress: () => _handleLongPress(context, entry),
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

  /// 長押し（T15）: 選択可能（ダウンロード対象）ファイルなら複数選択モードへ突入し
  /// そのファイルを選択。ディレクトリ・シンボリックリンクは従来どおりアクションメニュー
  /// （ディレクトリの rename/delete は長押しメニューが唯一の導線のため温存）。
  void _handleLongPress(BuildContext context, FileEntry entry) {
    if (!_canSelect(entry)) {
      _showActionMenu(context, entry);
      return;
    }
    setState(() {
      _selectMode = true;
      _selectedEntries.add(entry);
    });
  }

  /// 選択モード中のタップ: ファイル → トグル / ディレクトリ → ナビゲート（選択解除）。
  void _handleSelectionTap(FileEntry entry) {
    if (_canSelect(entry)) {
      setState(() {
        if (!_selectedEntries.remove(entry)) _selectedEntries.add(entry);
      });
      return;
    }
    _exitSelectionMode();
    ref.read(fileBrowserProvider.notifier).navigateToDirectory(entry.fullPath);
  }

  /// 選択モードを終了し選択をクリアする（解除ボタン・フォルダ移動時に呼ぶ）。
  void _exitSelectionMode() {
    if (!_selectMode && _selectedEntries.isEmpty) return;
    setState(() {
      _selectMode = false;
      _selectedEntries.clear();
    });
  }

  /// 複数選択（ダウンロード対象）の可否: ファイルのみ・シンボリックリンク除外
  /// （FileActionMenu の download 表示条件と同一）。
  bool _canSelect(FileEntry entry) => !entry.isDirectory && !entry.isSymlink;

  /// 一括ダウンロード（T15）: 選択一覧を保存先選択（1 回）→ startDownloads →
  /// 順次転送。awaitingOverwrite → 上書き確認 / downloading → 進捗シートは
  /// [_downloadFlowSub] が担当（既存 T10/T11 導線の再利用・件数非依存）。
  Future<void> _handleBatchDownload() async {
    final entries = _selectedEntries.toList();
    if (entries.isEmpty) return;
    final dir = await showSaveDestinationDialog(context, ref);
    if (dir == null || !mounted) return; // 保存先キャンセル → idle 維持
    await ref.read(downloadProvider.notifier).startDownloads(entries, dir);
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
      case FileAction.download:
        await _handleDownload(context, [entry]);
    }
  }

  /// ダウンロード導線: 保存先選択 → startDownloads（単一・一括の共通経路）。
  ///
  /// フェーズ駆動（awaitingOverwrite → 上書き確認 / downloading → 進捗シート）は
  /// initState の [_downloadFlowSub] listen が担う。
  Future<void> _handleDownload(
    BuildContext context,
    List<FileEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    final dir = await showSaveDestinationDialog(context, ref);
    if (dir == null || !mounted) return; // 保存先キャンセル → idle 維持

    await ref.read(downloadProvider.notifier).startDownloads(entries, dir);
  }

  /// awaitingOverwrite: 同名衝突の事前スキャン検出を基盤ダイアログで一括確認（🤝#5）。
  Future<void> _handleAwaitingOverwrite() async {
    final decisions = await _collectOverwriteDecisions(context);
    if (!mounted) return;
    if (decisions == null) {
      // null 戻り値（barrier/back dismiss）= 操作中断 → バッチ中断（転送開始しない）。
      ref.read(downloadProvider.notifier).reset();
      return;
    }
    await ref
        .read(downloadProvider.notifier)
        .applyOverwriteDecisions(decisions);
  }

  /// downloading: 進捗シートを表示（多重表示防止・閉じても転送は継続）。
  void _showDownloadProgressSheet() {
    if (_sheetOpen) return;
    _sheetOpen = true;
    showTransferProgressSheet(context).whenComplete(() {
      _sheetOpen = false;
    });
  }

  /// 上書き確認導線。[DownloadState.collidingItems] をファイルごとに
  /// 基盤 [showOverwriteConfirmDialog]（batch モード + 全ファイル適用）で確認する。
  ///
  /// - null 戻り値（barrier/back dismiss）＝操作中断 → 呼び出し側でバッチ中断（reset）。
  /// - `applyToAll == true` は残り全衝突へ同じ決定を適用する（基盤契約 C-8）。
  /// - 決定は `Map<localPath, OverwriteChoice>` で返し、呼び出し側が applyOverwriteDecisions へ渡す。
  Future<Map<String, OverwriteChoice>?> _collectOverwriteDecisions(
    BuildContext context,
  ) async {
    final decisions = <String, OverwriteChoice>{};
    final remaining = List.of(ref.read(downloadProvider).collidingItems);
    while (remaining.isNotEmpty) {
      final item = remaining.removeAt(0);
      final result = await showOverwriteConfirmDialog(
        context,
        fileName: item.name,
        mode: OverwriteDialogMode.batch,
        showApplyToAll: true,
      );
      if (result == null) return null; // 操作中断 → バッチ中断
      decisions[item.localPath] = result.choice;
      if (result.applyToAll) {
        for (final rest in remaining) {
          decisions[rest.localPath] = result.choice;
        }
        break;
      }
    }
    return decisions;
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
