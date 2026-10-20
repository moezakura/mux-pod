// inventory: HERDR-SCROLLBACK-LINK-READER-TEST-000
/// herdr_scrollback_link_reader.dart のテスト。
///
/// [HerdrScrollbackLinkReader] は `Timer` による停止待ち 400ms・開始間隔
/// 2秒・busy 再試行 2秒を内部で使うため、`flutter_test` の
/// `TestWidgetsFlutterBinding` が test 本体全体を包む FakeAsync ゾーンを
/// 利用する（`testWidgets` を widget を pump せずに使い、
/// `tester.pump(duration)` でタイマーを進める）。
///
/// `HerdrScrollbackLinkReader` の既定 `clock`（`DateTime.now`）は生の壁時計
/// で、FakeAsync は `Timer` は仮想化するが素の `DateTime.now()` は仮想化
/// しない（`package:clock` の `clock.now()` 経由の呼び出しだけを差し替える）。
/// そのため開始間隔 2 秒の判定を検証するテストでは、`clock:` に手動で進める
/// `now` を注入する（`herdr_caret_snapshot_reader_test.dart` と同じ手法）。
/// [advance] は `now` と仮想タイマーの両方を同じ量だけ
/// 進める。
library;

import 'dart:async';

import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_types.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_alignment.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_reader.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/scrollback_link_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// [HerdrScrollbackLinkHelperRunner] の fake。
class _FakeRunner implements HerdrScrollbackLinkHelperRunner {
  int calls = 0;
  final List<List<int>> offsetsPerCall = [];

  /// 呼び出しごとに返す結果を差し替えられる（デフォルトは空の窓）。
  ScrollbackLinksResult Function(List<int> offsets)? onRun;

  /// 設定時は [run] がこの完了まで待機する（in-flight 状態を作る）。
  Completer<void>? gate;

  @override
  Future<ScrollbackLinksResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required List<int> offsetsFromBottom,
    Duration? timeout,
  }) async {
    calls++;
    offsetsPerCall.add(offsetsFromBottom);
    final g = gate;
    if (g != null) await g.future;
    final handler = onRun;
    if (handler != null) return handler(offsetsFromBottom);
    return ScrollbackLinksResult(
      windows: [
        for (final offset in offsetsFromBottom)
          ScrollbackLinkWindow(
            requestedOffset: offset,
            actualOffset: offset,
            hyperlinks: const PaneHyperlinks(
              frameWidth: 80,
              frameHeight: 0,
              links: [],
              rowFingerprints: {},
              truncated: false,
            ),
          ),
      ],
      restore: ScrollbackLinkRestore.exact,
    );
  }
}

const _status = HerdrStatus(serverProtocol: 22, socket: '/tmp/herdr.sock');

