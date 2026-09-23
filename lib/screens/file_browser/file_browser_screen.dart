// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/download_provider.dart';
import '../../providers/file_browser_provider.dart';
import '../../providers/file_transfer_provider.dart';
import '../../providers/markdown_preview_provider.dart';
import '../../services/sftp/file_entry.dart';
import '../../theme/design_colors.dart';
import 'file_browser_app_bar.dart';
import 'file_browser_body.dart';
import 'file_browser_dialogs.dart';
import 'file_browser_download_flow.dart';
import 'file_browser_upload_flow.dart';
import 'markdown_preview_screen.dart';
import 'widgets/file_action_menu.dart';
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
  /// ダウンロードフローのフェーズ駆動リスナー（T10/T11）を所有する協調オブジェクト。
  ///
  /// `startDownloads` はキュー完了まで await されるため、await ベースでは
  /// 「転送中」の進捗シートを開けない。フェーズ遷移を listen して
  /// awaitingOverwrite → 上書き確認導線 / downloading → 進捗シートを駆動する。
  late final FileBrowserDownloadFlow _downloadFlow;

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
    _downloadFlow = FileBrowserDownloadFlow()
      ..attach(ref, onPhaseChanged: _onDownloadPhaseChanged);
  }

  @override
  void dispose() {
    _downloadFlow.dispose();
    super.dispose();
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
            FileBrowserAppBar(
              state: state,
              isDark: isDark,
              colorScheme: colorScheme,
              selectMode: _selectMode,
              selectedCount: _selectedEntries.length,
              onUpload: () =>
                  runFileBrowserUpload(context, ref, state.currentPath),
              onBatchDownload: _handleBatchDownload,
              onExitSelection: _exitSelectionMode,
            ),
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
            if (transferState.phase == FileTransferPhase.uploading)
              const SliverToBoxAdapter(child: FileBrowserUploadPanel()),
            FileBrowserBody(
              state: state,
              isDark: isDark,
              selectMode: _selectMode,
              selectedEntries: _selectedEntries,
              onRetry: () => ref.read(fileBrowserProvider.notifier).refresh(),
              onNavigateUp: () {
                _exitSelectionMode(); // フォルダ移動 = 選択解除
                ref.read(fileBrowserProvider.notifier).navigateUp();
              },
              onEntryTap: _onEntryTap,
              onEntryLongPress: _onEntryLongPress,
              onEntryMenu: _onEntryMenu,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCreateDirectoryDialog(context, ref),
        child: const Icon(Icons.create_new_folder),
      ),
    );
  }

  /// ダウンロード位相の遷移を協調オブジェクトから受け、State の context を
  /// 上書き確認・進捗シート表示へ渡す（flow は context を保持しない）。
  void _onDownloadPhaseChanged(DownloadPhase phase) {
    if (!mounted) return;
    switch (phase) {
      case DownloadPhase.awaitingOverwrite:
        // 一括導線のみ到達（単一は OS Save-As 側で上書き確認するため不要）。
        _downloadFlow.handleAwaitingOverwrite(context);
      case DownloadPhase.downloading:
      case DownloadPhase.exporting:
        // 転送中（一括）／Save-As 待ち（単一）の間は進捗シートを表示する。
        _downloadFlow.showProgressSheet(context);
      default:
        break;
    }
  }

  /// 行タップ（複数選択モードと通常の分岐を一括で受ける）。
  void _onEntryTap(FileEntry entry) {
    if (_selectMode) {
      _handleSelectionTap(entry);
    } else {
      _handleEntryTap(context, entry);
    }
  }

  /// 行長押し（選択可否チェック + 選択モード突入 / 従来メニュー）。
  void _onEntryLongPress(FileEntry entry) {
    if (_selectMode && !_canSelect(entry)) return;
    _handleLongPress(context, entry);
  }

  /// 行右端メニューボタン。
  void _onEntryMenu(FileEntry entry) {
    _showActionMenu(context, entry);
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
  /// シンボリックリンクは選択・単体操作のどちらも行わない。
  void _handleSelectionTap(FileEntry entry) {
    if (_canSelect(entry)) {
      setState(() {
        if (!_selectedEntries.remove(entry)) _selectedEntries.add(entry);
      });
      return;
    }
    if (!entry.isDirectory) return;
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

  /// 一括ダウンロード（T15）: 選択一覧を保存先選択（1 回）→ 順次転送。
  /// awaitingOverwrite → 上書き確認 / downloading → 進捗シートは
  /// [_downloadFlow] のフェーズリスナーが担当する。
  Future<void> _handleBatchDownload() async {
    final entries = _selectedEntries.toList();
    if (entries.isEmpty) return;
    await _downloadFlow.startBatch(entries, context);
  }

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
        await showRenameDialog(context, ref, entry);
      case FileAction.delete:
        await showDeleteConfirmDialog(context, ref, entry);
      case FileAction.download:
        // 単一ダウンロード: Tmp ダウンロード → exporting（OS Save-As）→ completed/cancelled。
        await _downloadFlow.startSingle(entry);
    }
  }
}
