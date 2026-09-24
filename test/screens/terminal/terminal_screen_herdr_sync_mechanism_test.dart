import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/tmux/pane_navigator.dart';
import 'package:flutter_muxpod/services/tmux/commands/layout.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('T18: mutation 後ツリー同期の単一化（H5/S4）', () {
    testWidgets('syncAfterHerdrMutation 単一経路: force 再取得後にターゲットが変化すると'
        '_switchHerdrTarget で表示切替される', (tester) async {
      final client = await pumpHerdrTerminal(
        tester,
        // 接続時: w1:p1 / 単一経路の force 再取得: w1:p2 のみ（w1:p1 消滅）。
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotFixture,
            kHerdrSnapshotPane2Fixture,
          ],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.syncAfterHerdrMutationForTesting(
        eventLabel: 'test mutation sync',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();

      // 単一経路: force 再取得（エポック++）→ 再解決 → ターゲット変化時のみ切替。
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('test mutation sync -> w1:p2')),
        isTrue,
        reason: '再解決で別 pane に決まると同期イベントが記録されること',
      );
      expect(
        events.any((e) => e.contains('switch target -> w1:p2')),
        isTrue,
        reason: 'ターゲット変化時は _switchHerdrTarget（切替コミット）が呼ばれること',
      );
      // 表示も w1:p2 に更新される（ブレッドクラム 'Pane 2'）。
      expect(find.text('Pane 2'), findsOneWidget);
      // force 再取得の実 CLI（接続時 1 回 + 単一経路 1 回）。
      expect(
        client.execCommands
            .where((c) => c.contains('herdr api snapshot'))
            .length,
        greaterThanOrEqualTo(2),
      );

      // SnackBar タイマー / ポーリングを消化してクリーンに終了。
      await tester.pump(const Duration(milliseconds: 200));
    });
    testWidgets('syncAfterHerdrMutation 単一経路: ターゲットが同一なら切替コミットなし', (
      tester,
    ) async {
      await pumpHerdrTerminal(
        tester,
        // force 再取得でも w1:p1 が残る → 表示継続（切替なし）。
        execOutputQueues: {
          'herdr api snapshot': [kHerdrSnapshotFixture, kHerdrSnapshotFixture],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.syncAfterHerdrMutationForTesting(
        eventLabel: 'test mutation sync',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();

      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('switch target')),
        isFalse,
        reason: '同一 pane へは切替コミットを発行しない（チラつき防止）',
      );
      expect(find.text('Pane 1'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
    });
    testWidgets('split 成功後は単一経路（force 再取得）で反映され、現在 pane が残れば表示継続', (
      tester,
    ) async {
      final client = await pumpHerdrTerminal(
        tester,
        // split 応答は layout なし（T0 実測 6-a）→ force 再取得で反映する。
        // split 後も w1:p1 が残る snapshot → 表示継続（切替なし）。
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotFixture,
            kHerdrTwoPanesSnapshotFixture,
          ],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.splitPaneForTesting(
        'w1:p1',
        SplitDirection.horizontal,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();

      // PaneWriter 経由の split コマンド。
      expect(
        client.execCommands.any(
          (c) => c == 'herdr pane split w1:p1 --direction right',
        ),
        isTrue,
        reason: 'split は PaneWriter.splitPane（herdr pane split）で実行されること',
      );
      // 単一経路の force 再取得（接続時 1 回 + split 後 1 回）。
      expect(
        client.execCommands
            .where((c) => c.contains('herdr api snapshot'))
            .length,
        greaterThanOrEqualTo(2),
        reason: 'split 成功後は _syncAfterHerdrMutation（force 再取得）が走ること',
      );
      // 現在 pane（w1:p1）が snapshot に残るため切替なし・表示継続。
      final events = herdrSwitchEvents(tester);
      expect(events.any((e) => e.contains('switch target')), isFalse);
      expect(find.text('Pane 1'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
    });
    testWidgets('focus 成功後は単一経路（force 再取得）で同期され、フォーカス先の pane へ表示が切り替わる', (
      tester,
    ) async {
      final client = await pumpHerdrTerminal(
        tester,
        // 接続時: w1:t1（w1:p1）/ focus 後の force 再取得: 旧 pane は残存しつつ
        // フォーカスは w1:p2 へ移動（S0 実測形状）。スワイプ（方向フォーカス）は
        // フォーカス移動を伴う操作のため followBackendFocus で追従すること。
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotFixture,
            kHerdrNewTabActiveSnapshotFixture,
          ],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.focusHerdrPaneDirectionForTesting(
        SwipeDirection.right,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();

      expect(
        client.execCommands.any(
          (c) => c == 'herdr pane focus --direction right --pane w1:p1',
        ),
        isTrue,
        reason: 'herdr の方向フォーカスは PaneWriter.focusPaneDirection で実行されること',
      );
      expect(
        client.execCommands
            .where((c) => c.contains('herdr api snapshot'))
            .length,
        greaterThanOrEqualTo(2),
        reason: 'focus 成功後も _syncAfterHerdrMutation 単一経路が走ること',
      );
      // スワイプはフォーカス移動を伴うため、旧 pane（w1:p1）が snapshot に
      // 残存していても followBackendFocus でフォーカス先（w1:p2）へ表示切替。
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('focus sync -> w1:p2')),
        isTrue,
        reason: 'focus 後は _syncAfterHerdrMutation（focus sync）が走ること',
      );
      expect(
        events.any((e) => e.contains('switch target -> w1:p2')),
        isTrue,
        reason: '方向フォーカスは snapshot の focused pane へ表示を追従すること',
      );
      expect(find.text('Pane 2'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
    });
    testWidgets('rename pane 成功後は単一経路（force 再取得）で同期される（Q-02）', (tester) async {
      final client = await pumpHerdrTerminal(
        tester,
        execOutputQueues: {
          'herdr api snapshot': [kHerdrSnapshotFixture, kHerdrSnapshotFixture],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.renameHerdrPaneForTesting('w1:p1', 'editor');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();

      expect(
        client.execCommands.any((c) => c == "herdr pane rename w1:p1 'editor'"),
        isTrue,
        reason:
            'pane rename は PaneWriter.renamePane（herdr pane rename）で実行されること',
      );
      expect(
        client.execCommands
            .where((c) => c.contains('herdr api snapshot'))
            .length,
        greaterThanOrEqualTo(2),
        reason: 'rename pane 成功後も _syncAfterHerdrMutation 単一経路が走ること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });
    testWidgets('zoom 成功後は単一経路（force 再取得）で同期される（Q-02）', (tester) async {
      final client = await pumpHerdrTerminal(
        tester,
        execOutputQueues: {
          'herdr api snapshot': [kHerdrSnapshotFixture, kHerdrSnapshotFixture],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.zoomHerdrPaneForTesting('w1:p1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();

      expect(
        client.execCommands.any(
          (c) => c == 'herdr pane zoom --pane w1:p1 --toggle',
        ),
        isTrue,
        reason: 'zoom は PaneWriter.zoomPane（herdr pane zoom --toggle）で実行されること',
      );
      expect(
        client.execCommands
            .where((c) => c.contains('herdr api snapshot'))
            .length,
        greaterThanOrEqualTo(2),
        reason: 'zoom 成功後も _syncAfterHerdrMutation 単一経路が走ること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
