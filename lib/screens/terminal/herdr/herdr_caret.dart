import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../../providers/settings_provider.dart' show settingsProvider;
import '../../../providers/ssh_provider.dart' show sshProvider;
import '../../../services/backend/domain/multiplexer_backend.dart';
import '../../../services/herdr/caret/herdr_caret_helper_installer.dart';
import '../../../services/herdr/caret/herdr_caret_helper_manager.dart';
import '../../../services/herdr/caret/herdr_caret_helper_manifest.dart';
import '../../../services/herdr/caret/herdr_caret_snapshot_reader.dart';
import '../../../services/herdr/caret/herdr_caret_ssh.dart';
import '../../../services/herdr/herdr_adapter.dart';
import '../../../services/herdr/herdr_models.dart';
import '../../../services/herdr/herdr_pane_frame_reader.dart';
import '../../../services/herdr/herdr_snapshot_cache.dart';
import '../../../services/herdr/hyperlink/herdr_hyperlink_helper_manager.dart';
import '../../../services/herdr/hyperlink/herdr_hyperlink_reader.dart';
import '../../../services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart';
import '../../../services/herdr/hyperlink/herdr_scrollback_link_reader.dart';
import '../../../services/ssh/ssh_client.dart';

import 'herdr_caret_host.dart';

export 'herdr_caret_host.dart';

/// caret reader / frame reader / status / executablePath の合成ファクトリ。
class HerdrCaretComposer {
  HerdrCaretComposer(this._host);

  final HerdrCaretHost _host;

  /// 直近の viewport 確定引数（herdr OSC 8 ハイパーリンク実験機能）。
  /// [setupScrollbackLinkReader] の manifest 読込中（await 中）
  /// に届いた [notifyViewportSettled] は、reader が未代入のため
  /// `_host.scrollbackLinkReader?.` で捨てられてしまう。ここに直近の
  /// 引数を保持し、reader 代入完了時に [onScrollbackLinkReaderAssigned]
  /// から 1 回だけ送り直す。
  ({
    ({Object? identity, int generation}) snapshotIdentity,
    int lineCount,
    ({int top, int bottom}) visibleRange,
  })?
  _pendingViewportSettle;

  /// [ensureStatus] の single-flight 用 in-flight future。
  Future<HerdrStatus>? _statusInFlight;

  /// [ensureInstaller] の memo と single-flight 用 in-flight future
  /// （caret と 2 つのリンク読取で 1 インスタンスを共有し、配置確認の SSH
  /// 実行（uname・sha256sum 等）を機能ごとに重複させない）。
  ///
  /// memo は接続単位。`_installerSshClient` /
  /// `_installerInFlightSshClient` で紐づく [SshClient] を記録し、
  /// [ensureInstaller] 呼び出し時の client と `identical` でなければ
  /// 作り直す（再接続で新しい [SshClient] に差し替わっても memo が古い
  /// client を握ったままだと、helper 配置確認が切断済み client 上で行われ
  /// 失敗し続けるため。caret は従来から再接続のたびに installer を作り直す）。
  HerdrCaretInstaller? _installer;
  SshClient? _installerSshClient;
  Future<HerdrCaretInstaller>? _installerInFlight;
  SshClient? _installerInFlightSshClient;

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

