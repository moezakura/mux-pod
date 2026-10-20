// inventory: HERDR-SCROLLBACK-LINK-READER-000
/// スクロールモードのリンク読取サービス。
///
/// [TerminalScrollFollowController.onViewportSettled] から呼ばれ、
/// - 停止待ち 400ms（[stopDebounce]）: 呼び出しが連続する間は待ち直す
/// - 開始間隔 2 秒（[minInterval]）: 前回の往復開始から 2 秒経っていなければ、
///   2 秒経過後に最新の範囲だけを取得する（trailing-edge・まとめて1回）
/// - single-flight: 往復が進行中（`busy` 再試行の待機中を含む）は新しい
///   往復を開始しない。その間に届いた通知は [_pending] に積み、進行中の
///   往復が終わった直後に trailing-edge で 1 回だけ取得する
/// - 窓の計算: a = (本文行数 − 1 − 表示範囲の下端) + k_est。
///   R は「直近の helper 結果の実測 frame 行数
///   （[ScrollbackLinkCache.lastFrameRows]） >
///   [HerdrScrollbackLinkCurrentPane.viewportRows] >
///   [HerdrScrollbackLinkCurrentPane.rows]」の優先順位で解決する（
///   helper が実 pty サイズを Dart から渡した値より優先して使う
///   ようになったため、R は pane の viewport 行数の見積りではなく、実際に
///   helper が使った行数に追従させる）。表示範囲の行数が R 以下なら1窓、
///   R 超 2R 以下なら2窓、2R 超なら3窓（`ceil(表示範囲の行数 / R)` を
///   [HerdrScrollbackLinkHelperManager.maxWindowCount] で頭打ち）。窓は
///   a, a+R, a+2R … と隙間なく並べる。[ScrollbackLinkCache.lastK] を
///   k_est の見積りに使う。取得済みの窓は除外する
/// - `HerdrScrollbackLinkHelperRunner.run` を1回実行し、結果を
///   [ScrollbackLinkCache] へ多数決による整列
///   （[resolveHerdrHyperlinkAlignedLinks]）を通して反映する
/// - null identity precondition: `snapshotIdentity.identity` が `null`
///   なら往復しない（`HerdrController.isCurrentIdentity(null)` が `true`
///   を返す既知の落とし穴に頼らず、reader 自身が防御する）
/// - reconnect / pane 切替の破棄: await 後に pane identity・snapshot
///   generation・snapshot identity（[currentSnapshotIdentity]。再接続で
///   generation を跨がずに identity だけ変わる場合の検出。
///   `TerminalScrollFollowController.currentSnapshotIdentity` と同じ形）を
///   再照合し、不一致なら結果を捨てる（onUpdated を呼ばない）
/// - session token: [cancelPending] / [endSession] は内部トークンを
///   進め、進行中の往復（`busy` 再試行の待機を含む）が完了・再開しても
///   結果を適用しない（キャンセル後に届いた結果は捨てる）
/// - `busy` は 2 秒後に 1 回だけ再試行する
/// - キャンセル（[cancelPending]）: スクロールモードを抜けた・pane 切替・
///   接続断・バックグラウンド移行のいずれかで待機中の取得を捨てる。実行中の
///   往復は最後まで進めさせ、結果は session token・identity 照合で捨てる
///   （helper 側が最後まで進めて位置を戻すため）
/// - バックグラウンド中（[isActive] が `false`）は往復 0 回
///
/// 取得失敗は例外を投げず、その回のリンクを諦める（best-effort）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../backend/domain/pane_frame_reader.dart' show PaneHyperlinks;
import '../caret/herdr_caret_helper_types.dart';
import '../herdr_models.dart';
import 'herdr_hyperlink_alignment.dart';
import 'herdr_scrollback_link_helper_manager.dart';
import 'scrollback_link_cache.dart';

