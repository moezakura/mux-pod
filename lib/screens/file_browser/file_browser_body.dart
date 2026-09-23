import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/file_browser_provider.dart';
import '../../services/sftp/file_entry.dart';
import '../../theme/design_colors.dart';
import 'widgets/file_list_tile.dart';

/// file_browser 画面内部の一覧ボディ（loading / error / empty / リスト行）。
///
/// provider 参照はシグネチャのコールバック（onRetry / onNavigateUp 等）に
/// 置換済みのため StatelessWidget で実装する。
class FileBrowserBody extends StatelessWidget {
  const FileBrowserBody({
    super.key,
    required this.state,
    required this.isDark,
    required this.selectMode,
    required this.selectedEntries,
    required this.onRetry,
    required this.onNavigateUp,
    required this.onEntryTap,
    required this.onEntryLongPress,
    required this.onEntryMenu,
  });

  /// 画面ルートの watch 値（loading / error / displayEntries / currentPath）。
  final FileBrowserState state;

  final bool isDark;

  /// 複数選択モード中か（行タップ・長押しの分岐は root 側のコールバックが判定）。
  final bool selectMode;

  /// 選択中のエントリ（行のチェック状態・トグル判定に使用）。
  final Set<FileEntry> selectedEntries;

  /// エラー時再試行（root が refresh を閉包）。
  final VoidCallback onRetry;

  /// 親ディレクトリ「..」への移動（root が選択解除 + navigateUp を閉包）。
  final VoidCallback onNavigateUp;

  /// 行タップ（root が複数選択モード分岐を閉包）。
  final ValueChanged<FileEntry> onEntryTap;

  /// 行長押し（root が選択可否チェック + 選択モード突入を閉包）。
  final ValueChanged<FileEntry> onEntryLongPress;

  /// 行右端メニューボタン（root がアクションメニュー表示を閉包）。
  final ValueChanged<FileEntry> onEntryMenu;

  @override
  Widget build(BuildContext context) {
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
                  onPressed: onRetry,
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
                onTap: onNavigateUp,
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

  /// 一覧行を組み立てる。選択モード中は選択可能ファイルのタップ／長押しで
  /// 選択を更新する。通常時はタップで既存挙動、長押しでファイル選択を開始し、
  /// 右端ボタンから全エントリの単体アクションメニューを開く。
  Widget _buildFileListTile(FileEntry entry) {
    return FileListTile(
      entry: entry,
      selectionMode: selectMode,
      selected: selectedEntries.contains(entry),
      onTap: () => onEntryTap(entry),
      onLongPress: () => onEntryLongPress(entry),
      onMenuPressed: () => onEntryMenu(entry),
    );
  }
}
