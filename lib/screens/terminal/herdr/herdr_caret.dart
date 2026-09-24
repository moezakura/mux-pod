import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart' show settingsProvider;
import '../../../providers/ssh_provider.dart' show sshProvider;
import '../../../services/backend/domain/multiplexer_backend.dart';
import '../../../services/herdr/caret/herdr_caret_helper_manager.dart';
import '../../../services/herdr/caret/herdr_caret_helper_manifest.dart';
import '../../../services/herdr/caret/herdr_caret_snapshot_reader.dart';
import '../../../services/herdr/herdr_adapter.dart';
import '../../../services/herdr/herdr_models.dart';
import '../../../services/herdr/herdr_pane_frame_reader.dart';
import '../../../services/herdr/herdr_snapshot_cache.dart';
import '../../../services/ssh/ssh_client.dart';

/// 合成ファクトリが required とする外部依存（root が提供）。
///
/// caret / frame reader の生成に必要な herdr state（cache / adapter / reader /
/// status）と、画面側の反映先（frameReader・view caret）への接続を抽象化する。
abstract interface class HerdrCaretHost {
  WidgetRef get ref;

  bool get isMounted;

  bool get isDisposed;

  MultiplexerBackendKind get backendKind;

  HerdrAdapter? get frameAdapter;

  HerdrSnapshotCache? get snapshotCache;

  /// テスト注入用 reader（`TerminalScreen.herdrCaretReader`）。
  HerdrCaretSnapshotReader? get injectedReader;

  HerdrCaretSnapshotReader? get caretReader;

  set caretReader(HerdrCaretSnapshotReader? value);

  HerdrStatus? get caretStatus;

  set caretStatus(HerdrStatus? value);

  /// 構築した frame reader をポーリングループへ反映する（session 側）。
  void setFrameReader(HerdrPaneFrameReader reader);

  /// OFF 遷移時・切替時に view の caret をクリアする（session 側）。
  void clearViewCaret();
}

/// caret reader / frame reader / status / executablePath の合成ファクトリ。
class HerdrCaretComposer {
  HerdrCaretComposer(this._host);

  final HerdrCaretHost _host;

  /// 注入 reader（テスト用）を設定ゲート付きで解決する。
  ///
  /// 設定 OFF / カーソル表示 OFF のときは null（呼び出し・副作用なし）。
  HerdrCaretSnapshotReader? resolveInjected() {
    final settings = _host.ref.read(settingsProvider);
    if (!settings.experimentalHerdrCaretPositionEnabled ||
        !settings.showTerminalCursor) {
      return null;
    }
    return _host.injectedReader;
  }

  /// 現在の caret reader を合成した herdr frame reader を構築する。
  ///
  /// caret reader 差し替え（production 構築完了・設定変化・再接続）のたびに
  /// 呼び、ポーリングループが使う frame reader へ反映する。
  HerdrPaneFrameReader buildFrameReader() {
    final adapter = _host.frameAdapter;
    final cache = _host.snapshotCache;
    assert(adapter != null && cache != null, 'herdr frame reader 構築時は必須');
    return HerdrPaneFrameReader(
      adapter!,
      HerdrPaneLayoutResolver(cache!),
      caretReader: _host.caretReader,
    );
  }

  /// caret reader の enabled ゲート（設定 ON && カーソル表示 ON）。
  bool isEnabled() =>
      !_host.isDisposed &&
      _host.ref.read(settingsProvider).experimentalHerdrCaretPositionEnabled &&
      _host.ref.read(settingsProvider).showTerminalCursor;

  /// 現在の herdr server status（protocol / socket）。未取得（null）は既定値。
  HerdrStatus readStatus() => _host.caretStatus ?? const HerdrStatus();

  /// caret 構成まわりの状態分類ログ（理由文字列のみ・機密なし）。
  void logCaretState(String state, String reason) {
    if (kDebugMode) {
      debugPrint('[herdr-caret] $state: $reason');
    }
  }

  /// `herdr status --json` を取得して memoize する。失敗は caret 無効のまま継続。
  Future<void> refreshStatus(SshClient sshClient) async {
    try {
      final status = await HerdrAdapter(sshClient).status();
      if (_host.isDisposed) return;
      _host.caretStatus = status;
    } catch (_) {
      logCaretState('unsupported', 'status fetch failed');
    }
  }

  /// production の herdr caret reader を非同期で構築する。
  ///
  /// - 設定 OFF / カーソル表示 OFF の間は何もしない（wire 呼び出し 0 回）。
  /// - manifest 読込失敗等は caret 無しで続行。await 中に再接続（cache 差し替え）
  ///   が起きたら構築結果を破棄する。
  Future<void> setupProduction(SshClient sshClient) async {
    if (_host.injectedReader != null) return;
    final cache = _host.snapshotCache;
    if (cache == null || _host.isDisposed) return;

    final settings = _host.ref.read(settingsProvider);
    if (!settings.experimentalHerdrCaretPositionEnabled ||
        !settings.showTerminalCursor) {
      return;
    }

    HerdrCaretHelperManifest? manifest;
    try {
      manifest = await HerdrCaretHelperManifest.load();
    } catch (_) {
      logCaretState('unsupported', 'manifest load failed');
      return;
    }
    if (_host.isDisposed) return;
    if (!identical(_host.snapshotCache, cache)) return;

    try {
      final manager = HerdrCaretHelperManager(
        ssh: sshClient,
        manifest: manifest,
      );
      final reader = HerdrCaretHelperSnapshotReader(
        runner: manager,
        statusProvider: readStatus,
        cacheProvider: () => _host.snapshotCache!,
        enabled: isEnabled,
      );
      if (_host.isDisposed || !identical(_host.snapshotCache, cache)) return;
      _host.caretReader = reader;
      _host.setFrameReader(buildFrameReader());
      unawaited(refreshStatus(sshClient));
    } catch (_) {
      _host.caretReader = null;
    }
  }

