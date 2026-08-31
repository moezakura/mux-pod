// inventory: HERDR-FRAME-000
/// herdr のペイン表示フレーム合成（content + layout）。
///
/// [PaneFrameReader] を実装し、`HerdrAdapter.paneRead`（content）と
/// [HerdrPaneLayoutResolver]（layout geometry）を合成して [PaneFrame] を
/// 返す。表示層の backend 分岐（`_backendKind == herdr` の直書き・診断専用
/// `cachedSnapshot` の表示利用）を除去する根本対応（Codex レビュー・バグ1）。
library;

import 'dart:math' as math;

import '../backend/domain/pane_content_reader.dart';
import '../backend/domain/pane_frame_reader.dart';
import '../backend/domain/pane_read.dart';
import 'caret/herdr_caret_snapshot_reader.dart';
import 'herdr_adapter.dart';
import 'herdr_snapshot_cache.dart';

/// geometry 未解決時の既定 frame サイズ（spec.md:75・従来仕様の 80x24）。
const int _kDefaultCaretCols = 80;

/// caret 要求の最小列数（行末カーソルの cursor:null 化を避ける。上の
/// コメント参照）。
const int _kMinCaretCols = 80;
const int _kDefaultCaretRows = 24;

/// herdr のペイン表示フレーム合成（content + layout + caret）。
///
/// [PaneFrameReader] を実装し、`HerdrAdapter.paneRead`（content）と
/// [HerdrPaneLayoutResolver]（layout geometry）を合成して [PaneFrame] を
/// 返す。表示層の backend 分岐（`_backendKind == herdr` の直書き・診断専用
/// `cachedSnapshot` の表示利用）を除去する根本対応（Codex レビュー・バグ1）。
///
/// Phase 4: [caretReader] が非 null なら [PaneCaret] を合成する。caret 取得
/// の失敗（null・例外）は content / geometry に影響させず、caret だけ諦める
/// （best-effort。通常の pane 表示・入力を止めない）。

/// herdr のペイン表示フレーム合成。
class HerdrPaneFrameReader implements PaneFrameReader {
  final HerdrAdapter _adapter;
  final PaneLayoutResolver _layoutResolver;
  final HerdrCaretSnapshotReader? _caretReader;

  HerdrPaneFrameReader(
    this._adapter,
    this._layoutResolver, {
    HerdrCaretSnapshotReader? caretReader,
  }) : _caretReader = caretReader;

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

    // Phase 4: カーソル snapshot（best-effort）。取得失敗・非対応環境・設定
    // OFF（reader 未注入）は null のまま。geometry 失敗と caret 失敗は独立
    // （計画 Phase 4-6）。
    //
    // cols は「80 を下限」で要求する（実測: autoFit で縮小された pane rect
    // （例 27x23）のままだと、herdr は 27 列フレームにレンダリングし、
    // プロンプト行末のカーソルがフレーム幅と同値（x == frameWidth）となり
    // cursor:null（非表示観測）として返る。ターミナル実幅は通常 80 列以上
    // のため、80 未満の geometry は 80 へ引き上げて要求する。rows は
    // geometry の値、無い場合は既定 24 を使う（フレームは末尾 rows 行になる）。
    PaneCaret? caret;
    final caretReader = _caretReader;
    if (caretReader != null) {
      final cols = math.max(geometry?.width ?? _kDefaultCaretCols, _kMinCaretCols);
      final rows = geometry?.height ?? _kDefaultCaretRows;
      try {
        final snapshot = await caretReader.read(
          paneId: request.paneId,
          cols: cols,
          rows: rows,
        );
        // `cursor: null` 観測（visible == false・位置不明）も PaneCaret へ
        // 正しく変換する（x/y=null・visible=false）。
        if (snapshot != null) {
          caret = PaneCaret(
            x: snapshot.x,
            y: snapshot.y,
            visible: snapshot.visible,
            shape: snapshot.shape,
            frameWidth: snapshot.frameWidth,
            frameHeight: snapshot.frameHeight,
          );
        }
      } catch (_) {
        // caret だけ諦める（content / geometry には影響させない）。
        caret = null;
      }
    }

    return PaneFrame(
      content: content.rawText,
      geometry: geometry,
      hasAnsi: content.hasAnsi,
      caret: caret,
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
