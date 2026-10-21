/// herdr OSC 8 ハイパーリンク（通常表示のリンクとスクロールモードのリンク）
/// 読取の準備を担う協調クラス（[HerdrCaretComposer] が生成・委譲する）。
///
/// helper の配置確認（[ensureInstaller]）・herdr status・フレーム reader の
/// 再構築は、[HerdrCaretComposer] が持つ共有状態を、そのメソッドを受け取った
/// コールバック経由で呼ぶ。このクラス自身は配置確認の状態を持たない。
library;

import '../../../providers/settings_provider.dart' show settingsProvider;
import '../../../services/herdr/caret/herdr_caret_helper_installer.dart';
import '../../../services/herdr/caret/herdr_caret_helper_manifest.dart';
import '../../../services/herdr/herdr_models.dart';
import '../../../services/herdr/herdr_pane_frame_reader.dart';
import '../../../services/herdr/hyperlink/herdr_hyperlink_helper_manager.dart';
import '../../../services/herdr/hyperlink/herdr_hyperlink_reader.dart';
import '../../../services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart';
import '../../../services/herdr/hyperlink/herdr_scrollback_link_reader.dart';
import '../../../services/ssh/ssh_client.dart';
import 'herdr_caret_host.dart';

/// 通常表示のハイパーリンク reader と、スクロールモードのリンク reader の
/// 設定ゲート・構築・viewport 確定の保持を担う。
class HerdrLinkComposer {
  HerdrLinkComposer({
    required HerdrCaretHost host,
    required this.ensureInstaller,
    required this.readStatus,
    required this.logCaretState,
    required this.buildFrameReader,
  }) : _host = host;

  final HerdrCaretHost _host;

  /// [HerdrCaretComposer.ensureInstaller] と同じ（配置確認の共有はそちらが持つ）。
  final Future<HerdrCaretInstaller> Function(
    SshClient sshClient,
    HerdrCaretHelperManifest manifest,
  )
  ensureInstaller;

  /// [HerdrCaretComposer.readStatus] と同じ。
  final HerdrStatus Function() readStatus;

  /// [HerdrCaretComposer.logCaretState] と同じ。
  final void Function(String state, String reason) logCaretState;

  /// [HerdrCaretComposer.buildFrameReader] と同じ。
  final HerdrPaneFrameReader Function() buildFrameReader;

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
}
