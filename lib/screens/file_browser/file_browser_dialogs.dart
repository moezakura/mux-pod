// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/file_browser_provider.dart';
import '../../services/sftp/file_entry.dart';
import '../../theme/design_colors.dart';

/// ファイル名変更ダイアログを表示し、成功/失敗を SnackBar で通知する。
Future<void> showRenameDialog(
  BuildContext context,
  WidgetRef ref,
  FileEntry entry,
) async {
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
      context.mounted) {
    final success = await ref
        .read(fileBrowserProvider.notifier)
        .rename(entry, newName);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? context.l10n.fileRenameSuccess
                : context.l10n.fileRenameFailure,
          ),
          backgroundColor: success ? DesignColors.success : DesignColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// ファイル/ディレクトリ削除確認ダイアログを表示し、成功/失敗を SnackBar で通知する。
Future<void> showDeleteConfirmDialog(
  BuildContext context,
  WidgetRef ref,
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

  if (confirmed == true && context.mounted) {
    final success = await ref.read(fileBrowserProvider.notifier).delete(entry);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? context.l10n.fileDeleteSuccess
                : context.l10n.fileDeleteFailure,
          ),
          backgroundColor: success ? DesignColors.success : DesignColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// 新規フォルダ作成ダイアログを表示し、成功/失敗を SnackBar で通知する。
Future<void> showCreateDirectoryDialog(
  BuildContext context,
  WidgetRef ref,
) async {
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

  if (name != null && name.isNotEmpty && context.mounted) {
    final success = await ref
        .read(fileBrowserProvider.notifier)
        .createDirectory(name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? context.l10n.fileCreateFolderSuccess
                : context.l10n.fileCreateFolderFailure,
          ),
          backgroundColor: success ? DesignColors.success : DesignColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
