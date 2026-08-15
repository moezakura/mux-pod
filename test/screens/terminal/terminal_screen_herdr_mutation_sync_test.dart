import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_muxpod/services/tmux/pane_navigator.dart';
import 'package:flutter_muxpod/services/tmux/tmux_command_builder.dart';

import '../../helpers/fake_ssh_client.dart';
import '../../helpers/terminal_test_scaffold.dart';

// T18（H5/S4）: mutation 後ツリー同期の単一化。全 mutation（split/close/zoom/
// resize/rename/create/focus/workspace・tab CRUD）の成功後に `_syncAfterHerdrMutation`
// 単一経路（force 再取得 → 再解決 → ターゲット変化時のみ _switchHerdrTarget →
// _boostPolling）で同期する。
// T19（S4）: mutation 失敗の分類別通知（target-not-found / invalid_key /
// no-op / server-down / その他）。
// Q-02/Q-05: pane rename / zoom / tab CRUD（create / rename / close）の
// コマンド発行と単一経路同期をカバーする。

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

// 再解決後（w1:p1 消滅・w1:p2 のみ）の snapshot fixture。
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

// 2 pane（w1:p1 / w1:p2）・単一 tab の snapshot fixture（split 後・close 対象判定用）。
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

// 対象が存在しない（panes 空）snapshot fixture（終端判定用）。
const kHerdrEmptySnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":null,"focused_tab_id":null,"focused_workspace_id":null,'
    '"layouts":[],"panes":[],"protocol":17,"tabs":[],"version":"0.7.5",'
    '"workspaces":[]},"type":"session_snapshot"}}';

// S0 実測形状: create --focus 後の snapshot（旧 tab は残存しつつ新タブが focused）。
// 旧 tab w1:t1（w1:p1）が残っていても、focused_tab_id / focused_pane_id /
// active_tab_id の 3 点で新タブ w1:t8（w1:p2）を指す。テスト#10（作成後の自動
// 切替）で「旧 pane 残存でも followBackendFocus が新 pane を優先する」ことを検証。
const kHerdrSnapshotNewTabFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p2","focused_tab_id":"w1:t8",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/a","focused":false,'
    '"foreground_cwd":"/a","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p2","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t8",'
    '"terminal_id":"term_2","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":false,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"},'
    '{"agent_status":"unknown","focused":true,"label":"2","number":2,'
    '"pane_count":1,"tab_id":"w1:t8","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t8",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":2,"tab_count":2,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// focused 情報欠落（全 tab / pane が非フォーカス）の snapshot fixture。
// followBackendFocus では「フォーカス tab → フォーカス pane」が解決できないため
// sticky へフォールバックし、現在表示（w1:p1）を維持することを検証する
// （Codex 観点 4: focused 情報欠落 => 現在の tab を維持）。
const kHerdrSnapshotNoFocusInfoFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":null,"focused_tab_id":null,"focused_workspace_id":null,'
    '"layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":false,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":false,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":false,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// 構造化エラー JSON（target-not-found 分類用）。
const kPaneNotFoundErrorFixture =
    '{"error":{"code":"pane_not_found","message":"no pane"},'
    '"id":"cli:pane:close"}';

// T0 実測 5-b: focus の soft 失敗（no_neighbor・layout 込み）。
const kFocusNoNeighborFixture =
    '{"id":"cli:pane:focus","result":{"focus":{'
    '"changed":false,"focused_pane_id":"w1:p1",'
    '"layout":{"area":{"x":0,"y":0,"width":80,"height":24},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":80,"height":24}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false},'
    '"reason":"no_neighbor","source_pane_id":"w1:p1"},'
    '"type":"pane_focus_direction"}}';

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

List<String> herdrSwitchEvents(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(TerminalScreen));
  return List<String>.from(state.herdrSwitchEventsForTesting());
}