/// スクロールモードで現在対象にしている pane（id・幅・viewport 行数）。
///
/// 呼び出しごとに最新値を返す想定（reader は保持しない）。取得不能なら
/// `null`（この回は往復しない）。
///
/// フィールド名は既存の `HerdrCaretSnapshotReader.read({paneId, cols, rows})`
/// （`herdr_caret_snapshot_reader.dart`）に合わせる。
///
/// [rows] は窓計算の R の最終フォールバック（helper フレームの行数。pane
/// の viewport 行数の見積り）。helper 側は `pane.get` の
/// `scroll.viewport_rows` から実際の行数を決めるが、MuxPod 側の
/// 窓計算は事前に R を見積もる必要があるため、pane の現在の viewport 行数を
/// そのまま渡す。
///
/// [viewportRows] は `scroll.viewport_rows`（herdr status）から
/// 別経路で渡す、より正確な見積り（helper が実 pty サイズを
/// 優先するようになったことに伴う追加）。`_computeOffsets` の R は
/// 優先順位「直近の helper 結果の実測 frame 行数
/// （[ScrollbackLinkCache.lastFrameRows]） > [viewportRows] > [rows]」で
/// 解決する。取得できない・0 以下なら `null`（次の候補へフォールバック）。
typedef HerdrScrollbackLinkCurrentPane = ({
  String paneId,
  int cols,
  int rows,
  int? viewportRows,
});

class HerdrScrollbackLinkReader {
  /// 停止待ち（スクロールが400ms止まったとき）。
  static const Duration defaultStopDebounce = Duration(milliseconds: 400);

  /// 開始間隔（前回の開始から最低2秒）。
  static const Duration defaultMinInterval = Duration(seconds: 2);

  /// `busy` 時の再試行待ち（busy は2秒後に1回だけ再試行）。
  static const Duration defaultBusyRetryDelay = Duration(seconds: 2);

  /// helper 実行のタイムアウト
  /// （[HerdrScrollbackLinkHelperManager.defaultRunTimeout] と同じ既定値）。
  static const Duration defaultTimeout = Duration(milliseconds: 3200);

  final HerdrScrollbackLinkHelperRunner _runner;
  final ScrollbackLinkCache _cache;
  final HerdrStatus? Function() _status;
  final HerdrScrollbackLinkCurrentPane? Function() _currentPane;
  final List<String> Function() _bodyLinesFor;
  final void Function() _onUpdated;
  final bool Function() _isActive;
  final ({Object? identity, int generation})? Function()
  _currentSnapshotIdentity;
  final Duration _stopDebounce;
  final Duration _minInterval;
  final Duration _busyRetryDelay;
  final Duration _timeout;
  final DateTime Function() _clock;

  Timer? _debounceTimer;
  Timer? _intervalTimer;
  Timer? _busyRetryTimer;
  DateTime? _lastStartedAt;
  _PendingSettle? _pending;

  /// `busy` 再試行の待機中（[_busyRetryTimer] が発火するまで）、[_attempt]
  /// が `await` している Completer。
  /// [_busyRetryTimer] のコールバックでしか完了しないため、待機中
  /// に [cancelPending] / [endSession] が Timer だけを cancel すると、
  /// この Completer が永久に完了せず `_runFetch` の `await` が戻らない
  /// （`_fetchInFlight` が true のまま残り、以後往復できなくなる）。
  /// [cancelPending] で Timer と一緒に complete する。
  ///
  /// 保持するのは Timer 待機中だけ。
  /// [_busyRetryTimer] が発火した瞬間（＝再試行の helper 呼び出しが実行中
  /// になる瞬間）に `null` へ戻す。それ以降は「実行中の往復（[_attempt]
  /// の `await` 中）」として通常どおり [cancelPending] の対象外になり、
  /// 最後まで走らせる（`実行中の往復（[_runFetch] の await 中）は
  /// キャンセルしない` という既存方針と一致させる）。ここを広く保持すると
  /// single-flight が破れ、`Future already completed` にもなる。
  Completer<void>? _busyRetryDone;

  /// 進行中の往復があるかどうか（`busy` 再試行の待機中も含む）。
  /// `true` の間は新しい往復を開始しない（trailing-edge は [_pending] で
  /// 保持し、往復が終わった直後に拾う）。
  bool _fetchInFlight = false;

  /// [cancelPending] / [endSession] のたびに進む世代トークン。
  /// 進行中の往復（`busy` 再試行の待機を含む）が、開始時点のトークンと
  /// 現在のトークンを比較し、不一致なら再試行の予約・結果適用のどちらも
  /// 行わない。
  int _sessionToken = 0;

