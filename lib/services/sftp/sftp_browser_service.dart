import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import 'file_entry.dart';
import 'preview_too_large_exception.dart';

/// SFTPファイルブラウザサービス
///
/// ディレクトリ一覧取得、削除、名前変更、フォルダ作成などの
/// ブラウザ操作を提供する。アップロード操作は [SftpService] が担当。
class SftpBrowserService {
  static const _listTimeout = Duration(seconds: 10);

  /// バイナリ検知の検査対象となる先頭ブロックのバイト数（目安 8KB）。
  ///
  /// [isLikelyBinary] の NUL 検出・UTF-8 置換文字比率の両方で使う。
  static const int kBinaryCheckBytes = 8 * 1024;

  /// UTF-8 置換文字（U+FFFD）比率のしきい値（目安 1%）。
  ///
  /// NUL 検出を主判定とし、こちらはフォールバック。
  /// 非 UTF-8 系（UTF-16 等）の .md 偽装を検知する。
  static const double kBinaryReplacementRatio = 0.01;

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

  /// ファイルを上限付きで読み込む
  ///
  /// [path] を [validatePath] で正規化した上で read モードでオープンし、
  /// `stat()` のサイズが [maxBytes] を超える場合は**読取前に**
  /// [PreviewTooLargeException] をスローする。
  /// サイズ不明（stat が null）・伸長ファイルに備えて常に
  /// `readBytes(length: maxBytes + 1)` で読み取り、[maxBytes] を超えた分が
  /// 読まれた場合（戻り値の `isTruncated == true`）で切詰めを検知する。
  ///
  /// 戻り値は named record `({Uint8List bytes, bool isTruncated})`。
  ///
  /// ## close 規約（重要）
  /// - [SftpFile] はオープン後**必ず** `close()` する（finally で保証）。
  /// - [SftpClient] は `close()` **しない**。SshClient がキャッシュ管理して
  ///   おり、close すると SSH チャネル枯渇の実障害（939a298）を招く。
  static Future<({Uint8List bytes, bool isTruncated})> readFileAsBytes(
    SftpClient sftp,
    String path, {
    required int maxBytes,
  }) async {
    final normalizedPath = validatePath(path);
    final file = await sftp.open(
      normalizedPath,
      mode: SftpFileOpenMode.read,
    );
    try {
      // 読取前のサイズ確認（symlink は follow した実サイズ・目安扱い・合意#4）
      final attrs = await file.stat();
      final size = attrs.size;
      if (size != null && size > maxBytes) {
        throw PreviewTooLargeException(
          path: normalizedPath,
          size: size,
          maxBytes: maxBytes,
        );
      }
      // 上限+1 バイトで読み取る（size 不明・伸長ファイルの切詰め検知を兼ねる）
      final bytes = await file.readBytes(length: maxBytes + 1);
      return (bytes: bytes, isTruncated: bytes.length > maxBytes);
    } finally {
      // SftpFile は必ず close。SftpClient は close しない（キャッシュ契約）。
      await file.close();
    }
  }

  /// バイナリ可能性を判定する純関数
  ///
  /// ①先頭 [kBinaryCheckBytes]（8KB）ブロック内の NUL バイト（0x00）検出
  /// （主判定・実質決定的。テキスト .md に NUL はほぼ無い）
  /// ②UTF-8 デコード（`allowMalformed: true`）の置換文字（U+FFFD）比率が
  /// [kBinaryReplacementRatio] を超えるか（フォールバック・非 UTF-8 系対策）
  /// のいずれかで判定する。空バイト列は false。
  ///
  /// 副作用なし（sync・純関数）。decode はここで行わない（呼び出し側の責務）。
  static bool isLikelyBinary(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    final head = bytes.length < kBinaryCheckBytes
        ? bytes
        : Uint8List.sublistView(bytes, 0, kBinaryCheckBytes);
    for (final b in head) {
      if (b == 0x00) return true;
    }
    final decoded = utf8.decode(head, allowMalformed: true);
    var replacementCount = 0;
    for (final rune in decoded.runes) {
      if (rune == 0xFFFD) replacementCount++;
    }
    return replacementCount / decoded.runes.length > kBinaryReplacementRatio;
  }

  /// パスを正規化・検証
  ///
  /// パストラバーサル攻撃を防ぐため、パスを正規化する。
  /// 絶対パスのみ許可する。
  static String validatePath(String path) {
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
