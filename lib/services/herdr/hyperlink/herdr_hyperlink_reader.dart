// inventory: HERDR-HYPERLINK-READER-000
/// herdr 通常表示のハイパーリンク読み取りサービス（herdr OSC 8 ハイパー
/// リンク実験機能「通常表示のリンク読取」）。
///
/// [HerdrCaretHelperSnapshotReader]（caret 読取）と同型のパターンを踏襲する:
/// - TTL 500ms（既定）: 同一 pane では一定間隔でしか helper を実行しない
/// - timeout 1000ms（既定）
/// - single-flight（pane 単位。同時要求は 1 回の実行にまとめる）
/// - epoch / adapter identity 照合（await 前後で [HerdrSnapshotCache] を
///   比較し、pane 切替・再接続・adapter 差し替えの stale 結果を破棄する）
/// - `statusProvider` は同期関数で SSH を呼ばない（`HerdrCaretComposer.
///   readStatus` を想定注入。status 未確立時は既定値 `HerdrStatus()` を
///   返すため helper は実行されない。status 取得自体の再試行は
///   `HerdrCaretComposer.ensureStatus` の責務であり、本 reader は行わない。
///   status 取得が失敗しても poll ごとの SSH 実行回数は 0 回に留める）
///
/// 取得失敗・非対応環境・stale は例外を投げず null を返す
/// （best-effort。通常の pane 表示・入力を止めない）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../backend/domain/pane_frame_reader.dart' show PaneHyperlinks;
import '../caret/herdr_caret_helper_types.dart';
import '../herdr_models.dart';
import '../herdr_snapshot_cache.dart';
import '../herdr_version.dart';
import 'herdr_hyperlink_helper_manager.dart';

/// 通常表示のハイパーリンク読み取りの抽象。
///
/// [HerdrHyperlinkReader.read] は取得できない環境・失敗時に null を返す。
abstract interface class HerdrHyperlinkReader {
  /// [paneId] のハイパーリンクを取得する（best-effort）。
  ///
  /// - 設定 OFF / 非対応環境 / 失敗 / stale は null。
  /// - 成功時は TTL 内の再呼び出しでキャッシュを返す。
  Future<PaneHyperlinks?> read({
    required String paneId,
    required int cols,
    required int rows,
  });
}

/// [HerdrHyperlinkHelperRunner] を注入した実装。
class HerdrHyperlinkHelperReader implements HerdrHyperlinkReader {
  /// 通常更新の TTL（同じ pane で helper を実行する最小間隔）。
  static const Duration defaultTtl = Duration(milliseconds: 500);

  /// helper 実行のタイムアウト。
  static const Duration defaultTimeout = Duration(milliseconds: 1000);

  final HerdrHyperlinkHelperRunner _runner;
  final HerdrStatus Function() _statusProvider;

  /// 現在の cache。画面破棄後（`snapshotCache = null`）は null を返す。
  final HerdrSnapshotCache? Function() _cacheProvider;
  final bool Function() _enabled;
  final Duration _ttl;
  final Duration _timeout;
  final DateTime Function() _clock;

  PaneHyperlinks? _cached;
  String? _cachedPaneId;
  DateTime? _cachedAt;

  /// pane+epoch 単位の in-flight（single-flight）。
  final Map<String, Future<PaneHyperlinks?>> _inFlight = {};

  HerdrHyperlinkHelperReader({
    required HerdrHyperlinkHelperRunner runner,
    required HerdrStatus Function() statusProvider,
    required HerdrSnapshotCache? Function() cacheProvider,
    required bool Function() enabled,
    Duration ttl = defaultTtl,
    Duration timeout = defaultTimeout,
    DateTime Function()? clock,
  }) : _runner = runner,
       _statusProvider = statusProvider,
       _cacheProvider = cacheProvider,
       _enabled = enabled,
       _ttl = ttl,
       _timeout = timeout,
       _clock = clock ?? DateTime.now;

  /// キャッシュ済み結果（TTL 内のみ有効。無ければ null）。診断用。
  PaneHyperlinks? get cachedHyperlinks => _cached;

  @override
  Future<PaneHyperlinks?> read({
    required String paneId,
    required int cols,
    required int rows,
  }) async {
    // 設定 OFF・不正 frame は実行しない。
    if (!_enabled() || cols < 0 || rows < 0) {
      _logState('disabled', paneId);
      return null;
    }

    final HerdrStatus status;
    try {
      status = _statusProvider();
    } catch (_) {
      _logState('unsupported', paneId);
      return null;
    }
    // status が未確立（既定値）でも SSH は呼ばない
    // （`isHerdrHyperlinkProtocolSupported` が既定値の serverProtocol を
    // 拒否するため、ここで打ち切られる。status 取得自体の再試行は行わない）。
    if (!isHerdrHyperlinkProtocolSupported(status.serverProtocol)) {
      _logState('unsupported', paneId);
      return null;
    }
    final apiSocket = status.socket;
    if (apiSocket == null || apiSocket.trim().isEmpty) {
      _logState('unsupported', paneId);
      return null;
    }

    final now = _clock();

    // TTL 内の同一 pane はキャッシュを返す（進行中 fetch がある場合は
    // 待たずに合流する）。
    final cached = _cached;
    if (cached != null &&
        _cachedPaneId == paneId &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _ttl &&
        !_hasInflight(paneId)) {
      return cached;
    }

    // epoch / adapter identity を実行前に記録する。
    final cacheBefore = _cacheProvider();
    if (cacheBefore == null) {
      // 破棄済み（画面破棄で cache が null 化済み）。実行しない。
      _logState('disposed', paneId);
      return null;
    }
    final epochBefore = cacheBefore.epoch;

    // single-flight（pane + epoch が同一なら合流）。
    final key = '$paneId|$epochBefore';
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    final future = _fetch(
      status: status,
      paneId: paneId,
      cols: cols,
      rows: rows,
      cacheBefore: cacheBefore,
      epochBefore: epochBefore,
    );
    _inFlight[key] = future;
    future.whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    });
    return future;
  }

  bool _hasInflight(String paneId) =>
      _inFlight.keys.any((key) => key.startsWith('$paneId|'));

  Future<PaneHyperlinks?> _fetch({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required int rows,
    required HerdrSnapshotCache cacheBefore,
    required int epochBefore,
  }) async {
    try {
      final result = await _runner.run(
        status: status,
        paneId: paneId,
        cols: cols,
        rows: rows,
        timeout: _timeout,
      );

      // stale 検出: await 中に pane 切替（epoch++）・再接続（adapter
      // 差し替え = cache 再生成）が無いかを照合する。
      final cacheAfter = _cacheProvider();
      if (cacheAfter == null) {
        // await 中に画面が破棄された。結果は破棄（例外にはしない）。
        _logState('disposed', paneId);
        return null;
      }
      if (!identical(cacheAfter, cacheBefore) ||
          cacheAfter.epoch != epochBefore) {
        _logState('stale', paneId); // 結果は破棄
        return null;
      }

      _cached = result;
      _cachedPaneId = paneId;
      _cachedAt = _clock();
      return result;
    } on HerdrCaretHelperException catch (e) {
      // 失敗はキャッシュを更新しない（次の read で再試行される）。
      _logState(e.failure.name, paneId);
      return null;
    } catch (_) {
      _logState('invalid', paneId);
      return null;
    }
  }

  /// 状態分類のみを debug log へ出す（socket path・画面内容は出さない）。
  void _logState(String state, String paneId) {
    if (kDebugMode) {
      debugPrint('[herdr-hyperlink] $state (pane=$paneId)');
    }
  }
}