  /// 注入 hyperlink reader（テスト用）を設定ゲート付きで解決する（herdr OSC
  /// 8 ハイパーリンク実験機能）。
  ///
  /// 設定 OFF のときは null（呼び出し・副作用なし）。caret と異なり
  /// カーソル表示設定は関係ない（[isHyperlinkEnabled] と同じゲート）。
  HerdrHyperlinkReader? resolveInjectedHyperlink() {
    if (!_host.ref.read(settingsProvider).experimentalHerdrHyperlinksEnabled) {
      return null;
    }
    return _host.injectedHyperlinkReader;
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
      hyperlinkReader: _host.hyperlinkReader,
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
  ///
  /// 失敗時は memo しない（[_host.caretStatus] は未設定のまま）。既存の
  /// best-effort 契約どおり、次回呼び出しで再取得を試みる
  /// （この catch ブロックは失敗を memo しない）。
  Future<void> refreshStatus(SshClient sshClient) async {
    try {
      final status = await HerdrAdapter(sshClient).status();
      if (_host.isDisposed) return;
      // 取得中に再接続（client 差し替え）が起きていたら、古い client の
      // status を書き戻さない。
      if (!identical(_host.ref.read(sshProvider.notifier).client, sshClient)) {
        return;
      }
      _host.caretStatus = status;
    } catch (_) {
      logCaretState('unsupported', 'status fetch failed');
    }
  }

  /// Herdr status を single-flight で確実に取得する（herdr OSC 8
  /// ハイパーリンク実験機能）。
  ///
  /// caret・hyperlinks・scrollback-links のどの機能から呼ばれても共有される
  /// （未取得ならその場で1回取得する single-flight）。既に取得済みなら即時返し、取得中なら合流する。
  /// 取得失敗時は [readStatus] の既定値（`const HerdrStatus()`）を返す
  /// （caret の既存 `refreshStatus` と同じ best-effort 契約。throw しない）。
  Future<HerdrStatus> ensureStatus(SshClient sshClient) {
    final current = _host.caretStatus;
    if (current != null) return Future.value(current);
    final inFlight = _statusInFlight;
    if (inFlight != null) return inFlight;
    final future = _fetchStatus(sshClient);
    _statusInFlight = future;
    future.whenComplete(() {
      if (identical(_statusInFlight, future)) _statusInFlight = null;
    });
    return future;
  }

  Future<HerdrStatus> _fetchStatus(SshClient sshClient) async {
    await refreshStatus(sshClient);
    return readStatus();
  }

  /// helper installer を single-flight で確実に取得する
  /// （caret と 2 つのリンク読取で 1 インスタンスを共有し、配置確認の SSH
  /// 実行（uname・sha256sum 等）を機能ごとに重複させない）。
  ///
  /// 既に構築済み（同一 [SshClient]）なら即時返し、構築中（同一 client）なら
  /// 合流する。client が変わっていれば（再接続）作り直す。失敗時は memo
  /// しない（次の要求で再試行できる。[HerdrCaretInstaller] 自体のコンスト
  /// ラクタは SSH を呼ばないため、ここで失敗するのは通常起きない）。
  Future<HerdrCaretInstaller> ensureInstaller(
    SshClient sshClient,
    HerdrCaretHelperManifest manifest,
  ) {
    final current = _installer;
    if (current != null && identical(_installerSshClient, sshClient)) {
      return Future.value(current);
    }
    final inFlight = _installerInFlight;
    if (inFlight != null && identical(_installerInFlightSshClient, sshClient)) {
      return inFlight;
    }
    // `Future(() {...})`（Timer.run ベース・マクロタスク）は使わない。
    // testWidgets の FakeAsync 環境ではマクロタスクは明示的に時間を進め
    // ないと発火せず await がハングする（実測: 300 秒超でも完了しない）。
    // async 関数（マイクロタスクベース）にすることで ensureStatus/
    // _fetchStatus と同様に自動で完了する。
    final future = _buildInstaller(sshClient, manifest);
    _installerInFlight = future;
    _installerInFlightSshClient = sshClient;
    future.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_installerInFlight, future)) {
          _installerInFlight = null;
          _installerInFlightSshClient = null;
        }
      },
    );
    return future;
  }

  Future<HerdrCaretInstaller> _buildInstaller(
    SshClient sshClient,
    HerdrCaretHelperManifest manifest,
  ) async {
    final installer = HerdrCaretInstaller(
      ssh: sshClient,
      manifest: manifest,
      sshRunner: HerdrCaretSshRunner(sshClient),
    );
    _installer = installer;
    _installerSshClient = sshClient;
    return installer;
  }

  /// hyperlink reader の enabled ゲート（設定 ON のみ。caret のカーソル
  /// 表示設定に相当するものは無い）。
  bool isHyperlinkEnabled() =>
      !_host.isDisposed &&
      _host.ref.read(settingsProvider).experimentalHerdrHyperlinksEnabled;

  /// production の通常表示ハイパーリンク reader を非同期で構築する。
  ///
  /// - 設定 OFF の間は何もしない（wire 呼び出し 0 回）。
  /// - manifest 読込失敗等は hyperlink reader 無しで続行。await 中に再接続
  ///   （cache 差し替え）が起きたら構築結果を破棄する。
  /// - installer は [ensureInstaller] 経由で caret と共有する。
  Future<void> setupHyperlinkProduction(SshClient sshClient) async {
    if (_host.injectedHyperlinkReader != null) return;
    final cache = _host.snapshotCache;
    if (cache == null || _host.isDisposed) return;

    if (!_host.ref.read(settingsProvider).experimentalHerdrHyperlinksEnabled) {
      return;
    }

    HerdrCaretHelperManifest? manifest;
    try {
      manifest = await HerdrCaretHelperManifest.load();
    } catch (_) {
      logCaretState('unsupported', 'hyperlink manifest load failed');
      return;
    }
    if (_host.isDisposed) return;
    if (!identical(_host.snapshotCache, cache)) return;

    try {
      final installer = await ensureInstaller(sshClient, manifest);
      if (_host.isDisposed || !identical(_host.snapshotCache, cache)) return;
      final manager = HerdrHyperlinkHelperManager(
        ssh: sshClient,
        manifest: manifest,
        installer: installer,
      );
      final reader = HerdrHyperlinkHelperReader(
        runner: manager,
        statusProvider: readStatus,
        cacheProvider: () => _host.snapshotCache,
        enabled: isHyperlinkEnabled,
      );
      if (_host.isDisposed || !identical(_host.snapshotCache, cache)) return;
      _host.hyperlinkReader = reader;
      _host.setFrameReader(buildFrameReader());
    } catch (_) {
      // この await 中に新しい engine 再構築（cache 差し替え）が
      // 起きていれば、失敗した古い呼び出しが新しい reader を null 化して
      // しまわないようにする（到達経路は未確認・防御的）。
      if (identical(_host.snapshotCache, cache)) {
        _host.hyperlinkReader = null;
      }
    }
  }

  /// 注入 scrollback-links helper runner（テスト用）を設定ゲート付きで
  /// 解決する。[resolveInjectedHyperlink] と同じゲート。
  ///
  /// caret/hyperlinks と異なり、注入されるのは SSH 境界（
  /// [HerdrScrollbackLinkHelperRunner]）だけで、reader 本体
  /// （[HerdrScrollbackLinkReader]）は本番と同じものを [buildScrollbackLinkReader]
  /// で構築する（テストでも root 配線・世代ガード・debounce 等の本番ロジックを
  /// そのまま検証できるようにするための意図的な違い）。
  HerdrScrollbackLinkHelperRunner? resolveInjectedScrollbackLinkRunner() {
    if (!_host.ref.read(settingsProvider).experimentalHerdrHyperlinksEnabled) {
      return null;
    }
    return _host.injectedScrollbackLinkHelperRunner;
  }

  /// スクロールモードの現在対象 pane（cols/rows の出所を1箇所にまとめる）。
  /// [HerdrScrollbackLinkReader.currentPane] へそのまま
  /// 渡す。
  ///
  /// [HerdrPaneLayoutResolver.resolve] と同じ rect/zoomed/area 解決だが、
  /// [HerdrScrollbackLinkReader] の `currentPane` は sync 契約のため、TTL
  /// 管理された [HerdrSnapshotCache.get] ではなく直近取得済みの
  /// [HerdrSnapshotCache.cachedSnapshot]（診断用の sync スナップショット）
  /// を使う。rows の出所はここ1箇所にまとめてある
  /// （変更が必要になったらここだけ直す）。
  HerdrScrollbackLinkCurrentPane? currentScrollbackLinkPane() {
    final paneId = _host.currentPaneId;
    if (paneId == null) return null;
    final snapshot = _host.snapshotCache?.cachedSnapshot;
    if (snapshot == null) return null;
    for (final layout in snapshot.layouts) {
      final rect = layout.rectFor(paneId);
      if (rect != null) {
        final size = layout.zoomed ? layout.area : rect;
        // v0.7.5 は client が一度も attach していない間、rect/area が
        // ともに 0 になる。0 サイズで helper を
        // 呼ぶと cols/rows=0 の実行になるため、pane なしとして扱う。
        if (size.width == 0 || size.height == 0) return null;
        // viewportRows（scroll.viewport_rows）は生値のまま渡す
        // （0 以下・欠損の扱いは _computeOffsets 側のフォールバック判定に
        // 委ねる）。
        return (
          paneId: paneId,
          cols: size.width,
          rows: size.height,
          viewportRows: snapshot.paneFor(paneId)?.viewportRows,
        );
      }
    }
    return null;
  }

  /// [HerdrScrollbackLinkReader] を [runner] と host のコールバックから
  /// 構築する。注入・production のどちらからも呼ばれる（runner
  /// だけが違う）。
  HerdrScrollbackLinkReader buildScrollbackLinkReader(
    HerdrScrollbackLinkHelperRunner runner,
  ) {
    return HerdrScrollbackLinkReader(
      runner: runner,
      cache: _host.scrollbackLinkCache!,
      status: readStatus,
      currentPane: currentScrollbackLinkPane,
      bodyLinesFor: _host.bodyLinesFor,
      onUpdated: _host.notifyScrollbackLinksUpdated,
      isActive: _host.isActive,
      currentSnapshotIdentity: _host.currentSnapshotIdentity,
      clock: _host.scrollbackLinkClock,
    );
  }

  /// root（[TerminalScreenAdapter]）の viewport 確定配線から呼ぶ
  /// （herdr OSC 8 ハイパーリンク実験機能）。
  ///
  /// reader が代入済みならそのまま転送する（従来どおり）。reader が未代入
  /// （[setupScrollbackLinkReader] の manifest 読込中）でも捨てずに直近の
  /// 引数を保持し、[onScrollbackLinkReaderAssigned] から 1 回だけ送り直す。
  void notifyViewportSettled(
    ({Object? identity, int generation}) snapshotIdentity,
    int lineCount,
    ({int top, int bottom}) visibleRange,
  ) {
    _pendingViewportSettle = (
      snapshotIdentity: snapshotIdentity,
      lineCount: lineCount,
      visibleRange: visibleRange,
    );
    _host.scrollbackLinkReader?.onViewportSettled(
      snapshotIdentity,
      lineCount,
      visibleRange,
    );
  }

  /// [_host.scrollbackLinkReader] へ代入した直後に呼ぶ（herdr OSC 8
  /// ハイパーリンク実験機能。[setupScrollbackLinkReader] の成功
  /// パスと、注入 runner の同期代入パスの両方から呼ぶ）。
  ///
  /// [notifyViewportSettled] が reader 未代入中に保持した直近の引数があり、
  /// かつ現在も select モードのままなら（select を抜けた・エンジン再構築
  /// で resetTerminalMode が先に走った、のいずれでもない）、1 回だけ
  /// reader へ送り直す。
  void onScrollbackLinkReaderAssigned() {
    final pending = _pendingViewportSettle;
    if (pending == null) return;
    final reader = _host.scrollbackLinkReader;
    if (reader == null || !_host.isSelectModeActive()) return;
    _pendingViewportSettle = null;
    reader.onViewportSettled(
      pending.snapshotIdentity,
      pending.lineCount,
      pending.visibleRange,
    );
  }

  /// エンジン再構築時に、古い viewport 確定の引数を新しい reader へ送らない
  /// ようにする（herdr OSC 8 ハイパーリンク実験機能）。
  /// `HerdrController._rebuildHerdrEngine` の scrollbackLinkReader
  /// dispose/null 化と同じ箇所で呼ぶ。
  void clearPendingViewportSettle() {
    _pendingViewportSettle = null;
  }

  /// production のスクロールモードのリンク読取を非同期で構築する。
  ///
  /// - 設定 OFF の間は何もしない（wire 呼び出し 0 回）。
  /// - manifest 読込失敗等は reader 無しで続行。await 中に再接続（cache
  ///   差し替え）が起きたら構築結果を破棄する。
  /// - installer は [ensureInstaller] 経由で caret/hyperlinks と共有する。
  Future<void> setupScrollbackLinkReader(SshClient sshClient) async {
    if (_host.injectedScrollbackLinkHelperRunner != null) return;
    final cache = _host.snapshotCache;
    if (cache == null || _host.isDisposed) return;

    if (!_host.ref.read(settingsProvider).experimentalHerdrHyperlinksEnabled) {
      return;
    }

    HerdrCaretHelperManifest? manifest;
    try {
      manifest = await HerdrCaretHelperManifest.load();
    } catch (_) {
      logCaretState('unsupported', 'scrollback link manifest load failed');
      return;
    }
    if (_host.isDisposed) return;
    if (!identical(_host.snapshotCache, cache)) return;

    try {
      final installer = await ensureInstaller(sshClient, manifest);
      if (_host.isDisposed || !identical(_host.snapshotCache, cache)) return;
      final manager = HerdrScrollbackLinkHelperManager(
        ssh: sshClient,
        manifest: manifest,
        installer: installer,
      );
      if (_host.isDisposed || !identical(_host.snapshotCache, cache)) return;
      _host.scrollbackLinkReader = buildScrollbackLinkReader(manager);
      // 代入完了前に届いていた viewport 確定を 1 回だけ送り直す。
      onScrollbackLinkReaderAssigned();
    } catch (_) {
      // この await 中に新しい engine 再構築（cache 差し替え）が
      // 起きていれば、失敗した古い呼び出しが新しい reader を null 化して
      // しまわないようにする（到達経路は未確認・防御的）。
      if (identical(_host.snapshotCache, cache)) {
        _host.scrollbackLinkReader = null;
      }
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
      final installer = await ensureInstaller(sshClient, manifest);
      if (_host.isDisposed || !identical(_host.snapshotCache, cache)) return;
      final manager = HerdrCaretHelperManager(
        ssh: sshClient,
        manifest: manifest,
        installer: installer,
      );
      final reader = HerdrCaretHelperSnapshotReader(
        runner: manager,
        statusProvider: readStatus,
        cacheProvider: () => _host.snapshotCache,
        enabled: isEnabled,
      );
      if (_host.isDisposed || !identical(_host.snapshotCache, cache)) return;
      _host.caretReader = reader;
      _host.setFrameReader(buildFrameReader());
      // ensureStatus 経由にする: hyperlinks
      // 側も同じ single-flight を通るため、両方 ON でも `herdr status` の
      // SSH 実行は 1 回にまとまる（`refreshStatus` を直接呼ぶと合流しない）。
      unawaited(ensureStatus(sshClient));
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
