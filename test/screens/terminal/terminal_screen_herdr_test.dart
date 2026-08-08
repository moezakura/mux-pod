import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';

// A8 最小監視のテスト: `_TerminalScreenState` のリングバッファを
// `@visibleForTesting` フック（herdrSwitchEventsForTesting）経由で読み出す。
// イベント文字列には `[HerdrSwitch]` プレフィックスが含まれ、debugPrint に
// 出力される文字列と同一である。
List<String> herdrSwitchEvents(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(TerminalScreen));
  return List<String>.from(state.herdrSwitchEventsForTesting());
}

// M2: pane indicator（右上ミニマップ）の描画判定。`_PaneLayoutPainter` は
// `terminal_screen.dart` の private クラスのため runtimeType 名で特定する。
Finder paneIndicatorPainter() => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      w.painter.runtimeType.toString() == '_PaneLayoutPainter',
);

// G4 実測のスナップショット fixture（workspace label は lab-ws1 / pane は w1:p1）。
const kHerdrSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// 再解決後（pane 差し替え後）の snapshot fixture: pane は w1:p2 のみ。
const kHerdrSnapshotPane2Fixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p2","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p2","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// 対象が存在しない（panes 空）snapshot fixture（再解決の終端判定用）。
const kHerdrEmptySnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":null,"focused_tab_id":null,"focused_workspace_id":null,'
    '"layouts":[],"panes":[],"protocol":17,"tabs":[],"version":"0.7.5",'
    '"workspaces":[]},"type":"session_snapshot"}}';

// T10 セレクタ用: 2 workspace（w1/w2）の snapshot fixture。
// w1:p1（cwd=/tmp・focused）/ w2:p1（cwd=/var）を持ち、セレクタの
// workspace → tab → pane ドリルダウンと pane 表示名（A10: currentPath 優先）
// を検証できる。
const kHerdrTwoWorkspaceSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/var","focused":false,'
    '"foreground_cwd":"/var","pane_id":"w2:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w2:t1",'
    '"terminal_id":"term_2","workspace_id":"w2"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"},'
    '{"agent_status":"unknown","focused":false,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w2:t1","workspace_id":"w2"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"},'
    '{"active_tab_id":"w2:t1","agent_status":"unknown","focused":false,'
    '"label":"lab-ws2","number":1,"pane_count":1,"tab_count":1,'
    '"workspace_id":"w2"}]},"type":"session_snapshot"}}';

Connection _herdrConnection() {
  return Connection(
    id: 'test-conn',
    name: 'Herdr Server',
    host: 'testhost',
    port: 22,
    username: 'user',
    multiplexer: const MultiplexerConfig(backend: BackendType.herdr),
    createdAt: DateTime(2025, 1, 1),
  );
}