void main() {
  late _FakeRunner runner;
  late ScrollbackLinkCache cache;
  late List<void Function()> updates;
  late bool active;
  late String? paneId;
  late int cols;
  late int rows;
  late int? viewportRows;
  late Object? identity;
  late int liveGeneration;
  late List<String> bodyLines;
  late DateTime now;

  HerdrScrollbackLinkReader makeReader({
    Duration stopDebounce = const Duration(milliseconds: 400),
    Duration minInterval = const Duration(seconds: 2),
    Duration busyRetryDelay = const Duration(seconds: 2),
  }) {
    return HerdrScrollbackLinkReader(
      runner: runner,
      cache: cache,
      status: () => _status,
      currentPane: () => paneId == null
          ? null
          : (
              paneId: paneId!,
              cols: cols,
              rows: rows,
              viewportRows: viewportRows,
            ),
      bodyLinesFor: () => bodyLines,
      onUpdated: () {
        for (final fn in updates) {
          fn();
        }
      },
      isActive: () => active,
      // await 後の identity/generation 再照合用。`identity`/`liveGeneration` は
      // テストが往復中に書き換えて再接続を模擬する（`paneId` を使った
      // 既存の pane 切替テストと同じ手法）。
      currentSnapshotIdentity: () => liveGeneration == 0
          ? null
          : (identity: identity, generation: liveGeneration),
      stopDebounce: stopDebounce,
      minInterval: minInterval,
      busyRetryDelay: busyRetryDelay,
      clock: () => now,
    );
  }

  setUp(() {
    runner = _FakeRunner();
    cache = ScrollbackLinkCache();
    updates = [];
    active = true;
    paneId = 'w1:t1:p1';
    cols = 80;
    // pane の viewport 行数（R）。既存テストの多くは
    // 表示範囲の行数と同じ 20 を既定にして、単一窓（表示範囲が R を
    // 超えない）のケースを基本形にする。
    rows = 20;
    // viewportRows は既定 null（未設定時の既存挙動の回帰確認用）。個別テストで上書きする。
    viewportRows = null;
    identity = Object();
    liveGeneration = 1;
    bodyLines = List.generate(200, (i) => 'line $i');
    now = DateTime(2024, 1, 1);
  });

  ({Object? identity, int generation}) snap(int generation) =>
      (identity: identity, generation: generation);

  /// `now`（reader へ注入した clock）と FakeAsync の仮想タイマーを同じ量
  /// だけ進める。
  Future<void> advance(WidgetTester tester, Duration d) async {
    now = now.add(d);
    await tester.pump(d);
  }

  testWidgets('止めて400ms後に1回だけ往復する', (tester) async {
    final reader = makeReader();
    var updateCount = 0;
    updates.add(() => updateCount++);

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    expect(runner.calls, 0);

    await advance(tester, const Duration(milliseconds: 399));
    expect(runner.calls, 0);

    await advance(tester, const Duration(milliseconds: 1));
    await tester.pump();
    expect(runner.calls, 1);
    expect(updateCount, 1);
  });

  testWidgets('400ms以内の連続呼び出しは1回にまとまり最新の範囲を使う', (tester) async {
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 0, bottom: 19));
    await advance(tester, const Duration(milliseconds: 200));
    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 399));
    expect(runner.calls, 0);

    await advance(tester, const Duration(milliseconds: 1));
    await tester.pump();
    expect(runner.calls, 1);
    // bottom=199 → offset = 200-1-199 = 0（最新の範囲）。
    expect(runner.offsetsPerCall.single, contains(0));
  });

  testWidgets('前回の開始から2秒以内の停止はまとめて1回・最新の範囲を使う（trailing-edge）', (tester) async {
    final reader = makeReader();
    var updateCount = 0;
    updates.add(() => updateCount++);

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    // 1秒後（開始から2秒未満）に別範囲で止まる。
    await advance(tester, const Duration(milliseconds: 600));
    reader.onViewportSettled(snap(1), 200, (top: 0, bottom: 19));
    await advance(tester, const Duration(milliseconds: 400));
    // まだ開始から2秒経っていないので往復しない。
    expect(runner.calls, 1);

    // 開始から2秒経過。
    await advance(tester, const Duration(seconds: 1));
    await tester.pump();
    expect(runner.calls, 2);
    // top=0,bottom=19 → offset = 200-1-19 = 180。
    expect(runner.offsetsPerCall.last, contains(180));
    expect(updateCount, 2);
  });

  testWidgets('busy は2秒後に1回だけ再試行する', (tester) async {
    var callCount = 0;
    runner.onRun = (offsets) {
      callCount++;
      if (callCount == 1) {
        throw const HerdrCaretHelperException(
          HerdrCaretHelperFailure.execFailed,
          'busy',
          null,
          HerdrHelperErrorKind.busy,
        );
      }
      return ScrollbackLinksResult(
        windows: [
          for (final offset in offsets)
            ScrollbackLinkWindow(
              requestedOffset: offset,
              actualOffset: offset,
              hyperlinks: const PaneHyperlinks(
                frameWidth: 80,
                frameHeight: 0,
                links: [],
                rowFingerprints: {},
                truncated: false,
              ),
            ),
        ],
        restore: ScrollbackLinkRestore.exact,
      );
    };
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    // 2秒未満では再試行しない。
    await advance(tester, const Duration(milliseconds: 1999));
    expect(runner.calls, 1);

    await advance(tester, const Duration(milliseconds: 1));
    await tester.pump();
    expect(runner.calls, 2);

    // 再試行後さらに時間が経っても3回目は起きない（1回だけ）。
    await advance(tester, const Duration(seconds: 5));
    expect(runner.calls, 2);
  });

  testWidgets('バックグラウンド中は往復0回', (tester) async {
    active = false;
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(seconds: 3));
    await tester.pump();
    expect(runner.calls, 0);
  });

  testWidgets('captureTargetIdentity() が null なら往復しない', (tester) async {
    identity = null;
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(seconds: 3));
    await tester.pump();
    expect(runner.calls, 0);
  });

  testWidgets('cancelPending は待機中の取得を捨てる', (tester) async {
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 100));
    reader.cancelPending();
    await advance(tester, const Duration(seconds: 3));
    await tester.pump();
    expect(runner.calls, 0);
  });

  testWidgets('再構築後（pane 切替）に届いた結果は捨てる（onUpdated を呼ばない）', (tester) async {
    runner.gate = Completer<void>();
    var updateCount = 0;
    updates.add(() => updateCount++);
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    // 往復中に pane が切り替わる。
    paneId = 'w1:t1:p2';
    runner.gate!.complete();
    await tester.pump();
    await tester.pump();

    expect(updateCount, 0);
    expect(cache.linksByBodyLine, isEmpty);
  });

  testWidgets('スナップショット差し替え後（generation不一致）に届いた結果は捨てる', (tester) async {
    runner.gate = Completer<void>();
    var updateCount = 0;
    updates.add(() => updateCount++);
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    // 往復中に新しいスナップショットへ切り替わる。
    cache.resetIfNeeded(identity: Object(), generation: 2);
    runner.gate!.complete();
    await tester.pump();
    await tester.pump();

    expect(updateCount, 0);
  });

  testWidgets('再接続（同じ pane・generation・identity だけ変化）で届いた結果は捨てる', (
    tester,
  ) async {
    runner.gate = Completer<void>();
    var updateCount = 0;
    updates.add(() => updateCount++);
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    // 往復中に再接続が起きる: paneId・cache.generation は変わらないが、
    // `currentSnapshotIdentity()` が返す identity オブジェクトだけが
    // 変わる（epoch / adapter 差し替え）。
    identity = Object();
    runner.gate!.complete();
    await tester.pump();
    await tester.pump();

    expect(updateCount, 0);
    expect(cache.linksByBodyLine, isEmpty);
  });

  testWidgets('endSession はキャッシュを破棄し、往復中の結果も捨てる', (tester) async {
    runner.gate = Completer<void>();
    var updateCount = 0;
    updates.add(() => updateCount++);
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    reader.endSession();
    expect(cache.generation, isNull);

    runner.gate!.complete();
    await tester.pump();
    await tester.pump();

    expect(updateCount, 0);
    expect(cache.linksByBodyLine, isEmpty);
  });

  testWidgets('cancelPending 後、往復中に busy が返っても再試行を予約しない', (tester) async {
    runner.gate = Completer<void>();
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    // 往復中（helper 呼び出し中）にキャンセルされる。
    reader.cancelPending();

    // gate を解いて busy 例外を返す。
    runner.onRun = (offsets) => throw const HerdrCaretHelperException(
      HerdrCaretHelperFailure.execFailed,
      'busy',
      null,
      HerdrHelperErrorKind.busy,
    );
    runner.gate!.complete();
    await tester.pump();

    // キャンセル済みなので busy 再試行は予約されない。5秒経っても
    // 2本目の往復は起きない。
    await advance(tester, const Duration(seconds: 5));
    expect(runner.calls, 1);
  });

  testWidgets('busy 再試行の待機中に cancelPending を呼んでも、往復が止まったままにならない'
      '（busy retry cancel leaves fetch stuck の回帰）', (tester) async {
    var callCount = 0;
    runner.onRun = (offsets) {
      callCount++;
      if (callCount == 1) {
        throw const HerdrCaretHelperException(
          HerdrCaretHelperFailure.execFailed,
          'busy',
          null,
          HerdrHelperErrorKind.busy,
        );
      }
      return ScrollbackLinksResult(
        windows: [
          for (final offset in offsets)
            ScrollbackLinkWindow(
              requestedOffset: offset,
              actualOffset: offset,
              hyperlinks: const PaneHyperlinks(
                frameWidth: 80,
                frameHeight: 0,
                links: [],
                rowFingerprints: {},
                truncated: false,
              ),
            ),
        ],
        restore: ScrollbackLinkRestore.exact,
      );
    };
    final reader = makeReader();

    // 1. 1回目で busy を返す。
    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    // 2. busy 再試行（2秒後）を待機中に cancelPending を呼ぶ。
    // このとき `_busyRetryTimer` は cancel されるが、修正前は待機用の
    // Completer が完了せず `_runFetch` の await が戻らないままになる。
    reader.cancelPending();

    // 3. 時計を5秒進める（busyRetryDelay の2秒を超える）。
    await advance(tester, const Duration(seconds: 5));
    await tester.pump();

    // キャンセルしたので再試行そのものは起きない（1回のまま）。
    expect(runner.calls, 1);

    // 4. まだ取得していない範囲（offset 180）で settle させる。
    reader.onViewportSettled(snap(1), 200, (top: 0, bottom: 19));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();

    // 5. 2回目の往復が起きる。修正前は `_fetchInFlight` が true のまま
    // 残るため、`_scheduleOrRunFetch` が常に早期 return し、ここが
    // 永久に起きない（runner.calls が1のまま）。
    expect(runner.calls, 2);
  });

  testWidgets('再試行の helper が実行中（gate 待ち）のときに cancelPending を呼んでも、'
      '2本目の往復が並行して始まらない（single-flight 違反の回帰）', (tester) async {
    var callCount = 0;
    runner.onRun = (offsets) {
      callCount++;
      if (callCount == 1) {
        throw const HerdrCaretHelperException(
          HerdrCaretHelperFailure.execFailed,
          'busy',
          null,
          HerdrHelperErrorKind.busy,
        );
      }
      return ScrollbackLinksResult(
        windows: [
          for (final offset in offsets)
            ScrollbackLinkWindow(
              requestedOffset: offset,
              actualOffset: offset,
              hyperlinks: const PaneHyperlinks(
                frameWidth: 80,
                frameHeight: 0,
                links: [],
                rowFingerprints: {},
                truncated: false,
              ),
            ),
        ],
        restore: ScrollbackLinkRestore.exact,
      );
    };
    final reader = makeReader();

    // 1. 1回目で busy を返す。
    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    // 2. 再試行（2秒後）の helper 呼び出しを実行中のまま止める（gate）。
    runner.gate = Completer<void>();
    await advance(tester, const Duration(seconds: 2));
    await tester.pump();
    expect(runner.calls, 2); // 再試行の呼び出しは始まった（gate 待ち中）。

    // 3. 再試行の helper が実行中のまま cancelPending を呼ぶ。
    reader.cancelPending();

    // 4. 別の範囲（まだ取得していない offset 180）で settle させる。
    reader.onViewportSettled(snap(1), 200, (top: 0, bottom: 19));
    await advance(tester, const Duration(seconds: 3));
    await tester.pump();

    // single-flight が守られていること: 再試行の helper がまだ gate で
    // 止まっている間は、2本目の往復は始まらない（3本目の呼び出しは
    // 起きない。修正前はここで calls が3になる）。
    expect(runner.calls, 2);

    // 5. 再試行の helper を完了させる（gate を解く）。
    runner.gate!.complete();
    await tester.pump();

    // 例外が発生していないこと（修正前は Completer を二重に complete
    // しようとして `Bad state: Future already completed` が出る）。
    expect(tester.takeException(), isNull);

    // 6. 再試行が終わった後、新しい pending（offset 180）で次の往復が
    // 走ること。
    await tester.pump();
    expect(runner.calls, 3);
    expect(runner.offsetsPerCall.last, contains(180));
  });

  testWidgets('busy 再試行の待機中に endSession を呼んでも、往復が止まったままにならない', (tester) async {
    var callCount = 0;
    runner.onRun = (offsets) {
      callCount++;
      if (callCount == 1) {
        throw const HerdrCaretHelperException(
          HerdrCaretHelperFailure.execFailed,
          'busy',
          null,
          HerdrHelperErrorKind.busy,
        );
      }
      return ScrollbackLinksResult(
        windows: [
          for (final offset in offsets)
            ScrollbackLinkWindow(
              requestedOffset: offset,
              actualOffset: offset,
              hyperlinks: const PaneHyperlinks(
                frameWidth: 80,
                frameHeight: 0,
                links: [],
                rowFingerprints: {},
                truncated: false,
              ),
            ),
        ],
        restore: ScrollbackLinkRestore.exact,
      );
    };
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    // busy 再試行の待機中に endSession（画面破棄・スクロールモード終了）
    // が呼ばれる。cancelPending と同じく待機を打ち切る必要がある。
    reader.endSession();
    expect(cache.generation, isNull);

    await advance(tester, const Duration(seconds: 5));
    await tester.pump();
    expect(runner.calls, 1);

    // 新しいセッションで settle させると、往復が再開できる
    // （修正前は _fetchInFlight が true のまま残り、ここが起きない）。
    reader.onViewportSettled(snap(1), 200, (top: 0, bottom: 19));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 2);
  });

  testWidgets('往復中に届いた通知は、往復完了後にまとめて1回だけ取得する（単一実行）', (tester) async {
    runner.gate = Completer<void>();
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1); // gate 待ちでまだ戻っていない

    // 往復中（gate 待ち）に新しい停止通知が届く。2秒の開始間隔を過ぎても、
    // 進行中の往復がある間は新しく開始しない（同時に2本目を実行しない）。
    reader.onViewportSettled(snap(1), 200, (top: 0, bottom: 19));
    await advance(tester, const Duration(milliseconds: 400));
    await advance(tester, const Duration(seconds: 3));
    expect(runner.calls, 1);

    // 往復が完了すると、trailing-edge で最新の範囲を1回だけ取得する。
    runner.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(runner.calls, 2);
    // top=0,bottom=19 → offset = 200-1-19 = 180。
    expect(runner.offsetsPerCall.last, contains(180));
  });

  testWidgets('cancelPending 後に届いた新しい通知は、古い往復が完了した後に取得する', (tester) async {
    runner.gate = Completer<void>();
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1); // gate 待ち

    // 往復中にキャンセルされる（スクロールモードを抜けた・pane 切替等）。
    reader.cancelPending();

    // その直後、新しいセッションの停止通知が届く。
    reader.onViewportSettled(snap(1), 200, (top: 0, bottom: 19));
    await advance(tester, const Duration(milliseconds: 400));
    // 古い往復はまだ gate 待ちなので、まだ2本目は始まらない
    // （single-flight）。
    expect(runner.calls, 1);

    // 古い往復が完了する（token 不一致で結果は捨てられるが、finally は
    // token を問わず新しいセッションの pending を拾う）。
    runner.gate!.complete();
    await tester.pump();
    await tester.pump();

    // 開始間隔（2秒）経過後に新しい範囲を1回だけ取得する。
    await advance(tester, const Duration(seconds: 3));
    await tester.pump();
    expect(runner.calls, 2);
    // top=0,bottom=19 → offset = 200-1-19 = 180。
    expect(runner.offsetsPerCall.last, contains(180));
  });

  testWidgets('endSession 後、往復完了時に新しい往復は始まらない', (tester) async {
    runner.gate = Completer<void>();
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    reader.endSession();

    runner.gate!.complete();
    await tester.pump();
    await tester.pump();
    await advance(tester, const Duration(seconds: 3));
    await tester.pump();
    expect(runner.calls, 1); // 2本目は始まらない
  });

  testWidgets('取得済みの範囲は再取得しない', (tester) async {
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);
    // R=20（pane.rows）、表示範囲の行数も20（180..199）で R を超えない
    // ため単一窓。a = 200-1-199 = 0。
    expect(runner.offsetsPerCall.single, [0]);

    // 同じ範囲で再度止まる（2秒経過後）。
    await advance(tester, const Duration(seconds: 2));
    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    // offset 0 は取得済みなので窓が無く、往復しない。
    expect(runner.calls, 1);
  });

  testWidgets('truncated の窓（拒否された窓・出力量で入りきらなかった窓）は取得済みにせず、次に止まったとき再取得する', (
    tester,
  ) async {
    runner.onRun = (offsets) => ScrollbackLinksResult(
      windows: [
        for (final offset in offsets)
          ScrollbackLinkWindow(
            requestedOffset: offset,
            actualOffset: offset,
            hyperlinks: const PaneHyperlinks(
              frameWidth: 80,
              frameHeight: 20,
              links: [],
              rowFingerprints: {},
              truncated: true,
            ),
          ),
      ],
      restore: ScrollbackLinkRestore.exact,
    );
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);
    expect(cache.hasFetched(0), isFalse);

    // 同じ範囲で再度止まる（2秒経過後）: truncated の窓は再取得される。
    await advance(tester, const Duration(seconds: 2));
    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 2);
    expect(runner.offsetsPerCall.last, [0]);

    // 新しい停止が無ければ、時間が経っても再取得しない。
    await advance(tester, const Duration(seconds: 10));
    await tester.pump();
    expect(runner.calls, 2);
  });

  testWidgets('表示範囲が R 行を超えないときは単一窓', (tester) async {
    final reader = makeReader();
    // R=20（既定）、top=0..19（表示範囲20行）は R を超えないため単一窓。
    // a = 200-1-19 = 180。
    reader.onViewportSettled(snap(1), 200, (top: 0, bottom: 19));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.offsetsPerCall.single, [180]);
  });

  testWidgets('表示範囲が R 超 2R 以下のときは2窓', (tester) async {
    // R=10（pane の viewport 行数）。表示範囲15行（top=185..199）は
    // R(10) を超え 2R(20) 以下のため、a, a+R の2窓のみ（3窓目 a+2R は
    // 要求しない）。
    rows = 10;
    final reader = makeReader();
    reader.onViewportSettled(snap(1), 200, (top: 185, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    // a = 200-1-199 = 0, a+R = 10。
    expect(runner.offsetsPerCall.single, [0, 10]);
  });

  testWidgets('複数窓: 表示範囲が 2R を超えるときは a, a+R, a+2R を要求する（上限3個）', (tester) async {
    // R=10（pane の viewport 行数）。表示範囲100行（top=100..199）は
    // 2R(20) を超えるため、a, a+R, a+2R の3窓を要求する
    // （1回で取る窓は最大3＝viewport の行数×3行まで）。
    rows = 10;
    final reader = makeReader();
    reader.onViewportSettled(snap(1), 1000, (top: 100, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    // a = 1000-1-199 = 800, a+R=810, a+2R=820（いずれも lineCount 未満）。
    expect(runner.offsetsPerCall.single, [800, 810, 820]);
  });

  testWidgets('表示範囲が 3R を超えても3窓のまま増えない（上限3）', (tester) async {
    // R=10。表示範囲35行（3R=30を超える）でも、窓は a, a+R, a+2R の
    // 3個のまま（4個目 a+3R は要求しない）。
    rows = 10;
    final reader = makeReader();
    reader.onViewportSettled(snap(1), 1000, (top: 165, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    // a = 1000-1-199 = 800, a+R=810, a+2R=820。
    expect(runner.offsetsPerCall.single, [800, 810, 820]);
  });

  testWidgets('窓タイリングの R は、直近の helper 実測 frame 行数'
      '（ScrollbackLinkCache.lastFrameRows）があればそれを最優先する'
      '（pane.rows=20 のままでも無視されること）', (tester) async {
    // helper が実際に使った行数（7）を直接キャッシュへ設定する
    // （直近の往復で判明した値、という想定）。
    cache.resetIfNeeded(identity: identity, generation: 1);
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 999,
      linksByBodyLine: const {},
      frameRows: 7,
    );
    final reader = makeReader();

    // pane.rows は既定の20のまま（_resolveWindowRowSpan が lastFrameRows
    // を優先するなら無視されるはず）。表示範囲100行は R=7 なら上限3窓
    // （ceil(100/7)=15 を3で頭打ち）、間隔は7。
    reader.onViewportSettled(snap(1), 1000, (top: 100, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();

    // a = 1000-1-199 = 800。間隔7で a, a+7, a+14。
    expect(runner.offsetsPerCall.single, [800, 807, 814]);
  });

  testWidgets('窓タイリングの R は、lastFrameRows が無く viewportRows があればそれを'
      '使う（pane.rows=20 のままでも無視される'
      'こと）', (tester) async {
    viewportRows = 5;
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 1000, (top: 100, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();

    // a = 1000-1-199 = 800。間隔5で a, a+5, a+10。
    expect(runner.offsetsPerCall.single, [800, 805, 810]);
  });

  testWidgets('viewportRows が 0 以下でも素通しされるが、最終的に pane.rows へ'
      'フォールバックする（viewportRows を作る parser 側では正規化せず、0 もそのまま渡ってくる前提）', (
    tester,
  ) async {
    viewportRows = 0;
    rows = 10;
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 1000, (top: 100, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();

    // viewportRows=0 は無効として読み飛ばし、pane.rows=10 を使う。
    expect(runner.offsetsPerCall.single, [800, 810, 820]);
  });

  testWidgets('helper が実際に使った frame 行数が requested rows と異なっても、次回の'
      '窓タイリングにギャップが出ない（helper が実 '
      'pty サイズを優先し、Dart が要求した rows=20 とは違う7行で返してきた'
      '場合、次の往復はその7行基準で隙間なく並ぶ）', (tester) async {
    bodyLines = ['alpha', 'bravo', 'charlie', 'delta', 'echo'];
    // helper は要求（rows=20）とは無関係に、実際に使った行数7を返す。
    runner.onRun = (offsets) => ScrollbackLinksResult(
      windows: [
        for (final offset in offsets)
          ScrollbackLinkWindow(
            requestedOffset: offset,
            actualOffset: offset,
            hyperlinks: const PaneHyperlinks(
              frameWidth: 80,
              frameHeight: 7, // 要求 rows=20 とは異なる実測値
              links: [],
              rowFingerprints: {},
              truncated: false,
            ),
          ),
      ],
      restore: ScrollbackLinkRestore.exact,
    );
    final reader = makeReader();

    // 1回目: 単一窓（表示範囲20行は pane.rows=20 を超えない）。
    reader.onViewportSettled(snap(1), 1000, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.offsetsPerCall.single, [800]);
    expect(cache.lastFrameRows, 7);

    // 2回目: 1回目の実測（frameRows=7）が次の窓計算に反映され、間隔7で
    // 隙間なく並ぶ（pane.rows=20 を使った場合の間隔20にはならない）。
    // 窓の計算自体は [800, 807, 814] だが、800 は1回目で取得済みのため
    // 「取得済みの範囲は再取得しない」ため除外され、実際に要求
    // するのは [807, 814] になる（間隔7は変わらない＝ギャップなし）。
    reader.onViewportSettled(snap(1), 1000, (top: 100, bottom: 199));
    await advance(tester, const Duration(seconds: 2));
    await tester.pump();
    expect(runner.offsetsPerCall.last, [807, 814]);
  });

  testWidgets('直近に採用した k（lastK）が次回の窓計算に引き継がれる（k_est）', (tester) async {
    // 前回のスナップショットで採用済みの k=3 を直接キャッシュへ設定する
    // （k_est は同じスナップショットで最後に採用した k）。
    cache.resetIfNeeded(identity: identity, generation: 1);
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 999,
      linksByBodyLine: const {},
      k: 3,
    );
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();

    // a = (200-1-199) + k_est(3) = 3（表示範囲20行は R=20 を超えないため
    // 単一窓）。offset 999 は既に取得済みだが、offset 3 は未取得のため
    // 往復する。
    expect(runner.offsetsPerCall.single, [3]);
  });

  testWidgets('整列に成功した窓の結果がキャッシュへ反映される', (tester) async {
    bodyLines = ['alpha', 'bravo', 'charlie', 'delta', 'echo'];
    runner.onRun = (offsets) => ScrollbackLinksResult(
      windows: [
        ScrollbackLinkWindow(
          requestedOffset: offsets.single,
          actualOffset: offsets.single,
          hyperlinks: PaneHyperlinks(
            frameWidth: 80,
            frameHeight: 5,
            links: const [
              PaneHyperlink(
                url: 'https://example.test',
                ranges: [PaneHyperlinkRange(row: 2, startCol: 0, endCol: 6)],
              ),
            ],
            rowFingerprints: {
              for (var i = 0; i < 5; i++)
                i: HerdrRowFingerprint.rowFingerprint(bodyLines[i])!,
            },
            truncated: false,
          ),
        ),
      ],
      restore: ScrollbackLinkRestore.exact,
    );
    var updateCount = 0;
    updates.add(() => updateCount++);
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 5, (top: 0, bottom: 4));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();

    expect(updateCount, 1);
    expect(cache.generation, 1);
    // frameRow=2, windowOffset=0, frameRows=5, bodyLineCount=5, k=0 →
    // d = 0+(5-1-2)=2, i=(5-1-2)+0=2 → charlie 行。
    expect(cache.linksByBodyLine[2], isNotNull);
    expect(cache.linksByBodyLine[2]!.single.url, 'https://example.test');
  });
}