  /// [runner]・[cache] は必須。以下は構築と配線を分離するため
  /// screen 層（`terminal_root_bindings.dart`）が注入する:
  /// - [status]: 現在の `HerdrStatus`（非対応・未接続なら `null`）
  /// - [currentPane]: 現在対象の pane id・幅・viewport 行数（取得不能なら
  ///   `null`）
  /// - [bodyLinesFor]: 現在のスクロールモード表示本文（行の配列。
  ///   整列に使うフィンガープリント元）
  /// - [onUpdated]: キャッシュ更新後の再描画要求
  /// - [isActive]: バックグラウンドでないか（`false` の間は往復しない。
  ///   `() => !runtime.isInBackground` を渡す想定。新規 port は追加しない）
  /// - [currentSnapshotIdentity]: 現在のスナップショット identity（
  ///   `TerminalScrollFollowController.currentSnapshotIdentity` と同じ形。
  ///   await 後の再照合に使う）
  HerdrScrollbackLinkReader({
    required HerdrScrollbackLinkHelperRunner runner,
    required ScrollbackLinkCache cache,
    required HerdrStatus? Function() status,
    required HerdrScrollbackLinkCurrentPane? Function() currentPane,
    required List<String> Function() bodyLinesFor,
    required void Function() onUpdated,
    required bool Function() isActive,
    required ({Object? identity, int generation})? Function()
    currentSnapshotIdentity,
    Duration stopDebounce = defaultStopDebounce,
    Duration minInterval = defaultMinInterval,
    Duration busyRetryDelay = defaultBusyRetryDelay,
    Duration timeout = defaultTimeout,
    DateTime Function()? clock,
  }) : _runner = runner,
       _cache = cache,
       _status = status,
       _currentPane = currentPane,
       _bodyLinesFor = bodyLinesFor,
       _onUpdated = onUpdated,
       _isActive = isActive,
       _currentSnapshotIdentity = currentSnapshotIdentity,
       _stopDebounce = stopDebounce,
       _minInterval = minInterval,
       _busyRetryDelay = busyRetryDelay,
       _timeout = timeout,
       _clock = clock ?? DateTime.now;

