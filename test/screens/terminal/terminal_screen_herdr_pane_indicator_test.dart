import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_pane.dart';
import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('TerminalScreen herdr pane indicator (Phase 3)', () {
    // pane indicator 用 pump ヘルパー: snapshot（layout 付き）を 1 つ以上供給する。
    // [snapshotQueue] を渡すと [`_fetchHerdrSessions`] の force 再取得が順に消費する
    // （接続時 resolve → setup indicator fetch（cache ヒット）→ 各 force 再取得）。
    Future<void> pumpHerdrForIndicator(
      WidgetTester tester, {
      required String snapshotFixture,
      List<String>? snapshotQueue,
    }) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': snapshotFixture,
          'herdr pane read': 'content\n',
        },
        execOutputQueues: snapshotQueue == null
            ? const {}
            : {'herdr api snapshot': snapshotQueue},
        settle: false,
      );
      // 接続時 resolve + setup の indicator 設定 + 初回ポーリングを進める。
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 描画中の _PaneLayoutPainter（widget ツリーの CustomPaint）を 1 つ取得する。
    CustomPainter panePainterOf(WidgetTester tester) =>
        tester.widget<CustomPaint>(paneIndicatorPainter().first).painter!;

    // painter に描画させ、drawRect された矩形一覧を返す（#18 正規化検証用）。
    List<Rect> paintedRects(CustomPainter painter, Size size) {
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, size);
      return canvas.invocations
          .where((inv) => inv.invocation.memberName == #drawRect)
          .map((inv) => inv.invocation.positionalArguments.first as Rect)
          .toList();
    }

    testWidgets('#8: herdr 接続 + 2 pane layout で pane indicator が表示される', (
      tester,
    ) async {
      await pumpHerdrForIndicator(
        tester,
        snapshotFixture: kHerdrTwoPaneLayoutSnapshotFixture,
      );
      expect(paneIndicatorPainter(), findsWidgets);
      // painter の入力は 2 pane（w1:p1 / w1:p2）。
      final painter = panePainterOf(tester);
      final panes = List<MultiplexerPane>.from((painter as dynamic).panes);
      expect(panes, hasLength(2));
      expect(panes.map((p) => p.id).toSet(), {'w1:p1', 'w1:p2'});

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('#9: indicator タップで herdr 用 pane セレクタ（Select Pane）が開く', (
      tester,
    ) async {
      await pumpHerdrForIndicator(
        tester,
        snapshotFixture: kHerdrTwoPaneLayoutSnapshotFixture,
      );

      // indicator をタップ → _showHerdrPaneSelector（herdr 固有・HIGH-4）
      await tester.tap(paneIndicatorPainter());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // herdr 固有要素で判定: Select Pane タイトル + MultiplexerPaneTile キー。
      // （tmux 用 _showPaneSelector と誤同定しない粒度）
      expect(find.text('Select Pane'), findsOneWidget);
      expect(find.byKey(const ValueKey('mux-sel-pane-w1:p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('mux-sel-pane-w1:p2')), findsOneWidget);
      // A10: pane 表示名は cwd（/a・/b）優先。
      expect(find.text('/a'), findsOneWidget);
      expect(find.text('/b'), findsOneWidget);

      // シートを閉じて pending タイマーを消化。
      await tester.tapAt(const Offset(500, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('#10: 単一 pane では indicator 非表示（panes<=1 ガード）', (tester) async {
      await pumpHerdrForIndicator(
        tester,
        snapshotFixture: kHerdrLargeLayoutSnapshotFixture,
      );
      expect(paneIndicatorPainter(), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('#11: zoom 中も非 zoom 下地の 2 pane 分割が描画される', (tester) async {
      await pumpHerdrForIndicator(
        tester,
        snapshotFixture: kHerdrZoomedTwoPaneSnapshotFixture,
      );
      expect(paneIndicatorPainter(), findsWidgets);
      // zoom 特別対応なし: 下地（非 zoom rect）の 2 pane が描画される。
      final painter = panePainterOf(tester);
      final panes = List<MultiplexerPane>.from((painter as dynamic).panes);
      expect(panes, hasLength(2));
      expect(panes[0].width, 100, reason: '非 zoom 下地の rect が使われること');

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('#12: mutation 後同期で同一 id・rect 変化（resize）が再描画される', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        execOutputQueues: {
          // 接続時 resolve（force）: 2 pane → mutation 後同期（force）: resize 版
          'herdr api snapshot': [
            kHerdrTwoPaneLayoutSnapshotFixture,
            kHerdrIndicatorResizeSnapshotFixture,
          ],
        },
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 100));

      final painterBefore = panePainterOf(tester);
      final panesBefore = List<MultiplexerPane>.from(
        (painterBefore as dynamic).panes,
      );
      expect(panesBefore.first.width, 100);

      // mutation 後同期（H5/T18 単一経路）: force 再取得 → 同一 pane 再解決（switch なし）
      final dynamic state = tester.state(find.byType(TerminalScreen));
      await state.syncAfterHerdrMutationForTesting(
        eventLabel: 'test mutation sync',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // indicator の panes が新レイアウト（同一 id・rect 変化）へ更新される。
      final painterAfter = panePainterOf(tester);
      final panesAfter = List<MultiplexerPane>.from(
        (painterAfter as dynamic).panes,
      );
      expect(panesAfter, hasLength(2));
      expect(panesAfter.first.id, 'w1:p1');
      expect(
        panesAfter.first.width,
        130,
        reason: '同一 id でも rect 変化（resize）が indicator に反映されること',
      );
      // shouldRepaint: MultiplexerPane.== は id のみ比較だが、rect 明示比較で true。
      expect(
        (painterAfter as dynamic).shouldRepaint(painterBefore),
        isTrue,
        reason: '同一 id・rect のみ変化でも shouldRepaint が true になること（B-2）',
      );
      // force 再取得が実 CLI で発行された（接続時 1 + mutation 後 1）。
      expect(
        client.execCommands
            .where((c) => c.contains('herdr api snapshot'))
            .length,
        greaterThanOrEqualTo(2),
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('#12b: mutation 後同期で pane 追加（2→3）が indicator に反映される', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrTwoPaneLayoutSnapshotFixture,
            kHerdrThreePaneLayoutSnapshotFixture,
          ],
        },
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 100));

      final panesBefore = List<MultiplexerPane>.from(
        (panePainterOf(tester) as dynamic).panes,
      );
      expect(panesBefore, hasLength(2));

      final dynamic state = tester.state(find.byType(TerminalScreen));
      await state.syncAfterHerdrMutationForTesting(
        eventLabel: 'test split sync',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final panesAfter = List<MultiplexerPane>.from(
        (panePainterOf(tester) as dynamic).panes,
      );
      expect(
        panesAfter,
        hasLength(3),
        reason: 'mutation（split）成功後の新レイアウトが indicator に反映されること',
      );
      expect(panesAfter.map((p) => p.id).toSet(), {'w1:p1', 'w1:p2', 'w1:p3'});

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('#13: 再接続後の同一 pane 再解決（switch なし）でも indicator が更新', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrTwoPaneLayoutSnapshotFixture, // 接続時 resolve
            kHerdrIndicatorResizeSnapshotFixture, // 再接続後再解決
          ],
        },
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 100));

      final panesBefore = List<MultiplexerPane>.from(
        (panePainterOf(tester) as dynamic).panes,
      );
      expect(panesBefore.first.width, 100);

      // 再接続成功（同一 pane に再解決 → 切替コミットなしの早期 return 経路）。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;
      notifier.onReconnectSuccess?.call();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // 再接続中は notifier が null クリアされるが、再解決（早期 return 経路）の
      // 共通末尾で再設定され、新レイアウトが反映される。
      expect(paneIndicatorPainter(), findsWidgets);
      final panesAfter = List<MultiplexerPane>.from(
        (panePainterOf(tester) as dynamic).panes,
      );
      expect(
        panesAfter.first.width,
        130,
        reason: '同 pane 再解決（switch なし）でも indicator が更新されること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('#14: layout 無し（全 pane rect 0）では indicator 非表示（空ボックスなし）', (
      tester,
    ) async {
      // kHerdrSnapshotFixture: layout なし → 全 pane rect 0。
      await pumpHerdrForIndicator(
        tester,
        snapshotFixture: kHerdrSnapshotFixture,
      );
      expect(
        paneIndicatorPainter(),
        findsNothing,
        reason: '全 pane rect 0 では空の半透明ボックスを表示しない（HIGH-2）',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('#18: 非 0 起点 rect（x:26/y:1）でも 0 起点へ正規化されて描画される', (
      tester,
    ) async {
      await pumpHerdrForIndicator(
        tester,
        snapshotFixture: kHerdrMinNormalizeSnapshotFixture,
      );
      expect(paneIndicatorPainter(), findsWidgets);

      final painter = panePainterOf(tester);
      // 入力は非 0 起点のまま（正規化は paint 内・min を 0 へ引く）。
      final panes = List<MultiplexerPane>.from((painter as dynamic).panes);
      expect(panes, hasLength(2));
      expect(panes.first.left, 26);

      // 描画矩形の検証: 最初の pane の left/top が 0 起点化され、全矩形が領域内。
      final rects = paintedRects(painter, const Size(44, 44));
      expect(rects, isNotEmpty);
      expect(
        rects.first.left,
        0,
        reason: 'min（x:26）が引かれ 0 起点で描画されること（非正規化なら 26 分ずれる）',
      );
      expect(rects.first.top, 0, reason: 'min（y:1）が引かれ 0 起点で描画されること');
      for (final r in rects) {
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.top, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(44));
        expect(r.bottom, lessThanOrEqualTo(44));
      }

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('#17: セレクタで別 pane へ切替すると indicator が切替後の状態へ更新', (tester) async {
      await pumpHerdrForIndicator(
        tester,
        snapshotFixture: kHerdrTwoPaneLayoutSnapshotFixture,
      );

      // 初期: activePaneId = w1:p1
      var painter = panePainterOf(tester);
      expect((painter as dynamic).activePaneId, 'w1:p1');

      // pane セレクタを開いて w1:p2 を選択（_herdrSelectPane → _switchHerdrTarget →
      // setter が switch 後に呼ばれる・CRITICAL-1 の順序検証）。
      await tester.tap(paneIndicatorPainter());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Pane'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mux-sel-pane-w1:p2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // switch 後の差し込みで activePaneId が更新される（旧値残留 = stale）。
      painter = panePainterOf(tester);
      expect(
        (painter as dynamic).activePaneId,
        'w1:p2',
        reason: 'セレクタ切替（switch 後 setter）で indicator が更新されること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets(
      '#19: 接続直後に layout 未取得でも poll 駆動の snapshot 再取得後に indicator が表示',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          // TTL を fake time（tester.pump で進む clock）で駆動し、poll 経路の
          // snapshot 再取得（接続後 5s 以降）をテスト内で再現する。
          herdrCacheClock: () => tester.binding.clock.now(),
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          execOutputQueues: {
            // 接続時 resolve（fetch#1）+ その後の cache 再取得は FIFO で消費される。
            'herdr api snapshot': [
              kHerdrTwoPaneNoLayoutSnapshotFixture, // 接続直後: layout 未取得
              kHerdrTwoPaneLayoutSnapshotFixture, // poll 駆動再取得後: layout あり
            ],
          },
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        // 接続直後は layout 無し（全 rect 0）→ HIGH-2 ガードで非表示。
        expect(
          paneIndicatorPainter(),
          findsNothing,
          reason: '接続直後（layout 未取得）は rect 0 により非表示',
        );

        // cache TTL(5s) を超えるまで時間を進め、poll 駆動の snapshot 再取得を走らせて
        // layout 付き snapshot がキャッシュへ入るようにする（既存 poll 経路の定期再取得）。
        await tester.pump(const Duration(seconds: 7));
        await tester.pump();

        // 前提検証: poll 経路の cache 再取得で 2 件目の snapshot が実際に取得された。
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final sshNotifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        final client = sshNotifier.client as FakeSshClient;
        final snapshotExecs = client.execCommands
            .where((c) => c.contains('herdr api snapshot'))
            .length;
        expect(
          snapshotExecs,
          greaterThanOrEqualTo(2),
          reason: 'poll 駆動で 2 件目の snapshot（layout 付き）が取得されていること',
        );

        // 再取得後の snapshot には layout があるため、indicator が表示されるべき。
        // （現行コードは poll 経路で notifier を再設定しないため RED になる想定・#19）
        expect(
          paneIndicatorPainter(),
          findsWidgets,
          reason: 'layout 付き snapshot が届いたら indicator が表示されること',
        );
        final painter = panePainterOf(tester);
        final panes = List<MultiplexerPane>.from((painter as dynamic).panes);
        expect(panes, hasLength(2));
        expect(panes.first.width, 100, reason: 'layout の rect が反映されること');

        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  });
}