  /// 設定・カーソル表示の変化で caret reader を再構成する。
  ///
  /// - OFF への遷移: 保持 caret を破棄し、reader を除去する。
  /// - ON への遷移: 注入 reader があればそれを差し込み、無ければ production
  ///   構築を再開する。
  void reconfigure() {
    if (!_host.isMounted || _host.isDisposed) return;
    if (_host.backendKind != MultiplexerBackendKind.herdr) return;
    final sshClient = _host.ref.read(sshProvider.notifier).client;
    final settings = _host.ref.read(settingsProvider);
    final enabled =
        settings.experimentalHerdrCaretPositionEnabled &&
        settings.showTerminalCursor;

    if (!enabled) {
      if (_host.caretReader != null) {
        _host.caretReader = null;
        _host.clearViewCaret();
        if (_host.frameAdapter != null && _host.snapshotCache != null) {
          _host.setFrameReader(buildFrameReader());
        }
      }
      return;
    }

    if (sshClient == null) return;
    if (_host.injectedReader != null) {
      _host.caretReader = _host.injectedReader;
      _host.setFrameReader(buildFrameReader());
      return;
    }
    unawaited(setupProduction(sshClient));
  }

  /// hidden herdr TUI の起動コマンド用 executablePath を POSIX shell quote する。
  ///
  /// 接続設定（[SshClient.userExecutablePath]）が無ければ `herdr`（PATH 依存）。
  /// SSH exec はリモートシェル経由のため、スペースやシングルクォートを含む
  /// パスを安全に渡す。
  String executablePath(SshClient sshClient) {
    final raw = sshClient.userExecutablePath?.trim();
    final path = (raw == null || raw.isEmpty) ? 'herdr' : raw;
    return "'${path.replaceAll("'", r"'\''")}'";
  }
}

/// [HerdrCaretHost] のコールバック実装（controller が組み立てる・cycle 回避）。
class HerdrCaretHostImpl implements HerdrCaretHost {
  HerdrCaretHostImpl({
    required this.ref,
    required bool Function() isMounted,
    required bool Function() isDisposed,
    required MultiplexerBackendKind Function() backendKind,
    required HerdrAdapter? Function() frameAdapter,
    required HerdrSnapshotCache? Function() snapshotCache,
    required HerdrCaretSnapshotReader? Function() injectedReader,
    required HerdrCaretSnapshotReader? Function() caretReader,
    required void Function(HerdrCaretSnapshotReader? value) setCaretReader,
    required HerdrStatus? Function() caretStatus,
    required void Function(HerdrStatus? value) setCaretStatus,
    required void Function(HerdrPaneFrameReader reader) onFrameReader,
    required VoidCallback onClearViewCaret,
  }) : _isMounted = isMounted,
       _isDisposed = isDisposed,
       _backendKind = backendKind,
       _frameAdapter = frameAdapter,
       _snapshotCache = snapshotCache,
       _injectedReader = injectedReader,
       _caretReader = caretReader,
       _setCaretReader = setCaretReader,
       _caretStatus = caretStatus,
       _setCaretStatus = setCaretStatus,
       _onFrameReader = onFrameReader,
       _onClearViewCaret = onClearViewCaret;

  @override
  final WidgetRef ref;

  final bool Function() _isMounted;
  final bool Function() _isDisposed;
  final MultiplexerBackendKind Function() _backendKind;
  final HerdrAdapter? Function() _frameAdapter;
  final HerdrSnapshotCache? Function() _snapshotCache;
  final HerdrCaretSnapshotReader? Function() _injectedReader;
  final HerdrCaretSnapshotReader? Function() _caretReader;
  final void Function(HerdrCaretSnapshotReader? value) _setCaretReader;
  final HerdrStatus? Function() _caretStatus;
  final void Function(HerdrStatus? value) _setCaretStatus;
  final void Function(HerdrPaneFrameReader reader) _onFrameReader;
  final VoidCallback _onClearViewCaret;

  @override
  bool get isMounted => _isMounted();

  @override
  bool get isDisposed => _isDisposed();

  @override
  MultiplexerBackendKind get backendKind => _backendKind();

  @override
  HerdrAdapter? get frameAdapter => _frameAdapter();

  @override
  HerdrSnapshotCache? get snapshotCache => _snapshotCache();

  @override
  HerdrCaretSnapshotReader? get injectedReader => _injectedReader();

  @override
  HerdrCaretSnapshotReader? get caretReader => _caretReader();

  @override
  set caretReader(HerdrCaretSnapshotReader? value) => _setCaretReader(value);

  @override
  HerdrStatus? get caretStatus => _caretStatus();

  @override
  set caretStatus(HerdrStatus? value) => _setCaretStatus(value);

  @override
  void setFrameReader(HerdrPaneFrameReader reader) => _onFrameReader(reader);

  @override
  void clearViewCaret() => _onClearViewCaret();
}
