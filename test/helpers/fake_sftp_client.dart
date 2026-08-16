import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/sftp/sftp_statvfs.dart';

/// [SftpClient] インターフェースを実装した fake。
///
/// ディレクトリエントリは [entriesByPath] で提供する。
class FakeSftpClient implements SftpClient {
  final Map<String, List<SftpName>> entriesByPath;
  final String homeDirectory;
  final List<String> listdirCalls = [];
  final List<(String, String)> renameCalls = [];

  FakeSftpClient({
    this.entriesByPath = const {},
    this.homeDirectory = '/home/user',
  });

  SftpName _makeEntry(String name, bool isDirectory, {int? size}) {
    final mode = SftpFileMode.value(isDirectory ? 0x41ED : 0x81A4);
    return SftpName(
      filename: name,
      longname: isDirectory ? 'drwxr-xr-x' : '-rw-r--r--',
      attr: SftpFileAttrs(
        mode: mode,
        size: isDirectory ? null : size,
        modifyTime: DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000,
      ),
    );
  }

  List<SftpName> _listFor(String path) {
    return entriesByPath[path] ??
        [
          _makeEntry('..', true),
          _makeEntry('.', true),
          _makeEntry('file.txt', false, size: 42),
        ];
  }

  @override
  final SSHPrintHandler? printDebug = null;

  @override
  final SSHPrintHandler? printTrace = null;

  @override
  Future<SftpHandsake> get handshake async => SftpHandsake(3, const {});

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> setStat(String path, SftpFileAttrs attrs) async {
    throw UnimplementedError();
  }

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<int> download(
    String path,
    StreamSink<List<int>> destination, {
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 64 * 1024,
    int maxPendingRequests = 128,
    bool closeDestination = false,
  }) async {
    throw UnimplementedError();
  }

  @override
  Stream<List<SftpName>> readdir(String path) {
    return Stream.fromIterable([_listFor(path)]);
  }

  @override
  Future<List<SftpName>> listdir(String path) async {
    listdirCalls.add(path);
    return _listFor(path);
  }

  @override
  Future<void> remove(String filename) async {}

  @override
  Future<void> mkdir(String path, [SftpFileAttrs? attrs]) async {}

  @override
  Future<void> rmdir(String dirname) async {}

  @override
  Future<String> absolute(String path) async {
    if (path == '.') return homeDirectory;
    return path;
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    renameCalls.add((oldPath, newPath));
  }

  @override
  Future<String> readlink(String path) async {
    throw UnimplementedError();
  }

  @override
  Future<void> link(String linkPath, String targetPath) async {
    throw UnimplementedError();
  }

  @override
  Future<SftpStatVfs> statvfs(String path) async {
    throw UnimplementedError();
  }

  @override
  Future<void> close() async {}
}
