import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_muxpod/services/tmux/pane_navigator.dart';
import 'package:flutter_muxpod/services/tmux/commands/layout.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('T19: mutation 失敗の分類別通知（S4）', () {
    testWidgets('target-not-found（pane_not_found）は SnackBar 通知 + 単一経路で再同期する', (
      tester,
    ) async {
      final client = await pumpHerdrTerminal(
        tester,
        // split が pane_not_found で失敗 → 再同期（force 再取得）で w1:p2 へ。
        execOutputs: {'herdr pane split': kPaneNotFoundErrorFixture},
        execExitCodes: {'herdr pane split': 1},
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotFixture,
            kHerdrSnapshotPane2Fixture,
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
      await tester.pump(const Duration(milliseconds: 100));

      // 分類別通知（target-not-found）。
      expect(
        find.text('Target pane disappeared. Re-synced.'),
        findsOneWidget,
        reason: 'pane_not_found は「Target pane disappeared. Re-synced.」を通知する',
      );
      // 後続処理: 単一経路で強制再取得 → 再解決 → 別 pane へ遷移。
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('split re-sync -> w1:p2')),
        isTrue,
        reason: 'target-not-found 後は _syncAfterHerdrMutation で再同期されること',
      );
      expect(
        client.execCommands
            .where((c) => c.contains('herdr api snapshot'))
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(find.text('Pane 2'), findsOneWidget);

      // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets('close の pane_not_found も SnackBar 通知 + 再同期で復旧する', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr pane read': 'hello\n',
          'herdr pane close': kPaneNotFoundErrorFixture,
        },
        execExitCodes: {'herdr pane close': 1},
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrTwoPanesSnapshotFixture,
            kHerdrSnapshotPane2Fixture,
          ],
        },
        settle: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Pane'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Close Pane'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));

      // 対象が他端末で消えていた → 分類別通知 + 単一経路の再同期。
      expect(
        find.text('Target pane disappeared. Re-synced.'),
        findsOneWidget,
        reason: 'close の pane_not_found も target-not-found 分類で通知されること',
      );
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('close re-sync -> w1:p2')),
        isTrue,
        reason: 'close の target-not-found 後は _syncAfterHerdrMutation で再同期されること',
      );
      expect(
        client.execCommands
            .where((c) => c.contains('herdr api snapshot'))
            .length,
        greaterThanOrEqualTo(2),
      );

      // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets('focus の no_neighbor は情報 SnackBar「No pane in that direction」'
        'を表示し、force 再取得しない（T19/T20 no_neighbor 補完）', (tester) async {
      final client = await pumpHerdrTerminal(
        tester,
        // focus が隣接なし（changed:false + reason:no_neighbor）を返す。
        execOutputs: {'herdr pane focus': kFocusNoNeighborFixture},
      );

      // 発生前の snapshot 取得回数（接続時 1 回のみ）。
      final snapshotCountBefore = client.execCommands
          .where((c) => c.contains('herdr api snapshot'))
          .length;

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.focusHerdrPaneDirectionForTesting(
        SwipeDirection.right,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 分類別通知（no_neighbor → 情報 SnackBar）。
      expect(
        find.text('No pane in that direction'),
        findsOneWidget,
        reason: 'focus の no_neighbor は情報 SnackBar で通知されること（S4/T19）',
      );
      // 後続処理なし（T19 仕様）: force 再取得・切替コミットを発行しない。
      final snapshotCountAfter = client.execCommands
          .where((c) => c.contains('herdr api snapshot'))
          .length;
      expect(
        snapshotCountAfter,
        snapshotCountBefore,
        reason:
            'no_neighbor は soft 失敗のため _syncAfterHerdrMutation（force 再取得）しない',
      );
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('switch target')),
        isFalse,
        reason: 'no_neighbor は情報通知のみでターゲット切替をしない',
      );

      // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets(
      'rename pane の target-not-found は SnackBar 通知 + 単一経路で再同期する（Q-02）',
      (tester) async {
        await pumpHerdrTerminal(
          tester,
          // rename が pane_not_found で失敗 → 再同期（force 再取得）で w1:p2 へ。
          execOutputs: {'herdr pane rename': kPaneNotFoundErrorFixture},
          execExitCodes: {'herdr pane rename': 1},
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrSnapshotPane2Fixture,
            ],
          },
        );

        final dynamic state = tester.state(find.byType(TerminalScreen));
        final future = state.renameHerdrPaneForTesting('w1:p1', 'x');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await future;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // 分類別通知（target-not-found）+ 単一経路の再同期。
        expect(
          find.text('Target pane disappeared. Re-synced.'),
          findsOneWidget,
          reason: 'rename pane の pane_not_found も target-not-found 分類で通知されること',
        );
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('rename pane re-sync -> w1:p2')),
          isTrue,
          reason:
              'rename pane の target-not-found 後は _syncAfterHerdrMutation で再同期されること',
        );
        expect(find.text('Pane 2'), findsOneWidget);

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );

    testWidgets('zoom の pane_not_found も SnackBar 通知 + 再同期で復旧する（Q-02・移設）', (
      tester,
    ) async {
      await pumpHerdrTerminal(
        tester,
        // zoom が pane_not_found で失敗 → 再同期（force 再取得）で w1:p2 へ。
        execOutputs: {'herdr pane zoom': kPaneNotFoundErrorFixture},
        execExitCodes: {'herdr pane zoom': 1},
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotFixture,
            kHerdrSnapshotPane2Fixture,
          ],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.zoomHerdrPaneForTesting('w1:p1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 分類別通知（target-not-found）+ 単一経路の再同期。
      expect(
        find.text('Target pane disappeared. Re-synced.'),
        findsOneWidget,
        reason: 'zoom の pane_not_found も target-not-found 分類で通知されること',
      );
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('zoom re-sync -> w1:p2')),
        isTrue,
        reason: 'zoom の target-not-found 後は _syncAfterHerdrMutation で再同期されること',
      );
      expect(find.text('Pane 2'), findsOneWidget);

      // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets('close tab の target-not-found も SnackBar 通知 + 再同期で復旧する（Q-05）', (
      tester,
    ) async {
      await pumpHerdrTerminal(
        tester,
        execOutputs: {'herdr tab close': kPaneNotFoundErrorFixture},
        execExitCodes: {'herdr tab close': 1},
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrTwoPanesSnapshotFixture,
            kHerdrSnapshotPane2Fixture,
          ],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.closeHerdrTabForTesting('w1:t1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Target pane disappeared. Re-synced.'),
        findsOneWidget,
        reason: 'close tab の tab_not_found も target-not-found 分類で通知されること',
      );
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('close tab re-sync -> w1:p2')),
        isTrue,
        reason:
            'close tab の target-not-found 後は _syncAfterHerdrMutation で再同期されること',
      );

      // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets('server-down は既存どおりポーリング停止 + 通知に倒れる', (tester) async {
      final client = await pumpHerdrTerminal(
        tester,
        execExceptions: {'herdr pane split': HerdrServerNotRunningException()},
      );

      // server-down 発生前のポーリング read 回数。
      final readsBefore = client.execCommands
          .where((c) => c.contains('herdr pane read'))
          .length;

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.splitPaneForTesting(
        'w1:p1',
        SplitDirection.horizontal,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 既存の server-down 通知（Retry 付き・ポーリング停止 + キャッシュ失効）。
      expect(
        find.textContaining('Herdr server is not responding'),
        findsOneWidget,
        reason: 'server-down は既存の _handleHerdrServerDown 通知に倒れること',
      );

      // ポーリング停止: 2 秒進めても pane read が新規発行されない。
      final readsAfter = client.execCommands
          .where((c) => c.contains('herdr pane read'))
          .length;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        client.execCommands.where((c) => c.contains('herdr pane read')).length,
        readsAfter,
        reason: 'server-down 後はポーリングが停止し pane read を再発行しないこと',
      );
      expect(readsBefore, greaterThan(0));

      // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets('再同期でも対象が残らない場合は終端通知（再接続しない・R1）', (tester) async {
      await pumpHerdrTerminal(
        tester,
        // close 後（force 再取得）は workspace 消滅（panes 空）。
        execOutputs: {'herdr pane close': kPaneNotFoundErrorFixture},
        execExitCodes: {'herdr pane close': 1},
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotFixture,
            kHerdrEmptySnapshotFixture,
          ],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      // close を直接実行するテストフックは無いため、単一経路の再同期を直接呼ぶ
      // （close 成功後の _syncAfterHerdrMutation と同じ経路）。
      final future = state.syncAfterHerdrMutationForTesting(
        eventLabel: 'close pane sync',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final result = await future;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(result, isFalse, reason: '再解決不能（全 workspace 消滅）は false');
      expect(
        find.text('Herdr target pane not found'),
        findsOneWidget,
        reason: '終端通知（再接続しない・R1）が表示されること',
      );
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('close pane sync: no target remains')),
        isTrue,
      );

      // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });
  });
}
