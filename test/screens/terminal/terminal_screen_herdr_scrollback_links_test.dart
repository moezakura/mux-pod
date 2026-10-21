import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart'
    show PaneHyperlinks;
import 'package:flutter_muxpod/services/herdr/herdr_models.dart'
    show HerdrStatus;
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart'
    show
        HerdrScrollbackLinkHelperRunner,
        ScrollbackLinksResult,
        ScrollbackLinkRestore,
        ScrollbackLinkWindow;
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';
import 'helpers/scroll_send_test_helpers.dart' show enterMode, mode;
import 'helpers/herdr_experimental_settings.dart';

/// [HerdrScrollbackLinkHelperRunner] の fake。呼び出し引数
/// （pane/cols/offsets）を記録する。アライン（本文行との対応づけ）成否は
/// このテストの検証対象外のため、返す窓のリンクは常に空にする
/// （widget テストで確認するのは「fake runner が受け取った引数」と
/// 「bodyLinesFor が空でない実際の本文を渡していること」の2点）。
class _FakeScrollbackLinkRunner implements HerdrScrollbackLinkHelperRunner {
  int calls = 0;
  String? lastPaneId;
  int? lastCols;
  List<int>? lastOffsetsFromBottom;

  @override
  Future<ScrollbackLinksResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required List<int> offsetsFromBottom,
    Duration? timeout,
  }) async {
    calls++;
    lastPaneId = paneId;
    lastCols = cols;
    lastOffsetsFromBottom = offsetsFromBottom;
    return ScrollbackLinksResult(
      windows: [
        for (final offset in offsetsFromBottom)
          ScrollbackLinkWindow(
            requestedOffset: offset,
            actualOffset: offset,
            hyperlinks: PaneHyperlinks(frameWidth: cols, frameHeight: 0),
          ),
      ],
      restore: ScrollbackLinkRestore.exact,
    );
  }
}

