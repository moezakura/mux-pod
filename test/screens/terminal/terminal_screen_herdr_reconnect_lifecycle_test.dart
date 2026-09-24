import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('TerminalScreen herdr (backend flow / display)', () {
    testWidgets(
      'herdr reconnect re-resolves the target from a fresh snapshot and keeps '
      'polling without tmux tree refresh (T9a)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            // フォールバック: 3 回目以降の snapshot も再取得済み（w1:p2）を返す
            'herdr api snapshot': kHerdrSnapshotPane2Fixture,
            'herdr pane read w1:p1': 'content from p1\n',
            'herdr pane read w1:p2': 'content from p2\n',
          },
          // 1 回目（接続時解決）: w1:p1 / 2 回目（再接続後再解決）: w1:p2
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrSnapshotPane2Fixture,
            ],
          },
          settle: false,
        );

        // 初回表示: w1:p1 を read している
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p1')),
          isTrue,
        );

        // 再接続成功（SshNotifier のコールバック経由）
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        notifier.onReconnectSuccess?.call();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // _applyUpdate が post-frame に延期される場合があるため、描画を確定させる
        await tester.pump();

        // 再接続後: 新 adapter の cache（`identical` 差し替え検出）経由で snapshot を
        // 再取得し、ターゲットを w1:p2 へ再解決する（エポック++ は cache 内在）
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('re-resolve after reconnect -> w1:p2')),
          isTrue,
          reason: '再接続後のターゲット再解決がリングバッファに記録されること',
        );

        // 表示が w1:p2 に切り替わり、ポーリングが新ターゲットを読む
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p2')),
          isTrue,
          reason: '再接続後のポーリングは再解決した新しい pane ID を読むこと',
        );
        expect(find.textContaining('content from p2'), findsWidgets);

        // tmux ツリー更新は herdr では発火しない（既存バグ修正・A7）
        expect(
          client.execCommands.any((c) => c.contains('list-panes -a')),
          isFalse,
          reason: 'herdr では _startTreeRefresh（list-panes）を起動しないこと',
        );

        // 再接続後初回コンテンツ適用でスケジュールされる _scrollToCaret の
        // 100ms 遅延タイマーを消化する（ポーリングタイマーは dispose が破棄する）
        await tester.pump(const Duration(milliseconds: 200));
      },
    );
    testWidgets(
      'herdr reconnect to the same pane keeps the display without a switch '
      '(T9a)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read w1:p1': 'content from p1\n',
          },
          settle: false,
        );

        expect(find.textContaining('content from p1'), findsWidgets);

        // 再接続成功（同一 snapshot に再解決 → 切替コミットなし）
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        notifier.onReconnectSuccess?.call();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('re-resolve after reconnect -> w1:p1')),
          isTrue,
          reason: '再接続後の再解決（同一 pane）が記録されること',
        );
        expect(
          events.any((e) => e.contains('switch target')),
          isFalse,
          reason: '同一 pane への再解決では切替コミットが発生しないこと',
        );

        // 表示は継続され、ポーリングも同じ pane を読み続ける
        expect(find.textContaining('content from p1'), findsWidgets);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p1')),
          isTrue,
          reason: '再接続後も同一 pane のポーリングが継続すること',
        );
      },
    );
    testWidgets(
      'herdr lifecycle: resume restarts polling after server-down suspension '
      'without tmux tree refresh (T9b)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            // 構造化エラー: server 未稼働系 errorCode（A1 条件2）
            'herdr pane read':
                '{"error":{"code":"connection_refused","message":"connect refused"}}',
          },
          execExitCodes: {'herdr pane read': 1},
          settle: false,
        );

        // 初回ポーリングで server-down を検出しポーリング停止
        await tester.pump(const Duration(milliseconds: 200));
        final readsAfterDown = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        await tester.pump(const Duration(milliseconds: 500));
        final readsLater = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        expect(
          readsLater,
          readsAfterDown,
          reason: 'server-down 後はポーリングが停止していること',
        );

        // バックグラウンドへ → フォアグラウンド復帰
        // （herdr: サーバー復旧を再検証してポーリングを再開する）
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        // tmux ツリー更新は発火しない（A7）
        expect(
          client.execCommands.any((c) => c.contains('list-panes -a')),
          isFalse,
          reason: 'herdr では復帰時も _startTreeRefresh を起動しないこと',
        );

        // ポーリング再開: 次回 read が server-down で再停止 + SnackBar 通知
        await tester.pump(const Duration(milliseconds: 300));
        final readsAfterResume = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        expect(
          readsAfterResume,
          greaterThan(readsLater),
          reason: '復帰時に server-down 停止状態からポーリングが再開されること',
        );
        expect(find.byType(SnackBar), findsOneWidget);

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );
    testWidgets(
      'herdr lifecycle: dispose cleans up snapshot cache and ring buffer '
      'without exceptions (T9b)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        expect(notifier.onReconnectSuccess, isNotNull);

        // 画面破棄で HerdrSnapshotCache / リングバッファ等を例外なくクリーンアップ
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(notifier.onReconnectSuccess, isNull);
        expect(notifier.onDisconnectDetected, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
