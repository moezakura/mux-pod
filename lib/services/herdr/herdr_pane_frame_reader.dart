// inventory: HERDR-FRAME-000
/// herdr のペイン表示フレーム合成（content + layout）。
///
/// [PaneFrameReader] を実装し、`HerdrAdapter.paneRead`（content）と
/// [HerdrPaneLayoutResolver]（layout geometry）を合成して [PaneFrame] を
/// 返す。表示層の backend 分岐（`_backendKind == herdr` の直書き・診断専用
/// `cachedSnapshot` の表示利用）を除去する根本対応（Codex レビュー・バグ1）。
library;

import '../backend/domain/pane_content_reader.dart';
import '../backend/domain/pane_frame_reader.dart';
import '../backend/domain/pane_read.dart';
import 'herdr_adapter.dart';
import 'herdr_snapshot_cache.dart';

/// herdr のペイン表示フレーム合成。
class HerdrPaneFrameReader implements PaneFrameReader {
  final HerdrAdapter _adapter;
  final PaneLayoutResolver _layoutResolver;

  HerdrPaneFrameReader(this._adapter, this._layoutResolver);

  @override
  Future<PaneFrame> read(PaneFrameRequest request) async {
    // content と layout は別時刻の情報。pane ID / epoch / adapter identity を
    // 照合して合成する（display 層ではなくこの合成層で backend 差異を吸収）。
    final content = await _adapter.paneRead(
      request.paneId,
      source: 'recent',
      lines: request.read.maxLines,
      ansi: true,
      viaPersistent: request.purpose == PaneReadPurpose.live,
    );
    // geometry 解決の失敗は表示を止めない（既定 80x24 へフォールバック）。
    PaneGeometry? geometry;
    try {
      geometry = await _layoutResolver.resolve(request.paneId);
    } catch (_) {
      geometry = null;
    }
    return PaneFrame(
      content: content.rawText,
      geometry: geometry,
      hasAnsi: content.hasAnsi,
    );
  }
}

/// snapshot cache（唯一の read chokepoint・A5）から pane の geometry を解決する。
///
/// [HerdrSnapshotCache.get] は TTL / single-flight / epoch 契約を守るため、
/// 診断用 `cachedSnapshot` ではなく [get] を使う。zoom 時は pane rect が
/// 非 zoom 値のまま（herdr_models.dart）のため layout.area（タブ全面）を返す。
class HerdrPaneLayoutResolver implements PaneLayoutResolver {
  final HerdrSnapshotCache _cache;

  HerdrPaneLayoutResolver(this._cache);

  @override
  Future<PaneGeometry?> resolve(String paneId) async {
    final snapshot = await _cache.get();
    for (final layout in snapshot.layouts) {
      final rect = layout.rectFor(paneId);
      if (rect != null) {
        final size = layout.zoomed ? layout.area : rect;
        return PaneGeometry(width: size.width, height: size.height);
      }
    }
    return null;
  }
}