void main() {
  group('TerminalScreen herdr (read-only)', () {
    testWidgets('shows pane content read-only without tmux setup', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        readOnly: true,
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'hello\nworld\n',
        },
        settle: false,
      );

      // tmux のセットアップ（バージョン確認・ツリー取得・セッション作成）は
      // herdr では一切実行されない。
      expect(client.execCommands.any((c) => c.contains('tmux -V')), isFalse);
      expect(
        client.execCommands.any((c) => c.contains('list-panes -a')),
        isFalse,
      );
      expect(client.execCommands.any((c) => c.contains('set-option')), isFalse);

      // スナップショットから pane を解決し、pane read で内容を取得する。
      expect(
        client.execCommands.any((c) => c.contains('herdr api snapshot')),
        isTrue,
      );
      expect(
        client.execCommands.any(
          (c) => c.contains(
            'herdr pane read w1:p1 --source recent --lines 120 --raw',
          ),
        ),
        isTrue,
      );

      // read-only 表示（バナー + パンくずバッジ）
      expect(find.text('READ ONLY — viewing only'), findsOneWidget);
      expect(find.text('Read-only'), findsOneWidget);

      // 特殊キー入力バーは表示されない（mutation 無効化）
      expect(find.byType(SpecialKeysBar), findsNothing);

      // pane 内容が表示される
      expect(find.textContaining('hello'), findsWidgets);
      expect(find.textContaining('world'), findsWidgets);
    });

    testWidgets('uses an injected paneContentReader when provided', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        readOnly: true,
        initialPaneId: 'w1:p1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'injected content\n',
        },
        settle: false,
      );

      // 直接 pane ID 指定ならスナップショットに依存せず read する
      expect(
        client.execCommands.any(
          (c) => c.contains(
            'herdr pane read w1:p1 --source recent --lines 120 --raw',
          ),
        ),
        isTrue,
      );
      expect(find.textContaining('injected content'), findsWidgets);
    });

    testWidgets(
      'breadcrumb shows workspace label, pane segment, and tappable read-only '
      'badge (A9 display state / T11)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        // workspace ラベル + pane セグメント + Read-only バッジ（T11）。
        // pane ID が 2 セグメント形式（w1:p1）のため tab セグメントは非表示。
        expect(find.text('lab-ws1'), findsOneWidget);
        expect(find.text('Pane 1'), findsOneWidget);
        expect(find.text('Read-only'), findsOneWidget);
        expect(find.byIcon(Icons.tab), findsNothing);

        // read-only のためセッションセグメントはタップ不可（セレクタが開かない）
        await tester.tap(find.text('lab-ws1'));
        await tester.pump();
        expect(find.text('Select Session'), findsNothing);

        // T11: read-only バッジのタップで herdr 3 段セレクタ（第 1 段）が開く
        await tester.tap(find.text('Read-only'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Workspace'), findsOneWidget);
      },
    );

    testWidgets(
      'monitors server-down detection in the [HerdrSwitch] ring buffer (A8/T5b)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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

        // read-only: mutation（select-pane 等の tmux/herdr CLI）は一切発行されない
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

    testWidgets(
      'server-down stops polling, shows SnackBar with retry, no reconnect '
      '(A2/T7)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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
      'target-not-found terminal: re-resolve failure stops polling without '
      'reconnect (A2/T7)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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

    testWidgets(
      'herdr reconnect re-resolves the target from a fresh snapshot and keeps '
      'polling without tmux tree refresh (T9a)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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

    testWidgets(
      'T10 3-stage selector (workspace → tab → pane) switches the displayed '
      'pane via the single commit without mutation',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrTwoWorkspaceSnapshotFixture,
            'herdr pane read w1:p1': 'content from p1\n',
            'herdr pane read w2:p1': 'content from p2\n',
          },
          settle: false,
        );

        // 初期表示は w1:p1（snapshot から解決）
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p1')),
          isTrue,
        );

        // バッジタップ → 第 1 段: workspace 一覧
        await tester.tap(find.text('Read-only'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Workspace'), findsOneWidget);
        expect(find.text('lab-ws1'), findsWidgets);
        expect(find.text('lab-ws2'), findsOneWidget);

        // workspace 選択 → 第 2 段: tab 一覧
        await tester.tap(find.byKey(const ValueKey('herdr-sel-ws-w2')));
        await tester.pump();
        expect(find.text('Select Tab'), findsOneWidget);

        // tab 選択 → 第 3 段: pane 一覧
        await tester.tap(find.byKey(const ValueKey('herdr-sel-tab-w2:t1')));
        await tester.pump();
        expect(find.text('Select Pane'), findsOneWidget);

        // A10: pane 表示名は currentPath(cwd=/var) を優先する
        expect(find.text('/var'), findsOneWidget);

        // pane 選択 → 切替コミット（_switchHerdrTarget の単一入口経由）
        await tester.tap(find.byKey(const ValueKey('herdr-sel-pane-w2:p1')));
        await tester.pump();

        // A8 監視: 切替イベントがリングバッファに記録される
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('switch target -> w2:p1')),
          isTrue,
          reason: 'セレクタ選択が切替コミット（_switchHerdrTarget）を呼ぶこと',
        );

        // ポーリングが新しいターゲットを読む
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w2:p1')),
          isTrue,
          reason: '切替後に新しい pane ID がポーリング対象になること',
        );
        expect(find.textContaining('content from p2'), findsWidgets);

        // T11: ブレッドクラムの workspace ラベルが選択結果へ更新される
        expect(
          find.text('lab-ws2'),
          findsOneWidget,
          reason: 'パンくずの workspace 名が選択結果のラベルに更新されること',
        );

        // read-only（A6）: セレクタ経由でも mutation コマンドは一切発行されない
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

    testWidgets('T10 selector highlights the current display target as initial '
        'emphasis (workspace/tab/pane)', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        readOnly: true,
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Read-only'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Workspace'), findsOneWidget);

      // 初期強調: 現在ターゲット（w1:p1）が属する workspace が active 表示
      // （ActiveListTile のアクティブ時は title が太字になる）
      final wsTitle = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('herdr-sel-ws-w1')),
          matching: find.text('lab-ws1'),
        ),
      );
      expect(wsTitle.style?.fontWeight, FontWeight.bold);

      // workspace → tab へドリルダウン
      await tester.tap(find.byKey(const ValueKey('herdr-sel-ws-w1')));
      await tester.pump();
      expect(find.text('Select Tab'), findsOneWidget);

      // tab → pane 一覧。pane 表示名は cwd（A10: /tmp）を優先する
      await tester.tap(find.byKey(const ValueKey('herdr-sel-tab-w1:t1')));
      await tester.pump();
      expect(find.text('Select Pane'), findsOneWidget);
      expect(find.text('/tmp'), findsOneWidget);

      // 初期強調: 現在ターゲット w1:p1 が active 表示（title 太字）
      final paneTitle = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('herdr-sel-pane-w1:p1')),
          matching: find.text('/tmp'),
        ),
      );
      expect(paneTitle.style?.fontWeight, FontWeight.bold);

      // セレクタを閉じる（第 1 段の戻る位置まで戻す必要はなく、スワイプ/外側
      // タップ相当で閉じる。ここでは pane タップせずに dismiss する）
      await tester.tapAt(const Offset(500, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Pane'), findsNothing);
    });

    testWidgets('M2: herdr (read-only) では stale な tmux 複数ペイン状態でも pane '
        'indicator を表示せず mutation を発行しない', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        readOnly: true,
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        settle: false,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );

      // stale な tmuxProvider 状態を作る: 2 ペインのアクティブウィンドウを注入。
      // herdr 経路では tmuxProvider は更新されないため、接続前の残骸が残りうる。
      final tmuxNotifier = container.read(tmuxProvider.notifier);
      tmuxNotifier.updateSessions([
        TmuxSession(
          name: 'stale-session',
          windows: [
            TmuxWindow(
              index: 0,
              name: 'stale-win',
              panes: const [
                TmuxPane(index: 0, id: 'stale-p1', active: true),
                TmuxPane(index: 1, id: 'stale-p2'),
              ],
            ),
          ],
        ),
      ]);
      tmuxNotifier.setActive(
        sessionName: 'stale-session',
        windowIndex: 0,
        paneId: 'stale-p1',
      );
      await tester.pump();

      // 注入した状態が本当に複数ペイン（panes.length > 1）であることを確認
      // （ガードなしなら _buildPaneIndicator は表示される条件を満たす）。
      final staleState = container.read(tmuxProvider);
      expect(staleState.activeWindow?.panes.length, 2);

      // ガード: read-only では pane indicator は描画されない
      expect(paneIndicatorPainter(), findsNothing);

      // mutation（select/split/kill-pane 等の tmux コマンド）は一切発行されない
      expect(
        client.execCommands.any((c) => c.contains('select-pane')),
        isFalse,
      );
      expect(
        client.execCommands.any(
          (c) => c.contains('split-window') || c.contains('kill-pane'),
        ),
        isFalse,
      );
    });

    testWidgets('M2 regression: tmux (非 read-only) では pane indicator が表示される', (
      tester,
    ) async {
      // tmux backend（readOnly: false）: kFullTreeOutput の mysession/shell は
      // pane %0/%1 の 2 ペインを持つため indicator が描画される。
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      expect(paneIndicatorPainter(), findsWidgets);
    });
  });
}
