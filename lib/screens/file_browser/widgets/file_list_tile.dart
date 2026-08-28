import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/sftp/file_entry.dart';
import '../../../theme/design_colors.dart';

/// ファイル/ディレクトリ一覧のListTile
class FileListTile extends StatelessWidget {
  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// 複数選択モード中か（選択モード中のみチェックボックスを表示）。
  final bool selectionMode;

  /// 選択済みか（選択モード中のハイライト+チェック表示）。
  final bool selected;

  const FileListTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  /// 選択可能（ダウンロード対象＝ファイルのみ・シンボリックリンク除外。
  /// FileActionMenu の download 表示条件と同一）。
  bool get _selectable => !entry.isDirectory && !entry.isSymlink;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? DesignColors.textPrimary
        : DesignColors.textPrimaryLight;
    final subtitleColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;

    return ListTile(
      selected: selectionMode && selected,
      selectedTileColor: Theme.of(context).colorScheme.primary.withValues(
        alpha: 0.08,
      ),
      leading: _buildIcon(isDark),
      title: Text(
        entry.name,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: entry.isDirectory ? FontWeight.w500 : FontWeight.w400,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: _buildSubtitle(subtitleColor),
      trailing: _buildTrailing(subtitleColor),
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }

  /// trailing を組み立てる。選択モード中は選択可能ファイルのみチェックボックスを
  /// 表示（Checkbox はタップを吸収するためトグルは [onTap] へ委譲し、二重トグルを
  /// 防ぐ）。ディレクトリは従来どおり chevron。
  Widget? _buildTrailing(Color subtitleColor) {
    if (selectionMode && _selectable) {
      return Checkbox(
        value: selected,
        onChanged: (_) => onTap(),
      );
    }
    return entry.isDirectory
        ? Icon(Icons.chevron_right, color: subtitleColor, size: 20)
        : null;
  }

  Widget _buildIcon(bool isDark) {
    IconData icon;
    Color color;

    if (entry.isSymlink) {
      icon = Icons.link;
      color = DesignColors.terminalCyan;
    } else if (entry.isDirectory) {
      icon = Icons.folder;
      color = DesignColors.secondary;
    } else {
      icon = _getFileIcon(entry.extension);
      color = isDark
          ? DesignColors.textSecondary
          : DesignColors.textSecondaryLight;
    }

    return Icon(icon, color: color, size: 24);
  }

  Widget? _buildSubtitle(Color color) {
    final parts = <String>[];

    if (entry.permissionString != null) {
      parts.add(entry.permissionString!);
    }

    if (!entry.isDirectory && entry.size != null) {
      parts.add(entry.formattedSize);
    }

    if (entry.modifiedDateTime != null) {
      parts.add(DateFormat('yyyy-MM-dd').format(entry.modifiedDateTime!));
    }

    if (parts.isEmpty) return null;

    return Text(
      parts.join('  '),
      style: TextStyle(color: color, fontSize: 12),
      overflow: TextOverflow.ellipsis,
    );
  }

  static IconData _getFileIcon(String extension) {
    return switch (extension) {
      'md' || 'txt' || 'log' || 'csv' => Icons.description,
      'dart' ||
      'py' ||
      'js' ||
      'ts' ||
      'go' ||
      'rs' ||
      'java' ||
      'c' ||
      'cpp' ||
      'h' ||
      'rb' ||
      'sh' ||
      'bash' ||
      'zsh' => Icons.code,
      'json' ||
      'yaml' ||
      'yml' ||
      'toml' ||
      'xml' ||
      'ini' ||
      'conf' ||
      'cfg' => Icons.settings,
      'jpg' ||
      'jpeg' ||
      'png' ||
      'gif' ||
      'svg' ||
      'webp' ||
      'bmp' ||
      'ico' => Icons.image,
      'mp4' || 'mov' || 'avi' || 'mkv' || 'webm' => Icons.movie,
      'mp3' || 'wav' || 'flac' || 'ogg' || 'aac' => Icons.audio_file,
      'pdf' => Icons.picture_as_pdf,
      'zip' || 'tar' || 'gz' || 'bz2' || 'xz' || '7z' || 'rar' => Icons.archive,
      _ => Icons.insert_drive_file,
    };
  }
}
