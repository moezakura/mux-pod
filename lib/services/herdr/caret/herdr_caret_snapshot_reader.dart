// inventory: HERDR-CARET-READER-000
/// herdr カーソル位置スナップショットの読み取りサービス。
///
/// [HerdrCaretHelperRunner]（配置・実行 manager）を注入し、
/// - TTL 500ms（既定）: 同一 pane では一定間隔でしか helper を実行しない
/// - timeout 1000ms（既定）
/// - single-flight（pane 単位。同時要求は 1 回の実行にまとめる）
/// - epoch / adapter identity 照合（await 前後で [HerdrSnapshotCache] を
///   比較し、pane 切替・再接続・adapter 差し替えの stale 結果を破棄する）
/// を提供する。
///
/// 取得失敗・非対応環境・stale は例外を投げず null を返す
/// （best-effort。通常の pane 表示・入力を止めない）。
///
/// 本文（PaneFrame）との合成・設定 OFF ゲートは Phase 4 の呼び出し側が
/// 担うが、[enabled] を注入し、OFF 時に helper 実行が一切発生しないことを
/// reader 内でも構造的に保証する（呼び忘れ防止）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../herdr_models.dart';
import '../herdr_snapshot_cache.dart';
import 'herdr_caret_helper_manager.dart';
import 'herdr_caret_snapshot.dart';

/// カーソル位置スナップショット読み取りの抽象。
///
/// [HerdrCaretSnapshotReader.read] は取得できない環境・失敗時に null を返す。
/// 成功時のみ nullable な [HerdrCaretSnapshot] を返す。
abstract interface class HerdrCaretSnapshotReader {
  /// [paneId] のカーソル snapshot を取得する（best-effort）。
  ///
  /// - 設定 OFF / 非対応環境 / 失敗 / stale は null。
  /// - 成功時は TTL 内の再呼び出しでキャッシュを返す。
  Future<HerdrCaretSnapshot?> read({
    required String paneId,
    required int cols,
    required int rows,
  });
}

/// [HerdrCaretHelperRunner] を注入した実装。
class HerdrCaretHelperSnapshotReader implements HerdrCaretSnapshotReader {
  /// 通常更新の TTL（同じ pane で helper を実行する最小間隔）。
  static const Duration defaultTtl = Duration(milliseconds: 500);

  /// helper 実行のタイムアウト。
  static const Duration defaultTimeout = Duration(milliseconds: 1000);

  final HerdrCaretHelperRunner _runner;
  final HerdrStatus Function() _statusProvider;
  final HerdrSnapshotCache Function() _cacheProvider;
  final bool Function() _enabled;
  final Duration _ttl;
  final Duration _timeout;
  final DateTime Function() _clock;

  HerdrCaretSnapshot? _cached;
  DateTime? _cachedAt;

  /// pane+epoch 単位の in-flight（single-flight）。
  final Map<String, Future<HerdrCaretSnapshot?>> _inFlight = {};

  HerdrCaretHelperSnapshotReader({
    required HerdrCaretHelperRunner runner,
    required HerdrStatus Function() statusProvider,
    required HerdrSnapshotCache Function() cacheProvider,
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

  /// キャッシュ済み snapshot（TTL 内のみ有効。無ければ null）。
  ///
  /// 診断用。表示ロジックは [read] を唯一の入口にすること。
  HerdrCaretSnapshot? get cachedSnapshot => _cached;

  @override
  Future<HerdrCaretSnapshot?> read({
    required String paneId,
    required int cols,
    required int rows,
  }) async {
    // 設定 OFF・非対応 protocol/socket・不正 frame は実行しない。
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
    if (!kHerdrCaretSupportedProtocols.contains(status.serverProtocol)) {
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
        cached.paneId == paneId &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _ttl &&
        !_hasInflight(paneId)) {
      return cached;
    }

    // epoch / adapter identity を実行前に記録する。
    final cacheBefore = _cacheProvider();
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
      now: now,
    );
    _inFlight[key] = future;
    future.whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    });
    return future;
  }

  bool _hasInflight(String paneId) =>
      _inFlight.keys.any((key) => key.startsWith('$paneId|'));

  Future<HerdrCaretSnapshot?> _fetch({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required int rows,
    required HerdrSnapshotCache cacheBefore,
    required int epochBefore,
    required DateTime now,
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
      if (!identical(cacheAfter, cacheBefore) ||
          cacheAfter.epoch != epochBefore) {
        _logState('stale', paneId); // 結果は破棄
        return null;
      }

      final parsed = HerdrCaretSnapshot.fromHelperJson(
        result.stdout,
        expectedPaneId: paneId,
        capturedAt: _clock(),
      );
      _cached = parsed;
      _cachedAt = parsed.capturedAt;
      return parsed;
    } on HerdrCaretHelperException catch (e) {
      // 失敗はキャッシュを更新しない（次の read で再試行される）。
      _logState(e.failure.name, paneId);
      return null;
    } on FormatException {
      _logState('invalid', paneId);
      return null;
    } catch (_) {
      _logState('invalid', paneId);
      return null;
    }
  }

  /// 状態分類のみを debug log へ出す（socket path・画面内容は出さない）。
  void _logState(String state, String paneId) {
    if (kDebugMode) {
      debugPrint('[herdr-caret] $state (pane=$paneId)');
    }
  }
}