  /// [TerminalScrollFollowController.onViewportSettled] から呼ぶ
  /// （4引数目の `visibleRange` まで含めてそのまま渡す）。
  ///
  /// throw しない・sync で受け付ける（取得は内部で async に行う）。
  void onViewportSettled(
    ({Object? identity, int generation}) snapshotIdentity,
    int lineCount,
    ({int top, int bottom}) visibleRange,
  ) {
    if (!_isActive()) {
      _log('background-skip');
      return;
    }
    _cache.resetIfNeeded(
      identity: snapshotIdentity.identity,
      generation: snapshotIdentity.generation,
    );
    _pending = _PendingSettle(
      snapshotIdentity: snapshotIdentity,
      lineCount: lineCount,
      visibleRange: visibleRange,
    );
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_stopDebounce, _onDebounceElapsed);
  }

  /// 待機中の取得を捨てる（スクロールモードを抜けた・pane 切替・接続断・
  /// バックグラウンド移行のいずれか）。実行中の往復（[_runFetch] の
  /// `await` 中）はキャンセルしない（helper 側が最後まで進めて位置を戻す）。
  /// session token を進め、結果適用・再試行の予約のどちらも行わせない。
  ///
  /// `busy` 再試行の待機中（[_busyRetryTimer] 発火前）なら、Timer を
  /// cancel するだけでなく [_busyRetryDone] も complete する。そうしないと [_attempt] の
  /// `await` が戻らず、[_runFetch] の `finally`（`_fetchInFlight` を
  /// false に戻す処理）が永久に実行されない。
  void cancelPending() {
    _sessionToken++;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _intervalTimer?.cancel();
    _intervalTimer = null;
    _busyRetryTimer?.cancel();
    _busyRetryTimer = null;
    final busyRetryDone = _busyRetryDone;
    _busyRetryDone = null;
    if (busyRetryDone != null && !busyRetryDone.isCompleted) {
      busyRetryDone.complete();
    }
    _pending = null;
  }

  /// スクロールモード終了。待機中の取得を捨て、キャッシュを破棄する
  /// （キャッシュはスナップショット差し替えとスクロールモード終了で
  /// 破棄される）。
  void endSession() {
    cancelPending();
    _cache.clear();
  }

  /// 破棄（画面破棄時）。[endSession] と同じ後始末を行う。
  void dispose() {
    endSession();
  }

  void _onDebounceElapsed() {
    _debounceTimer = null;
    _scheduleOrRunFetch();
  }

  void _scheduleOrRunFetch() {
    if (!_isActive()) {
      _log('background-skip');
      return;
    }
    if (_fetchInFlight) {
      // 進行中の往復がある間は新しく開始しない。_pending は
      // onViewportSettled が常に最新へ更新済みなので、往復完了後の
      // trailing-edge（_runFetch の finally）が拾う。
      return;
    }
    final pending = _pending;
    if (pending == null) return;

    final now = _clock();
    final last = _lastStartedAt;
    final remaining = last == null
        ? Duration.zero
        : _minInterval - now.difference(last);
    if (remaining > Duration.zero) {
      // trailing-edge: 既にタイマーが動いていれば新しく張り直さない
      // （_pending は onViewportSettled が常に最新へ更新済み）。
      _intervalTimer ??= Timer(remaining, () {
        _intervalTimer = null;
        _scheduleOrRunFetch();
      });
      return;
    }

    _pending = null;
    unawaited(_runFetch(pending));
  }

  Future<void> _runFetch(_PendingSettle pending) async {
    if (!_isActive()) {
      _log('background-skip');
      return;
    }
    final identity = pending.snapshotIdentity.identity;
    if (identity == null) {
      // captureTargetIdentity() が null（未接続・キャッシュ未確立）。
      // isCurrent(null) が true を返す既知の落とし穴があるため、ここで
      // reader 自身が防御する。
      _log('no-identity');
      return;
    }
    final status = _status();
    if (status == null) {
      _log('no-status');
      return;
    }
    final pane = _currentPane();
    if (pane == null) {
      _log('no-pane');
      return;
    }

    final generation = pending.snapshotIdentity.generation;
    final offsets = _computeOffsets(
      lineCount: pending.lineCount,
      visibleRange: pending.visibleRange,
      paneRows: _resolveWindowRowSpan(pane),
    ).where((offset) => !_cache.hasFetched(offset)).toList();
    if (offsets.isEmpty) return; // 取得済みの範囲のみ

    // ここから往復が終わるまで（busy 再試行を含む）単一実行に絞る。
    _fetchInFlight = true;
    final token = _sessionToken;
    try {
      await _attempt(
        pane: pane,
        status: status,
        identity: identity,
        generation: generation,
        offsets: offsets,
        token: token,
        isBusyRetry: false,
      );
    } finally {
      _fetchInFlight = false;
      // 待機中の trailing-edge を拾う。
      // token の一致は問わない: cancelPending/endSession は _pending も
      // 消すため、ここで _pending が残っているなら、それは古い往復が
      // 終わった後に届いた「新しいセッションの」通知であり、拾うべき。
      // _scheduleOrRunFetch は isActive/_pending==null を自分で判定する
      // ので、endSession 直後（_pending == null）やバックグラウンド中は
      // 何も起きない。
      _scheduleOrRunFetch();
    }
  }

  /// 1 回分の往復（`busy` 再試行を含む）。[token] が [cancelPending] /
  /// [endSession] で進んでいれば、再試行の予約・結果適用のどちらも
  /// 行わない。
  Future<void> _attempt({
    required HerdrScrollbackLinkCurrentPane pane,
    required HerdrStatus status,
    required Object identity,
    required int generation,
    required List<int> offsets,
    required int token,
    required bool isBusyRetry,
  }) async {
    _lastStartedAt = _clock();
    final ScrollbackLinksResult result;
    try {
      result = await _runner.run(
        status: status,
        paneId: pane.paneId,
        cols: pane.cols,
        offsetsFromBottom: offsets,
        timeout: _timeout,
      );
    } on HerdrCaretHelperException catch (e) {
      if (token != _sessionToken) {
        _log('discarded-cancelled');
        return;
      }
      if (!isBusyRetry && e.helperErrorKind == HerdrHelperErrorKind.busy) {
        _log('busy-retry');
        final retryDone = Completer<void>();
        // [cancelPending] /
        // [endSession] が待機中に呼ばれても解放できるよう、フィールドに
        // 保持する（Timer の cancel だけでは Completer は完了しない）。
        _busyRetryDone = retryDone;
        _busyRetryTimer?.cancel();
        _busyRetryTimer = Timer(_busyRetryDelay, () {
          _busyRetryTimer = null;
          // [_busyRetryDone] を
          // 「cancelPending が完了させてよい」状態のまま保つのは、
          // Timer がまだ発火していない待機中だけにする。Timer が発火した
          // 時点（＝再試行の helper 呼び出しがこれから実行中になる時点）
          // で直ちに null に戻す。ここで clear しないと、再試行の helper
          // が実際に実行中（await 中）の間に cancelPending が呼ばれた
          // ときにも retryDone を早期 complete してしまい、
          // (1) single-flight が破れる（この往復と、キャンセル後に
          // 新規に始まる往復が並行する）、
          // (2) 後続の `.whenComplete()` が同じ Completer をもう一度
          // complete しようとして `Bad state: Future already completed`
          // になる。
          _busyRetryDone = null;
          if (token != _sessionToken) {
            _log('discarded-cancelled');
            if (!retryDone.isCompleted) retryDone.complete();
            return;
          }
          unawaited(
            _attempt(
              pane: pane,
              status: status,
              identity: identity,
              generation: generation,
              offsets: offsets,
              token: token,
              isBusyRetry: true,
            ).whenComplete(() {
              if (!retryDone.isCompleted) retryDone.complete();
            }),
          );
        });
        // busy 再試行が解決するまで、この往復を「進行中」のまま保つ
        // （single-flight）。
        return retryDone.future;
      }
      _log(e.failure.name);
      return;
    } catch (_) {
      _log('invalid');
      return;
    }

    if (token != _sessionToken) {
      _log('discarded-cancelled');
      return;
    }
    // reconnect / pane 切替の破棄: await 完了後に再照合する。
    if (!_isActive()) {
      _log('background-discard');
      return;
    }
    final paneAfter = _currentPane();
    if (paneAfter == null || paneAfter.paneId != pane.paneId) {
      _log('discarded-pane-mismatch');
      return;
    }
    if (_cache.generation != generation) {
      _log('discarded-generation-mismatch');
      return;
    }
    // generation を跨がずに identity だけ変わる再接続を検出する。
    final identityAfter = _currentSnapshotIdentity();
    if (identityAfter == null || identityAfter.identity != identity) {
      _log('discarded-identity-mismatch');
      return;
    }

    final bodyLines = _bodyLinesFor();
    final bodyFingerprints = List<String?>.generate(
      bodyLines.length,
      (i) => HerdrRowFingerprint.rowFingerprint(bodyLines[i]),
      growable: false,
    );

    var updated = false;
    for (var i = 0; i < result.windows.length; i++) {
      final window = result.windows[i];
      final requestedOffset = offsets[i];
      final aligned = _alignWindow(
        hyperlinks: window.hyperlinks,
        bodyFingerprints: bodyFingerprints,
        windowOffset: window.actualOffset,
      );
      final actualFrameRows = window.hyperlinks.frameHeight;
      _cache.applyWindowResult(
        generation: generation,
        offsetFromBottom: requestedOffset,
        linksByBodyLine: aligned?.linksByBodyLine ?? const {},
        k: aligned?.k,
        // 整列の成否に関わらず、helper が実際に使った
        // frame 行数は次回の窓タイリングの見積りとして採用する（正の値の
        // ときだけ ScrollbackLinkCache が取り込む）。
        frameRows: actualFrameRows,
        truncated: window.hyperlinks.truncated,
      );
      updated = true;
    }
    if (updated) _onUpdated();
  }

  /// [PaneHyperlinks]（窓1つ分）を整列の入力形へ変換して呼ぶ
  /// （`herdr_hyperlink_reconciler.dart` の通常表示側の変換と同じ組み替え。
  /// 窓ごとに `windowOffset` が異なる点だけが違う）。
  HerdrHyperlinkAlignedLinks? _alignWindow({
    required PaneHyperlinks hyperlinks,
    required List<String?> bodyFingerprints,
    required int windowOffset,
  }) {
    final frameRows = hyperlinks.frameHeight;
    if (bodyFingerprints.isEmpty || frameRows <= 0) return null;

    final frameFingerprints = List<String?>.generate(
      frameRows,
      (r) => hyperlinks.rowFingerprints[r],
      growable: false,
    );
    final frameLinksByRow = <int, List<HerdrHyperlinkRange>>{};
    for (final link in hyperlinks.links) {
      for (final range in link.ranges) {
        (frameLinksByRow[range.row] ??= <HerdrHyperlinkRange>[]).add(
          HerdrHyperlinkRange(
            startCol: range.startCol,
            endCol: range.endCol,
            url: link.url,
          ),
        );
      }
    }

    return resolveHerdrHyperlinkAlignedLinks(
      frameLinksByRow: frameLinksByRow,
      bodyFingerprints: bodyFingerprints,
      frameFingerprints: frameFingerprints,
      frameWidth: hyperlinks.frameWidth,
      windowOffset: windowOffset,
    );
  }

  /// [_computeOffsets] の R を解決する（優先順位: 直近の
  /// helper 結果の実測 frame 行数（[ScrollbackLinkCache.lastFrameRows]） >
  /// [HerdrScrollbackLinkCurrentPane.viewportRows] >
  /// [HerdrScrollbackLinkCurrentPane.rows]）。0 以下の値は「分からなかった」
  /// として次の候補へ読み進める（[viewportRows] が 0 以下・`null` を素通し
  /// してくる可能性があるため。[rows] は常に正の値である前提・呼び出し元が
  /// 既に保証している）。
  int _resolveWindowRowSpan(HerdrScrollbackLinkCurrentPane pane) {
    final lastFrameRows = _cache.lastFrameRows;
    if (lastFrameRows != null && lastFrameRows > 0) return lastFrameRows;
    final viewportRows = pane.viewportRows;
    if (viewportRows != null && viewportRows > 0) return viewportRows;
    return pane.rows;
  }

  /// 表示中の行の範囲から `offsetFromBottom` を最大
  /// [HerdrScrollbackLinkHelperManager.maxWindowCount] 個算出する
  ///
  /// a = (`lineCount` − 1 − `visibleRange.bottom`) + k_est
  /// （直近に採用した k。[ScrollbackLinkCache.lastK]。無ければ 0）。
  /// R は呼び出し元（[_runFetch]）が [_resolveWindowRowSpan] で解決した値
  /// （直近の helper 実測 frame 行数 >
  /// [HerdrScrollbackLinkCurrentPane.viewportRows] >
  /// [HerdrScrollbackLinkCurrentPane.rows] の優先順位。以前は pane の
  /// viewport 行数がそのまま helper フレームの行数と同じという想定だった
  /// が、helper が実 pty サイズを優先するようになったため、実測値に
  /// 追従させる）。表示範囲の行数（`visibleRange` の高さ）が R 以下なら
  /// 1窓、R を超え 2R 以下なら2窓、2R を超えるなら3窓（上限。3R を超えても
  /// 3窓のまま増やさない）。窓は a, a+R, a+2R … と隙間なく並べる
  /// （`ceil(visibleRows / R)` を [HerdrScrollbackLinkHelperManager.maxWindowCount]
  /// で頭打ちにする）。`lineCount` を超える窓（スナップショットに存在
  /// しない範囲）は含めない。
  List<int> _computeOffsets({
    required int lineCount,
    required ({int top, int bottom}) visibleRange,
    required int paneRows,
  }) {
    if (lineCount <= 0 || paneRows <= 0) return const [];
    final visibleRows = visibleRange.bottom - visibleRange.top + 1;
    if (visibleRows <= 0) return const [];

    final kEst = _cache.lastK ?? 0;
    final baseOffset = (lineCount - 1 - visibleRange.bottom) + kEst;
    final neededWindows = (visibleRows + paneRows - 1) ~/ paneRows; // ceil
    final windowCount =
        neededWindows < HerdrScrollbackLinkHelperManager.maxWindowCount
        ? neededWindows
        : HerdrScrollbackLinkHelperManager.maxWindowCount;

    final offsets = <int>[];
    for (var i = 0; i < windowCount; i++) {
      final offset = baseOffset + (paneRows * i);
      if (offset < 0 || offset >= lineCount) break;
      offsets.add(offset);
    }
    return offsets;
  }

  /// 状態分類のみを debug log へ出す（socket path・pane 本文は出さない）。
  void _log(String state) {
    if (kDebugMode) {
      debugPrint('[herdr-scrollback-link] $state');
    }
  }
}

class _PendingSettle {
  final ({Object? identity, int generation}) snapshotIdentity;
  final int lineCount;
  final ({int top, int bottom}) visibleRange;

  const _PendingSettle({
    required this.snapshotIdentity,
    required this.lineCount,
    required this.visibleRange,
  });
}
