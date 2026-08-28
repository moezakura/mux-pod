import 'package:flutter_muxpod/providers/file_browser_provider.dart';
import 'package:flutter_muxpod/services/sftp/file_entry.dart';

/// FileBrowserScreen テスト用の [FileBrowserNotifier] フェイク。
///
/// 固定の表示エントリを返し、SftpBrowserService への実アクセス（listdir 等）を
/// 行わない。`initialize` は no-op（画面 mount 時の CWD 解決を回避）。
class FakeFileBrowserNotifier extends FileBrowserNotifier {
  FakeFileBrowserNotifier({required this.entries});

  final List<FileEntry> entries;

  /// タップ遷移（navigateToDirectory）の記録（T15 テスト用・実 SFTP は行わない）。
  final List<String> navigatedPaths = [];

  @override
  FileBrowserState build() => FileBrowserState(entries: entries);

  @override
  Future<void> initialize(String? paneId) async {
    // no-op: 実ディレクトリ解決は不要（固定 entries を表示するだけ）。
  }

  @override
  Future<void> navigateToDirectory(String path) async {
    navigatedPaths.add(path);
  }
}