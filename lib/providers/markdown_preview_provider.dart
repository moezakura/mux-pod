import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n_lookup.dart';
import '../services/sftp/file_entry.dart';
import '../services/sftp/preview_too_large_exception.dart';
import '../services/sftp/sftp_browser_service.dart';
import '../services/ssh/ssh_client.dart';

import 'ssh_provider.dart';

/// Markdown プレビューのサイズ上限（20MB・合意#1 確定値）。
///
/// 遷移前の [FileEntry.size] チェックと open 後の stat チェックの両方で使う。
/// 実メモリ保護は [SftpBrowserService.readFileAsBytes] の
/// `readBytes(length: maxBytes + 1)` で担保される。
const int maxPreviewBytes = 20 * 1024 * 1024;

/// Markdown プレビュー画面の状態
///
/// content はプレビュー画面の lifetime のみ保持し永続化しない（L2-3）。
/// size は [mdFileTooLargeMessage] に渡す MB 表記（実サイズ切り上げ・LOW-1）。
class MarkdownPreviewState {
  final String path;
  final String content;
  final bool isLoading;
  final String? error;
  final bool isTooLarge;
  final bool isBinary;
  final bool isTruncated;
  final int? size;

  const MarkdownPreviewState({
    this.path = '',
    this.content = '',
    this.isLoading = false,
    this.error,
    this.isTooLarge = false,
    this.isBinary = false,
    this.isTruncated = false,
    this.size,
  });

  MarkdownPreviewState copyWith({
    String? path,
    String? content,
    bool? isLoading,
    String? error,
    bool? isTooLarge,
    bool? isBinary,
    bool? isTruncated,
    int? size,
  }) {
    return MarkdownPreviewState(
      path: path ?? this.path,
      content: content ?? this.content,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isTooLarge: isTooLarge ?? this.isTooLarge,
      isBinary: isBinary ?? this.isBinary,
      isTruncated: isTruncated ?? this.isTruncated,
      size: size ?? this.size,
    );
  }
}

/// Markdown プレビューを管理する Notifier
///
/// [Notifier] を使用し、プレビュー画面を閉じたら自動的に破棄される
/// （[markdownPreviewProvider] で `isAutoDispose: true` を指定）。
/// [load] は画面側（初回 ref.watch 確立直後）から呼ばれる前提（H-3）。
/// Provider 内で自己起動しない。
class MarkdownPreviewNotifier extends Notifier<MarkdownPreviewState> {
  /// 並走対策用バージョン番号（古いリクエストの結果を破棄する）
  int _readVersion = 0;

  /// SSH 接続状態監視
  StreamSubscription<SshConnectionState>? _connectionSub;

  @override
  MarkdownPreviewState build() {
    ref.onDispose(() {
      _connectionSub?.cancel();
    });
    return const MarkdownPreviewState();
  }

  /// Markdown ファイルを読み込む
  ///
  /// フロー（§L3 図1）: 遷移前サイズチェック（[FileEntry.size]・>20MB は
  /// 読み取りせず拒否）→ openSftp → [SftpBrowserService.readFileAsBytes]
  /// （[maxPreviewBytes] 上限）→ バイナリ検知（バイナリは decode しない）→
  /// テキストのみ `utf8.decode(allowMalformed: true)`。
  /// 失敗は throw せず state.error に反映する。
  Future<void> load({
    required String connectionId,
    required FileEntry entry,
  }) async {
    final version = ++_readVersion;
    state = MarkdownPreviewState(path: entry.fullPath, isLoading: true);

    // 遷移前サイズチェック（ブラウザ一覧の報告値・目安・合意#1）。
    // 超過時は SFTP に触れない（H-3）。
    final entrySize = entry.size;
    if (entrySize != null && entrySize > maxPreviewBytes) {
      state = MarkdownPreviewState(
        path: entry.fullPath,
        isTooLarge: true,
        size: _toMb(entrySize),
      );
      return;
    }

    try {
      final sshClient = _getSshClient();
      _startConnectionMonitoring(sshClient);
      final sftp = await sshClient.openSftp();

      final result = await SftpBrowserService.readFileAsBytes(
        sftp,
        entry.fullPath,
        maxBytes: maxPreviewBytes,
      );

      // 並走対策: 古いリクエストの結果は破棄
      if (version != _readVersion) return;

      if (SftpBrowserService.isLikelyBinary(result.bytes)) {
        // バイナリ判定: Markdown として読み込まず表示（合意#1）
        state = MarkdownPreviewState(
          path: entry.fullPath,
          isBinary: true,
          isTruncated: result.isTruncated,
          size: _toMbOrNull(entrySize),
        );
        return;
      }

      state = MarkdownPreviewState(
        path: entry.fullPath,
        content: utf8.decode(result.bytes, allowMalformed: true),
        isTruncated: result.isTruncated,
        size: _toMbOrNull(entrySize),
      );
    } on PreviewTooLargeException catch (e) {
      if (version != _readVersion) return;
      // stat 超過（読取前・合意#1）: 拒否＋警告
      state = MarkdownPreviewState(
        path: entry.fullPath,
        isTooLarge: true,
        size: e.size == null ? null : _toMb(e.size!),
      );
    } catch (e) {
      if (version != _readVersion) return;
      state = MarkdownPreviewState(
        path: entry.fullPath,
        error: lookupL10n().mdLoadFailed('$e'),
      );
    }
  }

  // --- Private methods ---

  SshClient _getSshClient() {
    final client = ref.read(sshProvider.notifier).client;
    if (client == null || !client.isConnected) {
      throw StateError(lookupL10n().termSshNotAvailable);
    }
    return client;
  }

  void _startConnectionMonitoring(SshClient client) {
    _connectionSub?.cancel();
    _connectionSub = client.connectionStateStream.listen((connState) {
      if (connState == SshConnectionState.disconnected ||
          connState == SshConnectionState.error) {
        state = state.copyWith(error: lookupL10n().mdSshLost, isLoading: false);
      }
    });
  }

  /// バイト数を MB に変換（切り上げ・実サイズ表示・LOW-1 対応）。
  int _toMb(int bytes) => (bytes / (1024 * 1024)).ceil();

  int? _toMbOrNull(int? bytes) => bytes == null ? null : _toMb(bytes);
}

/// Markdown プレビュー Provider
///
/// riverpod 3 では autoDispose は Notifier に統合されており、
/// `isAutoDispose: true` で画面破棄時の自動破棄（onDispose 実行）を実現する。
final markdownPreviewProvider =
    NotifierProvider<MarkdownPreviewNotifier, MarkdownPreviewState>(
      MarkdownPreviewNotifier.new,
      isAutoDispose: true,
    );
