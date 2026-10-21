/// herdr_scrollback_link_reader.dart のテスト（世代ガードと中断）。
///
/// 再構築・スナップショット差し替え・再接続・`cancelPending`・`endSession`
/// で、古い往復の結果を捨てることと、往復が止まったままにならないことを
/// 確認する。共有する状態と補助関数は
/// `helpers/scrollback_link_reader_fixture.dart` にある。
library;

import 'dart:async';

import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_types.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/scrollback_link_reader_fixture.dart';

void main() {
  setUp(setUpScrollbackLinkReaderFixture);

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
}
