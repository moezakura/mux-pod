import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import 'file_entry.dart';

/// SFTPファイルブラウザサービス
///
/// ディレクトリ一覧取得、削除、名前変更、フォルダ作成などの
/// ブラウザ操作を提供する。アップロード操作は [SftpService] が担当。
class SftpBrowserService {
  static const _listTimeout = Duration(seconds: 10);

  /// ディレクトリ一覧を取得
  ///
  /// [path] のディレクトリ内容を [FileEntry] のリストとして返す。
  /// `.` と `..` エントリは除外される。
  /// タイムアウト（10秒）を超えた場合は例外をスローする。
  Future<List<FileEntry>> listDirectory(SftpClient sftp, String path) async {
    final normalizedPath = validatePath(path);
    final names = await sftp.listdir(normalizedPath).timeout(_listTimeout);

    return names
        .where((n) => n.filename != '.' && n.filename != '..')
        .map((n) => FileEntry.fromSftpName(n, normalizedPath))
        .toList();
  }

  /// ファイルを削除
  Future<void> deleteFile(SftpClient sftp, String path) async {
    final normalizedPath = validatePath(path);
    await sftp.remove(normalizedPath);
  }

  /// ディレクトリを削除（空のディレクトリのみ）
  Future<void> deleteDirectory(SftpClient sftp, String path) async {
    final normalizedPath = validatePath(path);
    await sftp.rmdir(normalizedPath);
  }

  /// ファイルまたはディレクトリの名前を変更
  Future<void> rename(SftpClient sftp, String oldPath, String newPath) async {
    final normalizedOld = validatePath(oldPath);
    final normalizedNew = validatePath(newPath);
    await sftp.rename(normalizedOld, normalizedNew);
  }

  /// ディレクトリを作成
  Future<void> createDirectory(SftpClient sftp, String path) async {
    final normalizedPath = validatePath(path);
    await sftp.mkdir(normalizedPath);
  }

  /// ホームディレクトリのパスを取得
  Future<String> getHomeDirectory(SftpClient sftp) async {
    return await sftp.absolute('.');
  }

  /// パスを正規化・検証
  ///
  /// パストラバーサル攻撃を防ぐため、パスを正規化する。
  /// 絶対パスのみ許可する。
  String validatePath(String path) {
    if (path.isEmpty) return '/';
    final normalized = p.posix.normalize(path);
    if (!normalized.startsWith('/')) {
      return '/$normalized';
    }
    return normalized;
  }

  /// エントリをソート
  List<FileEntry> sortEntries(
    List<FileEntry> entries,
    SortOption option,
    bool ascending,
  ) {
    final sorted = List<FileEntry>.from(entries);
    sorted.sort((a, b) {
      // ディレクトリを常に先頭に
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      int result;
      switch (option) {
        case SortOption.name:
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortOption.size:
          result = (a.size ?? 0).compareTo(b.size ?? 0);
        case SortOption.date:
          result = (a.modifiedTime ?? 0).compareTo(b.modifiedTime ?? 0);
        case SortOption.type:
          result = a.extension.compareTo(b.extension);
          if (result == 0) {
            result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
      }
      return ascending ? result : -result;
    });
    return sorted;
  }

  /// 隠しファイルをフィルタリング
  List<FileEntry> filterHidden(List<FileEntry> entries, bool showHidden) {
    if (showHidden) return entries;
    return entries.where((e) => !e.isHidden).toList();
  }
}
