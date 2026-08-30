import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/sftp/sftp_statvfs.dart';

/// [SftpClient] インターフェースを実装した fake。
///
/// ディレクトリエントリは [entriesByPath] で提供する。
/// ファイル内容は [contentsByPath] で提供し、`open` で [FakeSftpFile] を返す。
class FakeSftpClient implements SftpClient {
  final Map<String, List<SftpName>> entriesByPath;
  final Map<String, Uint8List> contentsByPath;
  final String homeDirectory;
  final List<String> listdirCalls = [];
  final List<(String, String)> renameCalls = [];

  /// `close()` が呼ばれた回数（SftpClient 側。呼び出し側 close 禁止契約の検証用）。
  int closeCalls = 0;

  /// `remove()` が呼ばれたファイルパス（部分削除の検証用）。
  final List<String> removeCalls = [];

  /// `open()` が返した [FakeSftpFile]（書き込み内容の検証用・#41）。
  final List<FakeSftpFile> openedFiles = [];

  FakeSftpClient({
    this.entriesByPath = const {},
    this.contentsByPath = const {},
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
    // SftpService.ensureDirectory が stat を try { } on SftpStatusError { mkdir } で呼ぶため、
    // 存在しないパスは SftpStatusError を投げる（UnimplementedError だと捕捉されない）。
    final isKnown =
        path == '/' ||
        path == '.' ||
        path == '..' ||
        path == homeDirectory ||
        entriesByPath.containsKey(path);
    if (!isKnown) {
      throw SftpStatusError(SftpStatusCode.noSuchFile, 'No such file');
    }
    return _makeEntry(path, true).attr;
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
    final file = FakeSftpFile(this, contentsByPath[path] ?? Uint8List(0));
    openedFiles.add(file);
    return file;
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
  Future<void> remove(String filename) async {
    removeCalls.add(filename);
  }

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
  Future<void> close() async {
    closeCalls++;
  }
}

/// [SftpFile] を継承した fake。
///
/// `read` / `writeBytes` / `close` を差し替える。
/// `close()` は super を呼ばず closeCalls 計数のみ行う
/// （super の close は private `_client._close(_handle)` を呼ぶため
/// FakeSftpClient では NoSuchMethodError になる）。
class FakeSftpFile extends SftpFile {
  Uint8List _content;
  final int? size;

  /// `close()` が呼ばれた回数（ファイルハンドル close 正常の検証用）。
  int closeCalls = 0;

  /// #40 テスト拡張: チャンク分割 emit サイズ（read 呼び出しの [emitChunkSize] で上書き可能）。
  /// 未指定（null）なら従来どおり単発チャンク emit（基盤テスト互換）。
  final int? emitChunkSize;

  /// #40 テスト拡張: 各チャンク emit 前に await するフック（read 呼び出しの [beforeEmit] で上書き可能）。
  /// 戻り Future が完了するまでそのチャンクは emit されない（キャンセル境界テスト用）。
  final Future<void> Function(int chunkIndex)? beforeEmit;

  FakeSftpFile(
    SftpClient client,
    Uint8List content, {
    this.size,
    this.emitChunkSize,
    this.beforeEmit,
  }) : _content = content,
       super(client, Uint8List(0));

  /// 現在の内容（読取専用）。テスト用アクセサ。
  Uint8List get content => _content;

  @override
  Stream<Uint8List> read({
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 64 * 1024,
    int maxPendingRequests = 128,
    // #40 テスト拡張: 指定時はこのサイズでチャンク分割 emit する。
    // 未指定（null・0 以下）ならインスタンス既定値（未設定＝単発チャンク）に従う。
    int? emitChunkSize,
    // #40 テスト拡張: 各チャンク emit 前に await するフック。
    // 戻り Future が完了するまでそのチャンクは emit されない（キャンセル境界テスト用）。
    Future<void> Function(int chunkIndex)? beforeEmit,
  }) async* {
    final start = offset.clamp(0, _content.length);
    final end = length == null
        ? _content.length
        : (start + length).clamp(0, _content.length);
    final slice = Uint8List.sublistView(_content, start, end);

    // チャンク列を構築する（既定＝単発・拡張時＝emitChunkSize 分割）。
    final effectiveEmit = emitChunkSize ?? this.emitChunkSize;
    final effectiveBeforeEmit = beforeEmit ?? this.beforeEmit;
    final chunks = <Uint8List>[];
    if (effectiveEmit != null && effectiveEmit > 0) {
      for (var from = 0; from < slice.length; from += effectiveEmit) {
        var to = from + effectiveEmit;
        if (to > slice.length) to = slice.length;
        chunks.add(Uint8List.sublistView(slice, from, to));
      }
    } else {
      chunks.add(slice);
    }

    var done = 0;
    for (var i = 0; i < chunks.length; i++) {
      await effectiveBeforeEmit?.call(i);
      done += chunks[i].length;
      onProgress?.call(done);
      yield chunks[i];
    }
  }

  @override
  Future<SftpFileAttrs> stat() async {
    return SftpFileAttrs(
      mode: SftpFileMode.value(0x81A4),
      size: size ?? _content.length,
      modifyTime: DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000,
    );
  }

  @override
  Future<void> writeBytes(Uint8List data, {int offset = 0}) async {
    // offset 位置へ data を配置。連続 writeBytes（offset を増やしながら）で正しく連結する。
    // offset 末尾が現内容長を超える場合はゼロパディングで拡張する。
    final end = offset + data.length;
    if (end > _content.length) {
      final grown = Uint8List(end);
      grown.setRange(0, _content.length, _content);
      _content = grown;
    }
    _content.setRange(offset, end, data);
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}