void main() {
  group('TerminalScreen herdr caret (Phase 4)', () {
    group('herdr スクロールモードのリンク読取', () {
      testWidgets('select モードでスクロール確定すると fake runner が'
          'pane/cols/offsets 付きで呼ばれ、bodyLinesFor は実際の本文を渡す', (tester) async {
        final runner = _FakeScrollbackLinkRunner();
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': 'hello\n',
          },
          herdrScrollbackLinkHelperRunner: runner,
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        await enterMode(tester, 'Select Mode');
        expect(mode(tester), TerminalMode.select);
        // AnsiTextView が select モードの内容（herdr pane read の結果）で
        // 再描画され _lastBodyLineTexts が計算されるのを待つ。
        await tester.pump(const Duration(milliseconds: 500));

        final dynamic state = tester.state(find.byType(TerminalScreen));
        final List<String> bodyLines = state
            .scrollbackLinkBodyLinesForTesting();
        expect(
          bodyLines,
          isNotEmpty,
          reason: 'bodyLinesFor が空配列のまま通ってしまう偽の GREEN でないこと',
        );
        expect(
          bodyLines.any((line) => line.contains('hello')),
          isTrue,
          reason: 'bodyLinesFor は表示中の実際の本文（"hello"）を渡していること',
        );

        final context = tester.element(find.byType(AnsiTextView));
        state.notifyViewportSettledForTesting(context);
        // 停止待ち 400ms を超えて進め、往復を発生させる。
        await tester.pump(const Duration(milliseconds: 500));

        // select モード突入自体でも1回自動で往復するため（
        // loadHistoryForScroll）、少なくとも1回は呼ばれていることを見る
        // （厳密に1回であることは検証対象外。往復内容・引数を見る）。
        expect(
          runner.calls,
          greaterThanOrEqualTo(1),
          reason: '停止待ち後に往復が発生していること',
        );
        expect(
          runner.lastPaneId,
          'w1:p1',
          reason: 'currentScrollbackLinkPane() が現在の pane id を渡していること',
        );
        expect(
          runner.lastCols,
          80,
          reason:
              'currentScrollbackLinkPane() が layout rect の幅を渡していること'
              '（kHerdrSnapshotWithLayoutFixture の w1:p1 rect 幅）',
        );
        expect(runner.lastOffsetsFromBottom, isNotNull);
        expect(
          runner.lastOffsetsFromBottom!,
          isNotEmpty,
          reason: '窓（offsetsFromBottom）が計算され runner に渡っていること',
        );
      });

      testWidgets('select モードを抜けると保留中の往復が cancelPending で抑止される', (
        tester,
      ) async {
        final runner = _FakeScrollbackLinkRunner();
        // 1回目と同じ窓を2回目にも要求
        // すると `ScrollbackLinkCache.hasFetched` に弾かれ、endSession の
        // 配線の有無に関わらず往復 0 回になり見分けがつかない。多めの行数
        // を用意し、[jumpToLineFromTopForTesting] で実スクロール位置を
        // 変えることで、2回目は確実に未取得の窓を要求させる。
        //
        // さらに [HerdrScrollbackLinkReader] の開始間隔 2 秒
        // （`minInterval`）ゲートは実時間で判定される（`herdrCacheClock`
        // を渡さない限り）。`tester.pump` は仮想クロックしか進めないため、
        // 偽の時計を注入し pump と同じ幅だけ進める。
        var fakeNow = DateTime(2025, 1, 1);
        final lines = List.generate(500, (i) => 'line$i').join('\n');
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': '$lines\n',
          },
          herdrScrollbackLinkHelperRunner: runner,
          herdrCacheClock: () => fakeNow,
          settle: false,
        );

        Future<void> pumpVirtual(Duration d) async {
          fakeNow = fakeNow.add(d);
          await tester.pump(d);
        }

        await pumpVirtual(const Duration(milliseconds: 100));

        await enterMode(tester, 'Select Mode');
        expect(mode(tester), TerminalMode.select);
        // select モード突入自体の自動往復（loadHistoryForScroll）を
        // 完了させてから基準値を取る。
        await pumpVirtual(const Duration(milliseconds: 500));
        final callsAfterEntry = runner.calls;

        final dynamic state = tester.state(find.byType(TerminalScreen));
        // 実スクロール位置を中間の行へ移し、1回目とは異なる（未取得の）
        // 窓を要求させる。
        state.jumpToLineFromTopForTesting(250);
        await pumpVirtual(const Duration(milliseconds: 1));
        final context = tester.element(find.byType(AnsiTextView));
        state.notifyViewportSettledForTesting(context);

        // 停止待ち 400ms が経つ前（=まだ往復が始まっていない）に select
        // モードを抜ける。TerminalModeController.onModeChanged →
        // root の wiring（select 以外へ遷移）→
        // HerdrScrollbackLinkReader.endSession（cancelPending 含む）を通る。
        // モード変更（applyNormal）は tap ハンドラ内で同期的に発生するため、
        // 400ms の debounce タイマーが発火する前に確実にキャンセルされる。
        await pumpVirtual(const Duration(milliseconds: 100));
        await enterMode(tester, 'Normal Mode');
        expect(mode(tester), TerminalMode.normal);

        // 停止待ち 400ms・開始間隔 2 秒のいずれも越えて進めても、
        // cancelPending 済みの保留は往復として実行されないこと。
        await pumpVirtual(const Duration(milliseconds: 2600));

        expect(
          runner.calls,
          callsAfterEntry,
          reason:
              'select モードを抜けた後は、抜ける直前に予約した保留中の取得が'
              'cancelPending で抑止され、開始間隔 2 秒・停止待ち 400ms を'
              '超えても、未取得の窓への追加の往復が発生しないこと'
              '（endSession/cancelPending の配線）',
        );
      });

      testWidgets('バックグラウンド遷移（AppLifecycleState.paused）で保留中の往復が'
          'cancelPending で抑止される（onPausePolling配線）', (tester) async {
        final runner = _FakeScrollbackLinkRunner();
        // 1回目の往復と同じ窓を2回目にも要求
        // すると `ScrollbackLinkCache.hasFetched` に弾かれ、配線の有無に
        // 関わらず往復 0 回になり見分けがつかない。多めの行数
        // （viewport に収まらない量）を用意し、[jumpToLineFromTopForTesting]
        // で実スクロール位置を変えることで、2回目は確実に未取得の窓を
        // 要求させる。
        //
        // さらに [HerdrScrollbackLinkReader] の開始間隔 2 秒
        // （`minInterval`）ゲートは実時間（`DateTime.now()`）で判定される
        // （clock を渡さない限り）。`tester.pump` が進めるのはタイマー用の
        // 仮想クロックのみで実時間は進まないため、テスト内で1回目に続けて
        // 2回目の往復を発生させるには、`herdrCacheClock` で偽の時計を注入し、
        // pump と同じ幅だけ進める必要がある（注入しないと、配線の有無に
        // 関わらず2回目の往復が永久に起きず見分けがつかない）。
        var fakeNow = DateTime(2025, 1, 1);
        final lines = List.generate(500, (i) => 'line$i').join('\n');
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': '$lines\n',
          },
          herdrScrollbackLinkHelperRunner: runner,
          herdrCacheClock: () => fakeNow,
          settle: false,
        );

        Future<void> pumpVirtual(Duration d) async {
          fakeNow = fakeNow.add(d);
          await tester.pump(d);
        }

        await pumpVirtual(const Duration(milliseconds: 100));

        await enterMode(tester, 'Select Mode');
        expect(mode(tester), TerminalMode.select);
        // select モード突入自体の自動往復（loadHistoryForScroll）を
        // 完了させてから基準値を取る。
        await pumpVirtual(const Duration(milliseconds: 500));
        final callsAfterEntry = runner.calls;

        final dynamic state = tester.state(find.byType(TerminalScreen));
        // 実スクロール位置を中間の行へ移し、1回目とは異なる（未取得の）
        // 窓を要求させる。
        state.jumpToLineFromTopForTesting(250);
        await pumpVirtual(const Duration(milliseconds: 1));
        final context = tester.element(find.byType(AnsiTextView));
        state.notifyViewportSettledForTesting(context);

        // 停止待ち 400ms が経つ前（=まだ往復が始まっていない）にバック
        // グラウンドへ遷移する。_TerminalScreenState.didChangeAppLifecycle
        // State（terminal_screen.dart）の AppLifecycleState.paused 分岐 →
        // SessionLifecycle.pausePolling()（session_lifecycle.dart）の先頭 →
        // env.onPausePolling → HerdrScrollbackLinkReader.cancelPending。
        // didChangeAppLifecycleState の呼び出しは同期的なため、400ms の
        // debounce タイマーが発火する前に確実にキャンセルされる。
        await pumpVirtual(const Duration(milliseconds: 100));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await pumpVirtual(Duration.zero);

        // pausePolling は isActive（
        // `runtime.isInBackground`）を false→true にするだけでも、
        // HerdrScrollbackLinkReader._scheduleOrRunFetch の background-skip
        // により往復 0 回になる。これは cancelPending の配線が無くても
        // 成立してしまうため、配線の有無を見分けられない。400ms が経つ前に
        // resumed へ戻し、isActive を true に戻した状態で待ち時間を進める
        // ことで、cancelPending（配線）の有無だけで結果が分かれるようにする。
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpVirtual(Duration.zero);

        // 停止待ち 400ms・開始間隔 2 秒のいずれも越えて進めても、
        // cancelPending 済みの保留は往復として実行されないこと。
        await pumpVirtual(const Duration(milliseconds: 2600));

        expect(
          runner.calls,
          callsAfterEntry,
          reason:
              'バックグラウンド遷移直前に予約した保留中の取得が'
              'cancelPending で抑止され、resumed 復帰後に isActive が true に'
              '戻り、開始間隔 2 秒・停止待ち 400ms を超えても、未取得の窓への'
              '追加の往復が発生しないこと（onPausePolling の配線）',
        );
      });

      testWidgets('切断操作（Disconnect確認）で保留中の往復が cancelPending で'
          '抑止される（onDisconnect配線）', (tester) async {
        final runner = _FakeScrollbackLinkRunner();
        // 1回目と同じ窓を2回目にも要求すると
        // `ScrollbackLinkCache.hasFetched` に弾かれ、配線の有無に関わらず
        // 往復 0 回になり見分けがつかない。多めの行数を用意し、
        // [jumpToLineFromTopForTesting] で実スクロール位置を変えることで、
        // 2回目は確実に未取得の窓を要求させる。
        //
        // また [HerdrScrollbackLinkReader] の開始間隔 2 秒（`minInterval`）
        // ゲートは実時間（`DateTime.now()`）で判定される（clock を渡さない
        // 限り）。ここでは切断確認ダイアログの Close を押した後、画面が
        // dispose される前の短い実時間の猶予（後述）しかないため、
        // `herdrCacheClock` の偽の時計を先に大きく進めておくことで、
        // 停止待ち 400ms 分の実 pump だけで開始間隔ゲートも同時に満たす。
        var fakeNow = DateTime(2025, 1, 1);
        final lines = List.generate(500, (i) => 'line$i').join('\n');
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': '$lines\n',
          },
          herdrScrollbackLinkHelperRunner: runner,
          herdrCacheClock: () => fakeNow,
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        await enterMode(tester, 'Select Mode');
        expect(mode(tester), TerminalMode.select);
        await tester.pump(const Duration(milliseconds: 500));
        final callsAfterEntry = runner.calls;

        final dynamic state = tester.state(find.byType(TerminalScreen));
        // 実スクロール位置を中間の行へ移し、1回目とは異なる（未取得の）
        // 窓を要求させる。
        state.jumpToLineFromTopForTesting(250);
        await tester.pump();

        // 設定メニュー →「Disconnect」→ 確認ダイアログを開くところまでを
        // 先に済ませておく（メニュー・ダイアログの開閉アニメーションの
        // 時間経過を、停止待ち 400ms の計測が始まる前に消費させる）。
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Disconnect'));
        await tester.pumpAndSettle();

        // ここから 400ms の停止待ちの計測を始める。
        final context = tester.element(find.byType(AnsiTextView));
        state.notifyViewportSettledForTesting(context);
        // 開始間隔 2 秒のゲートを、pump の実時間を消費せずに満たす
        // （後続の 420ms の pump だけで停止待ち 400ms の debounce タイマー
        // と両方を同時に満たすため）。
        fakeNow = fakeNow.add(const Duration(seconds: 3));

        // 確認ダイアログの「Close」を押す。disconnect()
        // （session_connection.dart）冒頭の env.onDisconnect?.call() は
        // 同期的に走る（その後の SSH 切断・Navigator.pop は非同期）。
        await tester.tap(find.text('Close'));
        await tester.pump();

        // このまま pumpAndSettle や大きめの
        // duration で進めると、Navigator.pop によるページ遷移アニメーションが
        // 完了して TerminalScreen 自体が dispose される
        // （disposeCaches() → scrollbackLinkReader.dispose() という、
        // onDisconnect の配線とは別経路でも保留が消える）ため、
        // 「往復が起きない」ことが配線ではなく dispose によるものと
        // 区別できなくなる。実測（プローブテストで確認）では、この時点から
        // 420ms の pump では画面はまだ dispose されておらず、500ms の pump
        // では dispose される。420ms は 400ms の停止待ちを超えるため、
        // 画面が生きている（dispose 経由ではない）うちに、cancelPending
        // 配線の有無だけで結果が分かれる形で検証できる。
        await tester.pump(const Duration(milliseconds: 420));

        expect(
          find.byType(TerminalScreen).evaluate().isNotEmpty,
          isTrue,
          reason:
              'この時点ではまだ TerminalScreen が dispose されていないこと'
              '（dispose 経由の disposeCaches ではなく、onDisconnect の配線を'
              '検証するための前提）',
        );

        expect(
          runner.calls,
          callsAfterEntry,
          reason:
              '切断操作直前に予約した保留中の取得が cancelPending で'
              '抑止され、開始間隔 2 秒・停止待ち 400ms を超えても、未取得の'
              '窓への追加の往復が発生しないこと（onDisconnect の配線）',
        );
      });
    });
  });
}
