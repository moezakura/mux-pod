import 'package:flutter/services.dart';

import 'download_destination.dart';
import 'file_destination.dart';

/// iOS セキュリティスコープ付きフォルダ（UIDocumentPicker のフォルダ選択）の
/// MethodChannel クライアント。
///
/// ネイティブ側（ios/Runner/ScopedFolderChannel.swift）の
/// `mux.pod/scoped_folder` チャンネルと通信する。iOS では、ユーザーが選んだフォルダへ
/// ファイルを書き込むために「ブックマークの取得 → スコープアクセス開始 → 終了」の
/// 手順が必要なため、このクライアントがその手順を Flutter 側から扱えるようにする。
class IosScopedFolder {
  static const _channel = MethodChannel('mux.pod/scoped_folder');

  const IosScopedFolder();

  /// フォルダ選択ダイアログを表示し、base64 エンコードされたセキュリティスコープ
  /// ブックマークを返す。
  ///
  /// キャンセル時は `null`、選択・ブックマーク生成失敗時は
  /// [PlatformException] を投げる。
  Future<String?> pickFolder() {
    return _channel.invokeMethod<String>('pickFolder');
  }

  /// [bookmark]（pickFolder が返した base64 ブックマーク）からスコープアクセスを開始し、
  /// フォルダのファイルパスを返す。
  ///
  /// ブックマーク不正・stale 等は [PlatformException] を投げる。成功したら、対応する
  /// [stopScope] で必ずアクセスを終了すること。
  Future<String> startScope(String bookmark) async {
    final path = await _channel.invokeMethod<String>('startScope', bookmark);
    if (path == null) {
      throw PlatformException(
        code: 'scoped_folder_returned_null',
        message: 'startScope returned null',
      );
    }
    return path;
  }

  /// startScope で開始したスコープアクセスを終了する。
  Future<void> stopScope() async {
    await _channel.invokeMethod('stopScope');
  }
}

/// iOS セキュリティスコープ付きフォルダを表す [DownloadDestination]。
///
/// [prepare] でブックマークからスコープアクセスを開始し、得られた実パスを
/// [FileDestination] へ委譲する。複数ファイルの書込が終わったら [dispose] で
/// `stopScope` を呼び、スコープを解放する。
///
/// 契約:
/// - [exists] / [open] は、まだ準備済みでなければ [prepare] 相当（startScope）を
///   遅延実行してから [FileDestination] に委譲する。
/// - [dispose] はスコープアクセスを終了する。以後は [exists] / [open] を呼ばない。
class IosScopedDirectoryDestination implements DownloadDestination {
  /// 選択時のセキュリティスコープブックマーク（base64）。
  final String bookmark;

  FileDestination? _delegate;

  IosScopedDirectoryDestination({required this.bookmark});

  /// ブックマークからスコープアクセスを開始し、利用可能な
  /// [IosScopedDirectoryDestination] を返す。
  ///
  /// アクセスの開始に失敗した場合は [PlatformException] を投げる。
  static Future<IosScopedDirectoryDestination> prepare({
    required String bookmark,
  }) async {
    final dest = IosScopedDirectoryDestination(bookmark: bookmark);
    await dest._ensurePrepared();
    return dest;
  }

  @override
  Future<bool> exists(String name) async {
    final delegate = await _ensurePrepared();
    return delegate.exists(name);
  }

  @override
  Future<DownloadSink> open(String name, {required bool overwrite}) async {
    final delegate = await _ensurePrepared();
    return delegate.open(name, overwrite: overwrite);
  }

  @override
  Future<void> dispose() async {
    // iOS スコープアクセスを解放する（他のプラットフォームと違い必須）。
    await const IosScopedFolder().stopScope();
    _delegate = null;
  }

  /// まだなら startScope を実行して [FileDestination] を用意する。
  Future<FileDestination> _ensurePrepared() async {
    var delegate = _delegate;
    if (delegate != null) return delegate;
    final path = await const IosScopedFolder().startScope(bookmark);
    delegate = FileDestination(path);
    _delegate = delegate;
    return delegate;
  }
}
