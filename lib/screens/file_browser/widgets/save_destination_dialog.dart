import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';

/// 保存先フォルダの選択肢。
enum SaveDestinationChoice {
  /// `<appDocs>/downloads`（既定・アプリ内）
  downloads,

  /// `<appDocs>`（アプリドキュメントルート）
  documents,

  /// `<appDocs>/downloads` 配下に新規サブフォルダを作成
  subfolder,
}

/// 保存先フォルダ選択ダイアログを表示し、確定したディレクトリパスを返す。
///
/// - 選択肢: Downloads 直下（既定）/ Documents 直下 / 新規サブフォルダ作成。
/// - 既定保存先（`AppSettings.downloadDirectory`）が設定済みの場合はそのパスを
///   追加選択肢として先頭に表示し、初期選択にする（空の場合は Downloads 直下）。
/// - サブフォルダ作成失敗時はダイアログ内にエラーを表示し、**導線を閉じず**
///   再選択可能にする（§L2-2）。
/// - 戻り値: 確定時のディレクトリパス。キャンセル・dismiss 時は null
///   （保存先キャンセル → 転送開始しない・idle 維持）。
///
/// 選択肢 UI は RadioListTile を使わず ListTile 方式（Pattern Map D9:
/// Flutter 3.32+ で deprecated のため新規に使わない）。
Future<String?> showSaveDestinationDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final settings = ref.read(settingsProvider);
  final appDocs = (await getApplicationDocumentsDirectory()).path;
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (ctx) => _SaveDestinationDialog(
      downloadsDir: '$appDocs/downloads',
      documentsDir: appDocs,
      customDir: settings.downloadDirectory.trim().isEmpty
          ? null
          : settings.downloadDirectory.trim(),
    ),
  );
}

/// 保存先選択ダイアログ本体。
class _SaveDestinationDialog extends StatefulWidget {
  final String downloadsDir;
  final String documentsDir;
  final String? customDir;

  const _SaveDestinationDialog({
    required this.downloadsDir,
    required this.documentsDir,
    this.customDir,
  });

  @override
  State<_SaveDestinationDialog> createState() => _SaveDestinationDialogState();
}

class _SaveDestinationDialogState extends State<_SaveDestinationDialog> {
  /// 選択中のカテゴリ。`customDir` があれば設定値（初期選択）、なければ Downloads 直下。
  /// 設定済み DL 先（custom）選択中かどうかは [_customSelected] で表現する。
  late bool _customSelected = widget.customDir != null;
  SaveDestinationChoice _choice = SaveDestinationChoice.downloads;

  final TextEditingController _folderController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  void _select({bool? custom, SaveDestinationChoice? choice}) {
    setState(() {
      _customSelected = custom ?? _customSelected;
      if (choice != null) _choice = choice;
      _error = null;
    });
  }

  /// 選択中カテゴリの保存先パスを返す。サブフォルダ名が空/不正なら null。
  String? _resolvePath() {
    if (_customSelected) return widget.customDir;
    switch (_choice) {
      case SaveDestinationChoice.downloads:
        return widget.downloadsDir;
      case SaveDestinationChoice.documents:
        return widget.documentsDir;
      case SaveDestinationChoice.subfolder:
        final name = _folderController.text.trim().replaceAll(
          RegExp(r'[/\\\x00-\x1F]'),
          '',
        );
        // 空・親ディレクトリ解決（`.` / `..`）は拒否（core の sanitizeLocalName と
        // 同義の補完・アプリサンドボックス内でも親ディレクトリへの解決を防ぐ）。
        // review LOW#2 対応。
        if (name.isEmpty || name == '.' || name == '..') return null;
        return '${widget.downloadsDir}/$name';
    }
  }

  Future<void> _confirm() async {
    final path = _resolvePath();
    if (path == null) {
      setState(() => _error = context.l10n.fileCreateFolderFailure);
      return;
    }
    // 確定した保存先（Downloads/Documents 直下・サブフォルダ・設定値）が未作成の
    // 場合に作成する（端末書込は親ディレクトリが必須）。失敗時はダイアログ内エラー
    // で再選択可能（導線を閉じない）。createSync は同期 throw（widget テストの
    // FakeAsync でも確実に完了する）。
    try {
      Directory(path).createSync(recursive: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.l10n.fileCreateFolderFailure);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.fileDownloadDestinationTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 設定済みの既定 DL 先（あれば先頭・初期選択）
            if (widget.customDir != null)
              _buildOption(
                title: Text(
                  widget.customDir!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: _customSelected,
                icon: Icons.settings,
                onTap: () => _select(custom: true),
              ),
            _buildOption(
              title: Text(l10n.fileDownloadDestinationDownloads),
              subtitle: Text(
                widget.downloadsDir,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              selected:
                  !_customSelected &&
                  _choice == SaveDestinationChoice.downloads,
              icon: Icons.download,
              onTap: () => _select(
                custom: false,
                choice: SaveDestinationChoice.downloads,
              ),
            ),
            _buildOption(
              title: Text(l10n.fileDownloadDestinationDocuments),
              subtitle: Text(
                widget.documentsDir,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              selected:
                  !_customSelected &&
                  _choice == SaveDestinationChoice.documents,
              icon: Icons.folder,
              onTap: () => _select(
                custom: false,
                choice: SaveDestinationChoice.documents,
              ),
            ),
            _buildOption(
              title: Text(l10n.fileDownloadDestinationNewFolder),
              subtitle: Text(
                '${widget.downloadsDir}/<name>',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              selected:
                  !_customSelected &&
                  _choice == SaveDestinationChoice.subfolder,
              icon: Icons.create_new_folder,
              onTap: () => _select(
                custom: false,
                choice: SaveDestinationChoice.subfolder,
              ),
            ),
            if (!_customSelected && _choice == SaveDestinationChoice.subfolder)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _folderController,
                  autofocus: true,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFFE0E0E0)
                        : const Color(0xFF1F1F1F),
                  ),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: l10n.fileFolderNameHint,
                  ),
                  onSubmitted: (_) => _confirm(),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(onPressed: _confirm, child: Text(l10n.commonSave)),
      ],
    );
  }

  Widget _buildOption({
    required Widget title,
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
    Widget? subtitle,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: title,
      subtitle: subtitle,
      selected: selected,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.08),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}