/// herdr（mutation 解禁）のターミナルを起動して返す。
Future<FakeSshClient> _pumpHerdrTerminal(
  WidgetTester tester, {
  Map<String, String> execOutputs = const {},
  Map<String, int> execExitCodes = const {},
  Map<String, List<String>> execOutputQueues = const {},
  Map<String, Exception> execExceptions = const {},
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
    execExitCodes: execExitCodes,
    execOutputQueues: execOutputQueues,
    execExceptions: execExceptions,
    settle: false,
  );
  // 初回接続 + 初回ポーリング分だけ進める。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Pane 1'), findsOneWidget);
  return client;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('T18: mutation 後ツリー同期の単一化（H5/S4）', () {
    testWidgets(
      'syncAfterHerdrMutation 単一経路: force 再取得後にターゲットが変化すると'
      '_switchHerdrTarget で表示切替される',
      (tester) async {
        final client = await _pumpHerdrTerminal(
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
          client.execCommands.where((c) => c.contains('herdr api snapshot'))
              .length,
          greaterThanOrEqualTo(2),
        );

        // SnackBar タイマー / ポーリングを消化してクリーンに終了。
        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'syncAfterHerdrMutation 単一経路: ターゲットが同一なら切替コミットなし',
      (tester) async {
        await _pumpHerdrTerminal(
          tester,
          // force 再取得でも w1:p1 が残る → 表示継続（切替なし）。
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrSnapshotFixture,
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

        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('switch target')),
          isFalse,
          reason: '同一 pane へは切替コミットを発行しない（チラつき防止）',
        );
        expect(find.text('Pane 1'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'split 成功後は単一経路（force 再取得）で反映され、現在 pane が残れば表示継続',
      (tester) async {
        final client = await _pumpHerdrTerminal(
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
          client.execCommands
              .any((c) => c == 'herdr pane split w1:p1 --direction right'),
          isTrue,
          reason: 'split は PaneWriter.splitPane（herdr pane split）で実行されること',
        );
        // 単一経路の force 再取得（接続時 1 回 + split 後 1 回）。
        expect(
          client.execCommands.where((c) => c.contains('herdr api snapshot'))
              .length,
          greaterThanOrEqualTo(2),
          reason: 'split 成功後は _syncAfterHerdrMutation（force 再取得）が走ること',
        );
        // 現在 pane（w1:p1）が snapshot に残るため切替なし・表示継続。
        final events = herdrSwitchEvents(tester);
        expect(events.any((e) => e.contains('switch target')), isFalse);
        expect(find.text('Pane 1'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'focus 成功後は単一経路（force 再取得）で同期され、フォーカス先の pane へ表示が切り替わる',
      (tester) async {
        final client = await _pumpHerdrTerminal(
          tester,
          // 接続時: w1:t1（w1:p1）/ focus 後の force 再取得: 旧 pane は残存しつつ
          // フォーカスは w1:p2 へ移動（S0 実測形状）。スワイプ（方向フォーカス）は
          // フォーカス移動を伴う操作のため followBackendFocus で追従すること。
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrSnapshotNewTabFixture,
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
          client.execCommands
              .any((c) => c == 'herdr pane focus --direction right --pane w1:p1'),
          isTrue,
          reason: 'herdr の方向フォーカスは PaneWriter.focusPaneDirection で実行されること',
        );
        expect(
          client.execCommands.where((c) => c.contains('herdr api snapshot'))
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
      },
    );

    testWidgets(
      'rename pane 成功後は単一経路（force 再取得）で同期される（Q-02）',
      (tester) async {
        final client = await _pumpHerdrTerminal(
          tester,
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrSnapshotFixture,
            ],
          },
        );

        final dynamic state = tester.state(find.byType(TerminalScreen));
        final future = state.renameHerdrPaneForTesting('w1:p1', 'editor');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await future;
        await tester.pump();

        expect(
          client.execCommands.any(
            (c) => c == "herdr pane rename w1:p1 'editor'",
          ),
          isTrue,
          reason: 'pane rename は PaneWriter.renamePane（herdr pane rename）で実行されること',
        );
        expect(
          client.execCommands.where((c) => c.contains('herdr api snapshot'))
              .length,
          greaterThanOrEqualTo(2),
          reason: 'rename pane 成功後も _syncAfterHerdrMutation 単一経路が走ること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'zoom 成功後は単一経路（force 再取得）で同期される（Q-02）',
      (tester) async {
        final client = await _pumpHerdrTerminal(
          tester,
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrSnapshotFixture,
            ],
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
          client.execCommands.where((c) => c.contains('herdr api snapshot'))
              .length,
          greaterThanOrEqualTo(2),
          reason: 'zoom 成功後も _syncAfterHerdrMutation 単一経路が走ること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'create tab（label + --focus）成功後は単一経路（force 再取得）で同期され、'
      '新タブの表示へ自動切替わる（Q-05・タスク②）',
      (tester) async {
        final client = await _pumpHerdrTerminal(
          tester,
          // 接続時: w1:t1（w1:p1）/ create --focus 後の force 再取得: 旧 tab は
          // 残存しつつ新タブ w1:t8（w1:p2）が focused（S0 実測形状）。
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrSnapshotNewTabFixture,
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
          reason: 'tab 作成は PaneWriter.createTab（herdr tab create --label --focus）で実行されること',
        );
        expect(
          client.execCommands.where((c) => c.contains('herdr api snapshot'))
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
      },
    );

    testWidgets(
      '空欄ラベル（null / 空文字）は --label なし + --focus で作成される（Q-05・タスク②）',
      (tester) async {
        final client = await _pumpHerdrTerminal(
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
      },
    );

    testWidgets(
      'ラベル付き create は focus の有無で --focus 付与と表示追従が分岐する'
      '（Q-05・タスク②）',
      (tester) async {
        final client = await _pumpHerdrTerminal(
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
      },
    );

    testWidgets(
      'followBackendFocus でも focused 情報が欠落していれば現在表示を維持する'
      '（タスク②・Codex 観点 ④）',
      (tester) async {
        await _pumpHerdrTerminal(
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
      },
    );

    testWidgets(
      'rename tab 成功後は単一経路（force 再取得）で同期される（Q-05）',
      (tester) async {
        final client = await _pumpHerdrTerminal(
          tester,
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrSnapshotFixture,
            ],
          },
        );

        final dynamic state = tester.state(find.byType(TerminalScreen));
        final future = state.renameHerdrTabForTesting('w1:t1', 'work');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await future;
        await tester.pump();

        expect(
          client.execCommands.any(
            (c) => c == "herdr tab rename w1:t1 'work'",
          ),
          isTrue,
          reason: 'tab rename は PaneWriter.renameTab（herdr tab rename）で実行されること',
        );
        expect(
          client.execCommands.where((c) => c.contains('herdr api snapshot'))
              .length,
          greaterThanOrEqualTo(2),
          reason: 'rename tab 成功後も _syncAfterHerdrMutation 単一経路が走ること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'close tab 成功後に再解決でターゲットが別 pane へ遷移する（単一経路・連鎖遷移）',
      (tester) async {
        final client = await _pumpHerdrTerminal(
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
      },
    );

    testWidgets(
      'close 成功後に再解決でターゲットが別 pane へ遷移する（単一経路・連鎖遷移）',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr pane read': 'hello\n',
          },
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
      },
    );
  });

  group('T19: mutation 失敗の分類別通知（S4）', () {
    testWidgets(
      'target-not-found（pane_not_found）は SnackBar 通知 + 単一経路で再同期する',
      (tester) async {
        final client = await _pumpHerdrTerminal(
          tester,
          // split が pane_not_found で失敗 → 再同期（force 再取得）で w1:p2 へ。
          execOutputs: {
            'herdr pane split': kPaneNotFoundErrorFixture,
          },
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
          client.execCommands.where((c) => c.contains('herdr api snapshot'))
              .length,
          greaterThanOrEqualTo(2),
        );
        expect(find.text('Pane 2'), findsOneWidget);

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );

    testWidgets(
      'close の pane_not_found も SnackBar 通知 + 再同期で復旧する',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
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
          client.execCommands.where((c) => c.contains('herdr api snapshot'))
              .length,
          greaterThanOrEqualTo(2),
        );

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );

    testWidgets(
      'focus の no_neighbor は情報 SnackBar「No pane in that direction」'
      'を表示し、force 再取得しない（T19/T20 no_neighbor 補完）',
      (tester) async {
        final client = await _pumpHerdrTerminal(
          tester,
          // focus が隣接なし（changed:false + reason:no_neighbor）を返す。
          execOutputs: {
            'herdr pane focus': kFocusNoNeighborFixture,
          },
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
          reason: 'no_neighbor は soft 失敗のため _syncAfterHerdrMutation（force 再取得）しない',
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
      },
    );

    testWidgets(
      'rename pane の target-not-found は SnackBar 通知 + 単一経路で再同期する（Q-02）',
      (tester) async {
        await _pumpHerdrTerminal(
          tester,
          // rename が pane_not_found で失敗 → 再同期（force 再取得）で w1:p2 へ。
          execOutputs: {
            'herdr pane rename': kPaneNotFoundErrorFixture,
          },
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
          reason: 'rename pane の target-not-found 後は _syncAfterHerdrMutation で再同期されること',
        );
        expect(find.text('Pane 2'), findsOneWidget);

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );

    testWidgets(
      'zoom の pane_not_found も SnackBar 通知 + 再同期で復旧する（Q-02・移設）',
      (tester) async {
        await _pumpHerdrTerminal(
          tester,
          // zoom が pane_not_found で失敗 → 再同期（force 再取得）で w1:p2 へ。
          execOutputs: {
            'herdr pane zoom': kPaneNotFoundErrorFixture,
          },
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
      },
    );

    testWidgets(
      'close tab の target-not-found も SnackBar 通知 + 再同期で復旧する（Q-05）',
      (tester) async {
        await _pumpHerdrTerminal(
          tester,
          execOutputs: {
            'herdr tab close': kPaneNotFoundErrorFixture,
          },
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
          reason: 'close tab の target-not-found 後は _syncAfterHerdrMutation で再同期されること',
        );

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );

    testWidgets(
      'server-down は既存どおりポーリング停止 + 通知に倒れる',
      (tester) async {
        final client = await _pumpHerdrTerminal(
          tester,
          execExceptions: {
            'herdr pane split': HerdrServerNotRunningException(),
          },
        );

        // server-down 発生前のポーリング read 回数。
        final readsBefore =
            client.execCommands.where((c) => c.contains('herdr pane read'))
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
        final readsAfter =
            client.execCommands.where((c) => c.contains('herdr pane read'))
                .length;
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          client.execCommands.where((c) => c.contains('herdr pane read'))
              .length,
          readsAfter,
          reason: 'server-down 後はポーリングが停止し pane read を再発行しないこと',
        );
        expect(readsBefore, greaterThan(0));

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );

    testWidgets(
      '再同期でも対象が残らない場合は終端通知（再接続しない・R1）',
      (tester) async {
        await _pumpHerdrTerminal(
          tester,
          // close 後（force 再取得）は workspace 消滅（panes 空）。
          execOutputs: {
            'herdr pane close': kPaneNotFoundErrorFixture,
          },
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
      },
    );
  });
}
