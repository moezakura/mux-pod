import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sftp/file_entry.dart';
import '../services/sftp/sftp_browser_service.dart';
import '../services/ssh/ssh_client.dart';
import '../services/tmux/tmux_models.dart';
import '../l10n/l10n_lookup.dart';

import 'ssh_provider.dart';
import 'tmux_provider.dart';

// inventory: FILE-001
/// ファイルブラウザの状態
class FileBrowserState {
  // inventory: FILE-002
  // inventory: LEGACY-0030
  final String currentPath;
  // inventory: FILE-003
  // inventory: LEGACY-0031
  final List<FileEntry> entries;
  // inventory: FILE-004
  // inventory: LEGACY-0032
  final bool isLoading;
  // inventory: FILE-005
  // inventory: LEGACY-0033
  final String? error;
  // inventory: FILE-006
  // inventory: LEGACY-0034
  final SortOption sortOption;
  // inventory: FILE-007
  // inventory: LEGACY-0035
  final bool sortAscending;
  // inventory: FILE-008
  // inventory: LEGACY-0036
  final bool showHidden;

  const FileBrowserState({
    this.currentPath = '/',
    this.entries = const [],
    this.isLoading = false,
    this.error,
    this.sortOption = SortOption.name,
    this.sortAscending = true,
    this.showHidden = false,
  });

  // inventory: FILE-009
  // inventory: LEGACY-0037
  FileBrowserState copyWith({
    String? currentPath,
    List<FileEntry>? entries,
    bool? isLoading,
    String? error,
    SortOption? sortOption,
    bool? sortAscending,
    bool? showHidden,
  }) {
    return FileBrowserState(
      currentPath: currentPath ?? this.currentPath,
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      sortOption: sortOption ?? this.sortOption,
      sortAscending: sortAscending ?? this.sortAscending,
      showHidden: showHidden ?? this.showHidden,
    );
  }

  // inventory: FILE-010
  /// ソート・フィルタ適用済みのエントリ一覧
  List<FileEntry> get displayEntries {
    final service = _cachedBrowserService;
    final filtered = service.filterHidden(entries, showHidden);
    return service.sortEntries(filtered, sortOption, sortAscending);
  }

  static final _cachedBrowserService = SftpBrowserService();
}

// inventory: FILE-011
/// ファイルブラウザのNotifier
///
/// tmuxペインに1:1で紐づき、ペインのCWDを初期ディレクトリとして使用する。
/// AutoDisposeNotifier を使用し、画面を閉じたら自動的に破棄される。
class FileBrowserNotifier extends Notifier<FileBrowserState> {
  // inventory: FILE-012
  final SftpBrowserService _browserService = SftpBrowserService();

  // inventory: FILE-013
  /// 並走対策用バージョン番号
  int _listVersion = 0;

  /// SSH接続状態監視
  StreamSubscription<SshConnectionState>? _connectionSub;

  @override
  // inventory: FILE-014
  // inventory: LEGACY-0038
  FileBrowserState build() {
    ref.onDispose(() {
      _connectionSub?.cancel();
    });
    return const FileBrowserState();
  }

  // inventory: FILE-015
  // inventory: LEGACY-0039
  /// ファイルブラウザを初期化
  ///
  /// [paneId] に紐づくペインのCWDを初期ディレクトリとして使用する。
  /// CWDが取得できない場合はホームディレクトリにフォールバック。
  Future<void> initialize(String? paneId) async {
    // 前回のエラー状態をクリア
    _log('initialize START (paneId=$paneId)');
    state = const FileBrowserState();

    final tmuxState = ref.read(tmuxProvider);
    // inventory: LEGACY-0040
    String? initialPath;

    // ペインのCWDを取得
    if (paneId != null) {
      final pane = _findPaneById(tmuxState, paneId);
      initialPath = pane?.currentPath;
    }

    // SSH接続状態を監視
    // inventory: FILE-026
    _startConnectionMonitoring();

    // 初期ディレクトリを決定
    if (initialPath != null && initialPath.isNotEmpty) {
      // inventory: FILE-016
      // inventory: LEGACY-0041
      await loadDirectory(initialPath);
    } else {
      // ホームディレクトリにフォールバック
      // inventory: FILE-025
      await _loadHomeDirectory();
    }
  }

