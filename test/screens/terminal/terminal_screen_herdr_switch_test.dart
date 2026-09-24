import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_content_reader.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_read.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

class _ReResolvePropagationReader implements PaneContentReader {
  String pollContent = 'content from p1\n';
  bool failNextPoll = false;

  @override
  Future<MultiplexerPaneSnapshot> readPane(PaneReadRequest request) async {
    if (failNextPoll) {
      failNextPoll = false;
      throw const HerdrTargetNotFoundException(
        kind: HerdrTargetNotFoundKind.pane,
        message: 'no such pane',
        errorCode: 'pane_not_found',
        exitCode: 1,
      );
    }
    return MultiplexerPaneSnapshot(content: pollContent);
  }
}

void main() {
  group('TerminalScreen herdr (backend flow / display)', () {
    testWidgets(
      'monitors server-down detection in the [HerdrSwitch] ring buffer (A8/T5b)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
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
        // ポーリングの catch を発火させる（初回ポーリングで pane read が失敗する）
        await tester.pump(const Duration(milliseconds: 200));

        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('server-down detected')),
          isTrue,
          reason: 'server-down 検出がリングバッファに [HerdrSwitch] 付きで記録されること',
        );
        expect(
          events.where((e) => e.startsWith('[HerdrSwitch]')).length,
          greaterThanOrEqualTo(1),
        );
      },
    );
    testWidgets(
      'monitors target-not-found detection in the [HerdrSwitch] ring buffer (A8/T5b)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            // 構造化エラー: target 不在（A2 再解決トリガ）
            'herdr pane read':
                '{"error":{"code":"pane_not_found","message":"no such pane"}}',
          },
          execExitCodes: {'herdr pane read': 1},
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 200));

        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('target-not-found detected')),
          isTrue,
          reason: 'target-not-found 検出がリングバッファに [HerdrSwitch] 付きで記録されること',
        );
      },
    );
    testWidgets(
      'switch commit updates display state and polling target without mutation (A4/T6)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          initialPaneId: 'w1:p1',
          execOutputs: {'herdr pane read': 'content\n'},
          settle: false,
        );

        // 初期表示は w1:p1 を read している
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p1')),
          isTrue,
        );

        // 切替コミットを実行（本番の呼び出し元はセレクタ T10。テストフックは
        // `_switchHerdrTarget` を直接呼ぶ = 切替コミットの単一入口の検証）
        final dynamic state = tester.state(find.byType(TerminalScreen));
        state.switchHerdrTargetForTesting('w1:p2');
        await tester.pump();

        // 表示対象切替イベントがリングバッファに [HerdrSwitch] 付きで記録される（A8）
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('switch target -> w1:p2')),
          isTrue,
          reason: '表示対象切替がリングバッファに [HerdrSwitch] 付きで記録されること',
        );

        // コンテンツクリア + boostPolling: 次のポーリングで新ターゲットを read する
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p2')),
          isTrue,
          reason: '切替後に新しい pane ID がポーリング対象になること',
        );

        // 切替のみ: mutation（select-pane 等の tmux/herdr CLI）は一切発行されない
        expect(
          client.execCommands.any((c) => c.contains('select-pane')),
          isFalse,
        );
        expect(
          client.execCommands.any((c) => c.contains('herdr pane focus')),
          isFalse,
        );
      },
    );
    testWidgets('switch to the same target is a no-op (L-3: no flicker)', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        initialPaneId: 'w1:p1',
        execOutputs: {'herdr pane read': 'content\n'},
        settle: false,
      );

      // 直接指定（initialPaneId）の初期表示: workspaceId 'w1' / tabId null。
      // 同一ターゲット（paneId / workspaceId / tabId が全て一致）への切替は
      // no-op で、表示リセット・切替イベント・ポーリングブーストを抑止する。
      final dynamic state = tester.state(find.byType(TerminalScreen));
      state.switchHerdrTargetForTesting('w1:p1');
      await tester.pump();

      final events = herdrSwitchEvents(tester);
      expect(
        events.any((e) => e.contains('switch target')),
        isFalse,
        reason: '同一ターゲットへの切替は no-op で切替イベントを記録しないこと',
      );

      // 表示内容が維持されている（no-op でコンテンツがクリアされない）
      expect(find.textContaining('content'), findsWidgets);
    });
    testWidgets(
      'server-down stops polling, shows SnackBar with retry, no reconnect '
      '(A2/T7)',
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

        // 初回ポーリングで server-down を検出し、ポーリングを停止する
        await tester.pump(const Duration(milliseconds: 200));

        // 監視（A8）: server-down 検出がリングバッファに記録される
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('server-down')),
          isTrue,
          reason: 'server-down 検出がリングバッファに [HerdrSwitch] 付きで記録されること',
        );

        // SnackBar + Retry（Retry = 再試行）が表示される
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);

        // 再接続しない（R1）: server-down は再接続ループにせずポーリング停止
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        expect(
          notifier.reconnectCalls,
          0,
          reason: 'server-down では再接続せずポーリングを停止すること',
        );

        // ポーリング停止: 以降 pane read が増えない
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
          reason: 'server-down 後はポーリングが停止し pane read が増えないこと',
        );

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );
    testWidgets(
      'target-not-found re-resolves via forced snapshot and switches pane '
      '(A2/T7)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            // フォールバック: 3 回目以降の snapshot は再取得済み（w1:p2）を返す
            'herdr api snapshot': kHerdrSnapshotPane2Fixture,
            'herdr pane read w1:p1':
                '{"error":{"code":"pane_not_found","message":"no such pane"}}',
            'herdr pane read w1:p2': 'hello from p2\n',
          },
          // 1 回目（接続時解決）: w1:p1 / 2 回目（強制再取得）: w1:p2
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrSnapshotPane2Fixture,
            ],
          },
          execExitCodes: {'herdr pane read w1:p1': 1},
          settle: false,
        );

        // pane read w1:p1 が pane_not_found → 強制再取得で w1:p2 へ再解決
        await tester.pump(const Duration(milliseconds: 300));

        // 監視（A8）: 再解決成功がリングバッファに記録される
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('re-resolve succeeded -> w1:p2')),
          isTrue,
          reason: '再解決成功がリングバッファに [HerdrSwitch] 付きで記録されること',
        );

        // 表示対象が w1:p2 へ切り替わり、次のポーリングが新ターゲットを読む
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p2')),
          isTrue,
          reason: '再解決後は新しい pane ID がポーリング対象になること',
        );
        expect(find.textContaining('hello from p2'), findsWidgets);

        // 再接続は発生しない（再解決は再接続ではなく表示継続）
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        expect(
          notifier.reconnectCalls,
          0,
          reason: 'target-not-found の再解決は再接続を伴わないこと',
        );
      },
    );
    testWidgets(
      're-resolve propagates the snapshot tabId/workspaceId into the display '
      'state (T3)',
      (tester) async {
        final reader = _ReResolvePropagationReader();

        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          initialPaneId: 'w1:p1',
          paneContentReader: reader,
          // 直接指定（initialPaneId）のため初回の snapshot 取得は再解決時のみ
          execOutputs: {'herdr api snapshot': kHerdrSnapshotPane2Fixture},
          settle: false,
        );

        // 直接指定の初期表示では tabId 未確定（2 セグメント pane ID）のため
        // tab セグメントは非表示。
        expect(find.byIcon(Icons.tab), findsNothing);
        expect(find.textContaining('content from p1'), findsWidgets);

        // 次のポーリング read を target-not-found で失敗 → 強制再取得（w1:p2 の
        // snapshot）で再解決し、_switchHerdrTarget へ tabId / workspaceId が
        // 伝播する。再解決後のポーリング内容も差し替えておく。
        reader.failNextPoll = true;
        reader.pollContent = 'hello from p2\n';
        // 失敗ポーリング → 強制再取得 → 再解決 → 切替コミット
        await tester.pump(const Duration(milliseconds: 300));
        // 切替後のブーストポーリングが新ターゲットを読み、内容が反映される
        await tester.pump(const Duration(milliseconds: 300));

        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('re-resolve succeeded -> w1:p2')),
          isTrue,
          reason: '再解決成功がリングバッファに記録されること',
        );

        // 表示が w1:p2 に切り替わり、新しい pane の内容が表示される
        expect(
          find.textContaining('hello from p2'),
          findsWidgets,
          reason: '再解決後は新しい pane の内容が表示されること',
        );

        // 再解決後の表示状態に snapshot 実値（w1:p2 → tabId w1:t1）が反映され、
        // パンくずに tab セグメントが表示される。
        expect(
          find.byIcon(Icons.tab),
          findsOneWidget,
          reason: '再解決で確定した tabId が表示状態へ伝播し tab セグメントが表示されること',
        );
      },
    );
    testWidgets(
      'target-not-found terminal: re-resolve failure stops polling without '
      'reconnect (A2/T7)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            // フォールバック: 3 回目以降の snapshot も空（対象不在）
            'herdr api snapshot': kHerdrEmptySnapshotFixture,
            'herdr pane read':
                '{"error":{"code":"pane_not_found","message":"no such pane"}}',
          },
          // 1 回目（接続時解決）: w1:p1 / 2 回目（強制再取得）: 対象なし
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrEmptySnapshotFixture,
            ],
          },
          execExitCodes: {'herdr pane read': 1},
          settle: false,
        );

        await tester.pump(const Duration(milliseconds: 300));

        // 監視（A8）: 再解決失敗がリングバッファに記録される
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('re-resolve failed')),
          isTrue,
          reason: '再解決失敗がリングバッファに [HerdrSwitch] 付きで記録されること',
        );

        // 終端: 再接続しない（R1）
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        expect(notifier.reconnectCalls, 0, reason: '再解決失敗の終端では再接続しないこと');

        // SnackBar 通知（Retry = 再試行）
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);

        // 終端後はポーリングが停止し pane read が増えない
        final readsAfterTerminal = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        await tester.pump(const Duration(milliseconds: 500));
        final readsLater = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        expect(
          readsLater,
          readsAfterTerminal,
          reason: '終端後はポーリングが停止し pane read が増えないこと',
        );

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );
  });
}
