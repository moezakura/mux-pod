import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';

import '../../helpers/fake_ssh_client.dart';
import '../../helpers/terminal_test_scaffold.dart';

// T17（Q-03/R1/R2）: C-c 解禁（初回確認ダイアログのみ・警告バッジは表示
// しない）・破壊的 close の `pane close` 一本化・連鎖 close 確認（最後の
// pane / tab 判定）。

// G4 実測の snapshot fixture（w1:p1 のみ・単一 tab / 単一 workspace）。
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

// 2 pane（w1:p1 / w1:p2）・単一 tab の snapshot fixture。
// どちらかの pane を閉じても「最後の pane」ではない（連鎖警告なし）。
const kHerdrTwoPanesSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/a","focused":true,'
    '"foreground_cwd":"/a","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/b","focused":false,'
    '"foreground_cwd":"/b","pane_id":"w1:p2","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_2","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":2,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":2,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// 対象が存在しない（panes 空）snapshot fixture（連鎖 close 後の再解決終端用）。
const kHerdrEmptySnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":null,"focused_tab_id":null,"focused_workspace_id":null,'
    '"layouts":[],"panes":[],"protocol":17,"tabs":[],"version":"0.7.5",'
    '"workspaces":[]},"type":"session_snapshot"}}';

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

/// herdr（mutation 解禁）のターミナルを起動し、pane セレクタを開く。
Future<FakeSshClient> _openHerdrPaneSelector(
  WidgetTester tester, {
  Map<String, String> execOutputs = const {},
  Map<String, List<String>> execOutputQueues = const {},
}) async {
  final client = await TerminalTestScaffold.pumpTerminalScreen(
    tester,
    connection: _herdrConnection(),
    sessionName: 'lab-ws1',
    execOutputs: {
      'herdr api snapshot': kHerdrSnapshotFixture,
      'herdr pane read': 'hello\n',
      ...execOutputs,
    },
    execOutputQueues: execOutputQueues,
    settle: false,
  );

  // pane セグメント（'Pane 1'）タップ → pane セレクタ。
  await tester.tap(find.text('Pane 1'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Select Pane'), findsOneWidget);
  return client;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('T17: C-c 解禁（Q-03/R1）', () {
    testWidgets(
      'C-c 初回は確認ダイアログを表示し、キャンセルでは送信しない',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        final dynamic state = tester.state(find.byType(TerminalScreen));
        state.sendSpecialKeyForTesting('C-c');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // 初回確認ダイアログ（Q-03 の文言）。
        expect(find.text('Send Ctrl-C?'), findsOneWidget);
        expect(
          find.textContaining('シェルを終了させる場合があります'),
          findsOneWidget,
        );
        expect(
          find.textContaining('破壊的な close は Pane メニューの Close'),
          findsOneWidget,
        );

        // Cancel → send-keys は発行されない。
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          client.execCommands.any(
            (c) => c.contains('herdr pane send-keys') && c.contains('C-c'),
          ),
          isFalse,
          reason: 'キャンセル時は C-c を送信しないこと',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'C-c 確認後に送信され、フラグ保存後はダイアログを出さない（一度だけ）',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        final dynamic state = tester.state(find.byType(TerminalScreen));

        // 1 回目: 確認 → Send で `herdr pane send-keys w1:p1 C-c` が発行される。
        state.sendSpecialKeyForTesting('C-c');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('Send'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          client.execCommands.any((c) => c == 'herdr pane send-keys w1:p1 C-c'),
          isTrue,
          reason: '確認後は PaneKeyMap 経由で send-keys C-c が送信されること（Q-07①）',
        );

        // 2 回目: フラグ保存済みのためダイアログなしで送信される。
        final before = client.execCommands.length;
        state.sendSpecialKeyForTesting('C-c');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Send Ctrl-C?'), findsNothing);
        expect(
          client.execCommands.length,
          greaterThan(before),
          reason: '2 回目以降は確認なしで送信されること（SharedPreferences フラグ）',
        );
        expect(
          client.execCommands.where((c) => c.contains('C-c')).length,
          greaterThanOrEqualTo(2),
        );

        // キーオーバーレイの 1500ms タイマーを消化してクリーンに終了。
        await tester.pump(const Duration(milliseconds: 1500));
      },
    );

    testWidgets('mutation 解禁時も C-c 警告バッジは表示されない（tmux と同様）', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      // 実測で「C-c によるシェル終了（SIGINT）」はターミナル標準挙動（tmux でも
      // 同様）と判明したため、警告バッジは表示しない（tmux と同じ操作感・
      // ユーザー決定）。初回確認ダイアログは残る。
      expect(find.text('Ctrl-C 注意'), findsNothing);
      expect(find.text('Read-only'), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('readOnly 明示時は Read-only バッジ', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        readOnly: true,
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      expect(find.text('Read-only'), findsOneWidget);
      expect(find.text('Ctrl-C 注意'), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('T17: 連鎖 close 確認（Q-03/R2）', () {
    testWidgets(
      'pane セレクタの Close は確認ダイアログを経由して pane close を発行する',
      (tester) async {
        final client = await _openHerdrPaneSelector(
          tester,
          execOutputs: {'herdr api snapshot': kHerdrTwoPanesSnapshotFixture},
        );

        // タイルの ⋮ → Close Pane。
        await tester.tap(find.byIcon(Icons.more_vert).first);
        // PopupMenu の表示アニメーションを消化する。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Close Pane'));
        // _closeSelectorThen の 200ms 遅延後に確認ダイアログが開く。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // 最後の pane ではないため通常の確認文言。
        expect(find.text('Close Pane?'), findsOneWidget);
        expect(
          find.textContaining('Are you sure you want to close pane'),
          findsOneWidget,
        );

        await tester.tap(find.text('Close'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          client.execCommands.any(
            (c) =>
                c == 'herdr pane close w1:p1' ||
                c == 'herdr pane close w1:p2',
          ),
          isTrue,
          reason: '破壊的 close は PaneWriter.closePane（herdr pane close）で行うこと',
        );

        // _scrollToCaret の遅延タイマーを消化してクリーンに終了。
        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      '最後の pane を閉じると tab/workspace 連鎖終了を警告する',
      (tester) async {
        // 単一 workspace / 単一 tab / 単一 pane の snapshot。
        await _openHerdrPaneSelector(tester);

        await tester.tap(find.byIcon(Icons.more_vert).first);
        // PopupMenu の表示アニメーションを消化する。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Close Pane'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Close Pane?'), findsOneWidget);
        expect(
          find.textContaining(
            'last pane in the last tab',
          ),
          findsOneWidget,
          reason: '最後の pane + 最後の tab は tab と workspace の連鎖終了を警告すること',
        );
        expect(
          find.textContaining('close the tab and the workspace'),
          findsOneWidget,
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      '連鎖 close 確認後に pane close が発行され、再解決で終端通知になる',
      (tester) async {
        final client = await _openHerdrPaneSelector(
          tester,
          // 接続時: 単一 pane / close 後の force 再取得: 空（workspace 消滅）。
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrEmptySnapshotFixture,
            ],
          },
        );

        await tester.tap(find.byIcon(Icons.more_vert).first);
        // PopupMenu の表示アニメーションを消化する。
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

        // 破壊的 close は `herdr pane close`（send-keys C-c ではない）。
        expect(
          client.execCommands.any(
            (c) => c == 'herdr pane close w1:p1',
          ),
          isTrue,
          reason: 'C-c ではなく pane close が破壊的 close の唯一経路であること',
        );

        // close 後の H5 単一経路（強制再取得）が実行されること。
        expect(
          client.execCommands.any(
            (c) => c.contains('herdr api snapshot'),
          ),
          isTrue,
          reason: 'close 後の H5 単一経路（強制再取得）が実行されること',
        );

        // _scrollToCaret の遅延タイマーを消化してクリーンに終了。
        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  });
}
