import 'package:dartssh2/dartssh2.dart';

/// ソートオプション
enum SortOption { name, size, date, type }

/// リモートファイルシステムのエントリ（ファイルまたはディレクトリ）
class FileEntry {
  final String name;
  final String fullPath;
  final bool isDirectory;
  final bool isSymlink;
  final int? size;
  final int? modifiedTime;
  final String? permissionString;

  const FileEntry({
    required this.name,
    required this.fullPath,
    required this.isDirectory,
    this.isSymlink = false,
    this.size,
    this.modifiedTime,
    this.permissionString,
  });

  /// SftpName から FileEntry を生成
  factory FileEntry.fromSftpName(SftpName sftpName, String parentPath) {
    final attr = sftpName.attr;
    final isLink = attr.isSymbolicLink;
    // シンボリックリンクの場合、longname の先頭 'd' でディレクトリリンクを判定
    final isDir =
        attr.isDirectory ||
        (isLink && sftpName.longname.isNotEmpty && sftpName.longname[0] == 'd');
    final name = sftpName.filename;
    final fullPath = parentPath.endsWith('/')
        ? '$parentPath$name'
        : '$parentPath/$name';

    return FileEntry(
      name: name,
      fullPath: fullPath,
      isDirectory: isDir,
      isSymlink: isLink,
      size: isDir ? null : attr.size,
      modifiedTime: attr.modifyTime,
      permissionString: _formatPermissions(attr.mode),
    );
  }

  /// 隠しファイル（ドットファイル）かどうか
  bool get isHidden => name.startsWith('.');

  /// ファイル拡張子を取得
  String get extension {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  /// 更新日時を DateTime に変換
  DateTime? get modifiedDateTime {
    if (modifiedTime == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(modifiedTime! * 1000);
  }

  /// サイズを人間が読める形式にフォーマット
  String get formattedSize {
    if (size == null) return '';
    if (size! < 1024) return '$size B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)} KB';
    if (size! < 1024 * 1024 * 1024) {
      return '${(size! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// SftpFileMode からパーミッション文字列を生成（例: "rwxr-xr-x"）
  static String? _formatPermissions(SftpFileMode? mode) {
    if (mode == null) return null;
    final raw = mode.value & 0x1FF;
    final buf = StringBuffer();
    for (var i = 8; i >= 0; i--) {
      if (raw & (1 << i) != 0) {
        switch (i % 3) {
          case 2:
            buf.write('r');
          case 1:
            buf.write('w');
          case 0:
            buf.write('x');
        }
      } else {
        buf.write('-');
      }
    }
    return buf.toString();
  }

  @override
  String toString() => 'FileEntry($name, dir=$isDirectory, size=$size)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileEntry &&
          runtimeType == other.runtimeType &&
          fullPath == other.fullPath;

  @override
  int get hashCode => fullPath.hashCode;
}