  /// ディレクトリを読み込み
  Future<void> loadDirectory(String path) async {
    final version = ++_listVersion;
    _log('loadDirectory START (path=$path, version=$version)');

    state = state.copyWith(
      isLoading: true,
      error: null,
      currentPath: path,
      entries: path != state.currentPath ? const [] : null,
    );

    try {
      final sshClient = _getSshClient();
      _log('loadDirectory openSftp START');
      final sftp = await sshClient.openSftp();
      _log('loadDirectory openSftp OK');
      final entries = await _browserService.listDirectory(sftp, path);
      _log('loadDirectory listDirectory OK (entries=${entries.length})');

      // 並走対策: 古いリクエストの結果は破棄
      if (version != _listVersion) {
        _log('loadDirectory STALE (version=$version, current=$_listVersion)');
        return;
      }

      state = state.copyWith(
        entries: entries,
        isLoading: false,
        currentPath: path,
      );
    } catch (e) {
      _log('loadDirectory ERROR: $e');
      if (version != _listVersion) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // inventory: FILE-017
  // inventory: LEGACY-0042
  /// 子ディレクトリに遷移
  Future<void> navigateToDirectory(String path) async {
    await loadDirectory(path);
  }

  // inventory: FILE-018
  // inventory: LEGACY-0043
  /// 親ディレクトリに遷移
  Future<void> navigateUp() async {
    final parent = _getParentPath(state.currentPath);
    if (parent != state.currentPath) {
      await loadDirectory(parent);
    }
  }

  // inventory: FILE-019
  // inventory: LEGACY-0044
  /// ソートオプションを変更
  void setSort(SortOption option, {bool? ascending}) {
    if (option == state.sortOption && ascending == null) {
      state = state.copyWith(sortAscending: !state.sortAscending);
    } else {
      state = state.copyWith(
        sortOption: option,
        sortAscending: ascending ?? true,
      );
    }
  }

  // inventory: FILE-020
  // inventory: LEGACY-0045
  /// 隠しファイル表示を切り替え
  void toggleShowHidden() {
    state = state.copyWith(showHidden: !state.showHidden);
  }

  // inventory: FILE-021
  // inventory: LEGACY-0046
  /// ファイルまたはディレクトリを削除
  Future<bool> delete(FileEntry entry) async {
    _log('delete START (path=${entry.fullPath})');
    try {
      final sshClient = _getSshClient();
      _log('delete openSftp START');
      final sftp = await sshClient.openSftp();
      _log('delete openSftp OK');
      if (entry.isDirectory) {
        await _browserService.deleteDirectory(sftp, entry.fullPath);
      } else {
        await _browserService.deleteFile(sftp, entry.fullPath);
      }
      _log('delete operation OK');
    } catch (e) {
      _log('delete ERROR: $e');
      state = state.copyWith(error: lookupL10n().fileDeleteFailureDetail('$e'));
      return false;
    }
    await loadDirectory(state.currentPath);
    return true;
  }

  // inventory: FILE-022
  // inventory: LEGACY-0047
  /// ファイルまたはディレクトリの名前を変更
  Future<bool> rename(FileEntry entry, String newName) async {
    _log('rename START (path=${entry.fullPath}, newName=$newName)');
    try {
      final parentDir = _getParentPath(entry.fullPath);
      final newPath = parentDir.endsWith('/')
          ? '$parentDir$newName'
          : '$parentDir/$newName';

      final sshClient = _getSshClient();
      _log('rename openSftp START');
      final sftp = await sshClient.openSftp();
      _log('rename openSftp OK');
      await _browserService.rename(sftp, entry.fullPath, newPath);
      _log('rename operation OK');
    } catch (e) {
      _log('rename ERROR: $e');
      state = state.copyWith(error: lookupL10n().fileRenameFailureDetail('$e'));
      return false;
    }
    await loadDirectory(state.currentPath);
    return true;
  }

  // inventory: FILE-023
  // inventory: LEGACY-0048
  /// 新規フォルダを作成
  Future<bool> createDirectory(String name) async {
    _log('createDirectory START (name=$name)');
    try {
      final newPath = state.currentPath.endsWith('/')
          ? '${state.currentPath}$name'
          : '${state.currentPath}/$name';

      final sshClient = _getSshClient();
      _log('createDirectory openSftp START');
      final sftp = await sshClient.openSftp();
      _log('createDirectory openSftp OK');
      await _browserService.createDirectory(sftp, newPath);
      _log('createDirectory operation OK');
    } catch (e) {
      _log('createDirectory ERROR: $e');
      state = state.copyWith(
        error: lookupL10n().fileCreateFolderFailureDetail('$e'),
      );
      return false;
    }
    await loadDirectory(state.currentPath);
    return true;
  }

  // inventory: FILE-024
  // inventory: LEGACY-0049
  /// 現在のディレクトリをリロード
  Future<void> refresh() async {
    await loadDirectory(state.currentPath);
  }

  // --- Private methods ---

  SshClient _getSshClient() {
    final client = ref.read(sshProvider.notifier).client;
    if (client == null || !client.isConnected) {
      throw StateError(lookupL10n().termSshNotAvailable);
    }
    return client;
  }

  Future<void> _loadHomeDirectory() async {
    _log('_loadHomeDirectory START');
    try {
      final sshClient = _getSshClient();
      _log('_loadHomeDirectory openSftp START');
      final sftp = await sshClient.openSftp();
      _log('_loadHomeDirectory openSftp OK');
      // inventory: LEGACY-0050
      String homePath;
      try {
        homePath = await _browserService.getHomeDirectory(sftp);
        _log('_loadHomeDirectory getHomeDirectory OK (path=$homePath)');
      } catch (e) {
        _log('_loadHomeDirectory getHomeDirectory ERROR: $e');
        homePath = '/';
      }
      await loadDirectory(homePath);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: lookupL10n().fileLoadHomeFailed('$e'),
      );
    }
  }

  void _startConnectionMonitoring() {
    _connectionSub?.cancel();
    final client = ref.read(sshProvider.notifier).client;
    if (client == null) return;

    _connectionSub = client.connectionStateStream.listen((connState) {
      if (connState == SshConnectionState.disconnected ||
          connState == SshConnectionState.error) {
        state = state.copyWith(
          error: lookupL10n().fileSshConnectionLost,
          isLoading: false,
        );
      }
    });
  }

  // inventory: FILE-027
  TmuxPane? _findPaneById(TmuxState tmuxState, String paneId) {
    for (final session in tmuxState.sessions) {
      for (final window in session.windows) {
        for (final pane in window.panes) {
          if (pane.id == paneId) return pane;
        }
      }
    }
    return null;
  }

  // inventory: FILE-028
  String _getParentPath(String path) {
    if (path == '/') return '/';
    final normalized = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash <= 0) return '/';
    return normalized.substring(0, lastSlash);
  }

  static int _sftpOpenCount = 0;
  static int _sftpCloseCount = 0;

  void _log(String message) {
    if (message.contains('openSftp OK')) _sftpOpenCount++;
    if (message.contains('sftp.close()')) _sftpCloseCount++;
    debugPrint(
      '[FileBrowser] $message (open=$_sftpOpenCount, close=$_sftpCloseCount, leaked=${_sftpOpenCount - _sftpCloseCount})',
    );
  }
}

// inventory: FILE-029
/// ファイルブラウザ Provider
final fileBrowserProvider =
    NotifierProvider<FileBrowserNotifier, FileBrowserState>(
      FileBrowserNotifier.new,
    );
