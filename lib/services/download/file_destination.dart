import 'dart:io';
import 'dart:typed_data';

import 'download_destination.dart';

/// 実ディレクトリパスベースの [DownloadDestination]。
///
/// Android のアプリ専用領域・iOS のドキュメント領域など、そのまま `File` で
/// 書き込めるパスを対象にする。オーバーヘッドが少なく、他のツールとも共有しやすい。
class FileDestination implements DownloadDestination {
  /// 保存先ディレクトリの絶対パス。
  final String directoryPath;

  FileDestination(this.directoryPath);

  /// [name] をディレクトリに結合した絶対パス。
  String pathOf(String name) => '$directoryPath/$name';

  @override
  Future<bool> exists(String name) async => File(pathOf(name)).exists();

  @override
  Future<DownloadSink> open(String name, {required bool overwrite}) async {
    // `FileMode.write` は常に新規作成/切り詰めで開く。
    //
    // 注意: ロジック上の overwrite（既存を再利用するか）は保存先によって意味が異なり、
    // 本実装ではファイルの格納先が直接見えるため、`false` でも既存を**切り詰めて**
    // 上書きし得る。呼び出し側は `overwrite:false` を選ぶ前に [exists] で非存在を
    // 確認している（衝突解決は UI 層の責務）。ここでは [overwrite] の値に依らず
    // 同じ書込モードを使う（SAF のように採番はしない）。
    return FileSink(File(pathOf(name)));
  }

  @override
  Future<void> dispose() async {
    // ローカルファイルはスコープ解放が不要なため no-op。
  }
}

/// [FileDestination] が開く書込ストリーム実装。
///
/// コンストラクタでは実ファイルを**遅延オープン**する（初回 flush まで実ファイルは生成
/// されない。ディレクトリ欠落等のエラーは書込時（初回 flush）の [FileSystemException] と
/// して顕在化する）。0 バイトファイルは close() 時に正しく生成される（SFTP ダウンロード
/// は成功時に必ず close を呼ぶため機能する）。
class FileSink implements DownloadSink {
  final File _file;
  final IOSink _sink;
  bool _closed = false;

  FileSink(this._file) : _sink = _file.openWrite(mode: FileMode.write);

  @override
  Future<void> add(Uint8List bytes) async {
    if (_closed) {
      throw StateError('FileSink is closed');
    }
    _sink.add(bytes);
    // 各 add で flush し、IOSink の内部バッファを増やさずメモリ使用量を一定に保つ
    // （受入⑥: 全ロードしない方針と対称）。
    await _sink.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sink.close();
  }

  @override
  Future<void> deletePartial() async {
    // flush（ベストエフォート）→ File.delete（ベストエフォート）。
    // どちらも失敗は握りつぶす（SFTP ダウンロードの cleanup と対称）。
    try {
      await close();
    } catch (_) {
      // 握りつぶし。
    }
    try {
      await _file.delete();
    } catch (_) {
      // 握りつぶし。削除できない残骸は呼び出し側のエラー報告に委ねる。
    }
  }
}
