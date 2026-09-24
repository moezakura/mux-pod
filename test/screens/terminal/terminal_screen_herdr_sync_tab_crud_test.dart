import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('T18: mutation 後ツリー同期の単一化（H5/S4）', () {
    testWidgets('create tab（label + --focus）成功後は単一経路（force 再取得）で同期され、'
        '新タブの表示へ自動切替わる（Q-05・タスク②）', (tester) async {
      final client = await pumpHerdrTerminal(
        tester,
        // 接続時: w1:t1（w1:p1）/ create --focus 後の force 再取得: 旧 tab は
        // 残存しつつ新タブ w1:t8（w1:p2）が focused（S0 実測形状）。
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotFixture,
            kHerdrNewTabActiveSnapshotFixture,
          ],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.createHerdrTabForTesting(
        'w1',
        label: 'logs',
        focus: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();

      expect(
        client.execCommands.any(
          (c) => c == "herdr tab create --workspace w1 --label 'logs' --focus",
        ),
        isTrue,
        reason:
            'tab 作成は PaneWriter.createTab（herdr tab create --label --focus）で実行されること',
      );
      expect(
        client.execCommands
            .where((c) => c.contains('herdr api snapshot'))
            .length,
        greaterThanOrEqualTo(2),
        reason: 'create tab 応答は layout なしのため force 再取得で反映すること（T18）',
      );
      // アプリ契約（作成後自動切替）: 旧 pane（w1:p1）が snapshot に残存しても、
      // followBackendFocus で新タブの focused pane（w1:p2）へ表示が切り替わる。
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('create tab sync -> w1:p2')),
        isTrue,
        reason: 'create 後は _syncAfterHerdrMutation（create tab sync）が走ること',
      );
      expect(
        events.any((e) => e.contains('switch target -> w1:p2')),
        isTrue,
        reason: '--focus 付き create は snapshot の focused pane へ表示を追従すること',
      );
      expect(find.text('Pane 2'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
    });
    testWidgets('空欄ラベル（null / 空文字）は --label なし + --focus で作成される（Q-05・タスク②）', (
      tester,
    ) async {
      final client = await pumpHerdrTerminal(
        tester,
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotFixture,
            kHerdrSnapshotFixture,
            kHerdrSnapshotFixture,
            kHerdrSnapshotFixture,
          ],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));

      // label: null → --label なし + --focus。
      var future = state.createHerdrTabForTesting('w1', focus: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();
      expect(
        client.execCommands.any(
          (c) => c == 'herdr tab create --workspace w1 --focus',
        ),
        isTrue,
        reason: 'label null は --label なし（デフォルト名）で --focus 付き作成になる',
      );

      // label: 空文字 → 同様に --label なし + --focus。
      future = state.createHerdrTabForTesting('w1', label: '', focus: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();
      expect(
        client.execCommands.any(
          (c) => c == 'herdr tab create --workspace w1 --focus',
        ),
        isTrue,
        reason: '空文字ラベルも --label なし（デフォルト名）で --focus 付き作成になる',
      );
      // --label を含む create が発行されていないこと（透過・正規化の回帰防止）。
      expect(
        client.execCommands
            .where((c) => c.startsWith('herdr tab create'))
            .any((c) => c.contains('--label')),
        isFalse,
      );

      await tester.pump(const Duration(milliseconds: 200));
    });
    testWidgets('ラベル付き create は focus の有無で --focus 付与と表示追従が分岐する'
        '（Q-05・タスク②）', (tester) async {
      final client = await pumpHerdrTerminal(
        tester,
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotFixture,
            kHerdrSnapshotFixture,
            kHerdrSnapshotFixture,
            kHerdrSnapshotFixture,
          ],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));

      // focus: true → --focus 付与。
      var future = state.createHerdrTabForTesting(
        'w1',
        label: 'logs',
        focus: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();
      expect(
        client.execCommands.any(
          (c) => c == "herdr tab create --workspace w1 --label 'logs' --focus",
        ),
        isTrue,
        reason: 'focus: true は --focus を付与する',
      );

      // focus: null → --focus なし（フォーカス不変・herdr 既定）+ 表示追従しない。
      future = state.createHerdrTabForTesting('w1', label: 'logs');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();
      expect(
        client.execCommands.any(
          (c) => c == "herdr tab create --workspace w1 --label 'logs'",
        ),
        isTrue,
        reason: 'focus: null は --focus を付与しない',
      );
      // 同一 fixture（フォーカス pane = 現在 pane）ではいずれも切替なし
      // （sticky 維持・Codex 観点 ②）。
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('switch target')),
        isFalse,
        reason: 'focus なし create は現在の tab を維持する（切替コミットなし）',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });
    testWidgets('followBackendFocus でも focused 情報が欠落していれば現在表示を維持する'
        '（タスク②・Codex 観点 ④）', (tester) async {
      await pumpHerdrTerminal(
        tester,
        // 接続時: w1:p1（フォーカス）/ force 再取得: 全 tab・pane が非フォーカス
        // （focused 情報欠落）→ followBackendFocus は null を返し sticky に
        // フォールバックして現在表示（w1:p1）を維持する。
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotFixture,
            kHerdrSnapshotNoFocusInfoFixture,
          ],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.syncAfterHerdrMutationForTesting(
        eventLabel: 'test mutation sync',
        policy: HerdrSyncTargetPolicy.followBackendFocus,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();

      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('switch target')),
        isFalse,
        reason: 'focused 情報欠落時は sticky へフォールバックして現在表示を維持すること',
      );
      expect(find.text('Pane 1'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
    });
    testWidgets('rename tab 成功後は単一経路（force 再取得）で同期される（Q-05）', (tester) async {
      final client = await pumpHerdrTerminal(
        tester,
        execOutputQueues: {
          'herdr api snapshot': [kHerdrSnapshotFixture, kHerdrSnapshotFixture],
        },
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      final future = state.renameHerdrTabForTesting('w1:t1', 'work');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await future;
      await tester.pump();

      expect(
        client.execCommands.any((c) => c == "herdr tab rename w1:t1 'work'"),
        isTrue,
        reason: 'tab rename は PaneWriter.renameTab（herdr tab rename）で実行されること',
      );
      expect(
        client.execCommands
            .where((c) => c.contains('herdr api snapshot'))
            .length,
        greaterThanOrEqualTo(2),
        reason: 'rename tab 成功後も _syncAfterHerdrMutation 単一経路が走ること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });
    testWidgets('close tab 成功後に再解決でターゲットが別 pane へ遷移する（単一経路・連鎖遷移）', (
      tester,
    ) async {
      final client = await pumpHerdrTerminal(
        tester,
        // 接続時: 2 pane / close tab 後の force 再取得: w1:p2 のみ（w1:p1 消滅）。
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

      expect(
        client.execCommands.any((c) => c == 'herdr tab close w1:t1'),
        isTrue,
        reason: 'tab close は PaneWriter.closeTab（herdr tab close）で実行されること',
      );
      // 単一経路: force 再取得 → 再解決で w1:p1 消滅 → w1:p2 へ遷移。
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('close tab sync -> w1:p2')),
        isTrue,
        reason: 'close tab 後は _syncAfterHerdrMutation（close tab sync）が走ること',
      );
      expect(
        events.any((e) => e.contains('switch target -> w1:p2')),
        isTrue,
        reason: '連鎖 close でターゲット消滅時は再解決で別 pane に遷移すること',
      );
      expect(find.text('Pane 2'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
    });
    testWidgets('close 成功後に再解決でターゲットが別 pane へ遷移する（単一経路・連鎖遷移）', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {'herdr pane read': 'hello\n'},
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

      // pane セレクタを開く（pane セグメント 'Pane 1' タップ）。
      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Pane'), findsOneWidget);

      // w1:p1 のタイル ⋮ → Close Pane → 確認 → Close。
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

      // 破壊的 close は `pane close` の唯一経路。
      expect(
        client.execCommands.any(
          (c) => c == 'herdr pane close w1:p1' || c == 'herdr pane close w1:p2',
        ),
        isTrue,
        reason: 'close は PaneWriter.closePane（herdr pane close）で実行されること',
      );

      // 単一経路: force 再取得 → 再解決で w1:p1 消滅 → w1:p2 へ遷移。
      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('close pane sync -> w1:p2')),
        isTrue,
        reason: 'close 後は _syncAfterHerdrMutation（close pane sync）が走ること',
      );
      expect(
        events.any((e) => e.contains('switch target -> w1:p2')),
        isTrue,
        reason: '破壊的操作でターゲット消滅時は再解決で別 pane に遷移すること',
      );

      // _scrollToCaret の遅延タイマーを消化してクリーンに終了。
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
