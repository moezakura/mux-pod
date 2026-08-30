import 'dart:typed_data';

import 'package:saf_stream/saf_stream.dart';
import 'package:saf_stream/saf_stream_platform_interface.dart';
import 'package:saf_util/saf_util.dart';

import 'download_destination.dart';

/// Android Storage Access Framework（SAF）の tree URI ベースの [DownloadDestination]。
///
/// ユーザーがフォルダを選択（writePermission 付与）した際の `content://…/tree/…` を
/// [treeUri] に保持し、ファイルの存在確認・書込・削除を SAF 経由で行う。
///
/// 保存先としての特性:
/// - [exists]: `SafUtil.child(treeUri, [name])` の null 判定。
/// - [open]: `SafStream.startWriteStream` でネイティブストリームを開く。
///   `overwrite:true` は既存ファイルを**再利用して切り詰め**、`false` は**常に新規作成**
///   で SAF 側が自動採番する（`name (1).ext` 等）。
/// - [dispose]: SAF はスコープ解放が不要（URI は pickDirectory 時に永続権限が付与される）
///   ため no-op。
class SafDirectoryDestination implements DownloadDestination {
  /// SAF のフォルダ tree URI 文字列。
  final String treeUri;

  SafDirectoryDestination(this.treeUri);

  @override
  Future<bool> exists(String name) async {
    final childFile = await SafUtil().child(treeUri, [name]);
    return childFile != null;
  }

  @override
  Future<DownloadSink> open(String name, {required bool overwrite}) async {
    final info = await SafStream().startWriteStream(
      treeUri,
      name,
      'application/octet-stream',
      overwrite: overwrite,
    );
    return SafSink(info);
  }

  @override
  Future<void> dispose() async {
    // SAF はスコープ解除不要（pickDirectory 時の書き込み権限が永続化される）ため no-op。
  }
}

/// [SafDirectoryDestination] が開く書込ストリーム実装。
///
/// [SafWriteStreamInfo]（session + 生成/利用したファイル URI）を保持し、[add] を
/// `SafStream.writeChunk` でネイティブへ送る。閉じるときは [SafStream.endWriteStream]
/// で確定する。
class SafSink implements DownloadSink {
  final SafWriteStreamInfo _info;
  bool _closed = false;

  SafSink(this._info);

  @override
  Future<void> add(Uint8List bytes) {
    if (_closed) {
      throw StateError('SafSink is closed');
    }
    // SAF ストリームは writeChunk が直接ネイティブへ書き込むため追加の flush は不要。
    return SafStream().writeChunk(_info.session, bytes);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await SafStream().endWriteStream(_info.session);
  }

  @override
  Future<void> deletePartial() async {
    // endWriteStream（ベストエフォート）→ 生成したファイル削除（ベストエフォート）。
    // どちらも失敗は握りつぶす（SFTP ダウンロードの cleanup と対称）。
    try {
      await close();
    } catch (_) {
      // 握りつぶし。
    }
    try {
      await SafUtil().delete(_info.fileResult.uri.toString(), false);
    } catch (_) {
      // 握りつぶし。削除できない残骸は呼び出し側のエラー報告に委ねる。
    }
  }
}
