import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_writer.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

import '../../helpers/terminal_test_scaffold.dart';

// H4 等価性テスト（T4 基本版）:
// `_can(capability)` が操作単位の能力判定になることを検証する。
// - herdr（T13 フリップ後）: mutation の各能力は有効、copy-mode / absoluteResize
//   は設計上 false。
// - tmux: 全 capability true → mutation 有効。
//
// UI の期待（SpecialKeysBar 表示・未接続バナー非表示）も併せて検証する。
// ※ 未接続時のみ全能力 false。接続後はバックエンドの能力に応じて操作単位で
//   有効化される。

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

/// 14 能力それぞれを要求する `PaneCapabilities` の一覧（T4 の全 capability 検証用）。
const List<PaneCapabilities> kAllCapabilityRequirements = [
  PaneCapabilities(sendText: true),
  PaneCapabilities(sendKeys: true),
  PaneCapabilities(focus: true),
  PaneCapabilities(split: true),
  PaneCapabilities(close: true),
  PaneCapabilities(rename: true),
  PaneCapabilities(zoom: true),
  PaneCapabilities(resize: true),
  PaneCapabilities(paste: true),
  PaneCapabilities(copyMode: true),
  PaneCapabilities(imageTransfer: true),
  PaneCapabilities(workspaceCrud: true),
  PaneCapabilities(tabCrud: true),
  PaneCapabilities(absoluteResize: true),
];

dynamic _state(WidgetTester tester) =>
    tester.state(find.byType(TerminalScreen));

void main() {
  group('TerminalScreen _can framework (T4・H4 等価性 → Phase 2 フリップ T13)', () {
    testWidgets(
      'herdr backend: mutation capabilities enabled (T13)',
      (tester) async {
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

        final state = _state(tester);
        // 解禁された能力は true（Q-02・T13/T15 フリップ）。
        for (final required in [
          PaneCapabilities(sendText: true),
          PaneCapabilities(sendKeys: true),
          PaneCapabilities(focus: true),
          PaneCapabilities(split: true),
          PaneCapabilities(close: true),
          PaneCapabilities(rename: true),
          PaneCapabilities(zoom: true),
          PaneCapabilities(resize: true),
          PaneCapabilities(paste: true),
          PaneCapabilities(imageTransfer: true),
          PaneCapabilities(workspaceCrud: true),
          PaneCapabilities(tabCrud: true),
        ]) {
          expect(
            state.canForTesting(required),
            isTrue,
            reason: 'capability ${required.toString()} must be true',
          );
        }
        // 設計上 false の能力（copy-mode なし・相対 resize のみ・Q-04）。
        for (final required in [
          PaneCapabilities(copyMode: true),
          PaneCapabilities(absoluteResize: true),
        ]) {
          expect(
            state.canForTesting(required),
            isFalse,
            reason: 'capability ${required.toString()} must be false',
          );
        }
        final caps = state.paneCapabilitiesForTesting();
        expect(caps.sendText, isTrue);
        expect(caps.imageTransfer, isTrue);
        expect(caps.absoluteResize, isFalse);

        // UI: SpecialKeysBar 表示・未接続バナー非表示（mutation 解禁）。
        expect(find.byType(SpecialKeysBar), findsOneWidget);
        expect(find.text('Not connected — viewing only'), findsNothing);

        // `_scrollToCaret` の 100ms 遅延タイマーを消化してクリーンに終了
        // （dispose でキャンセルされないためテスト終端で pending になる）。
        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets('tmux backend: 全 capability true → mutation 有効', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);

      final state = _state(tester);
      // tmux は全 capability true
      for (final required in kAllCapabilityRequirements) {
        expect(
          state.canForTesting(required),
          isTrue,
          reason: 'capability ${required.toString()} must be true',
        );
      }
      // 複数能力の同時要求も満たす（要求 ⊆ 現在能力）
      expect(
        state.canForTesting(
          const PaneCapabilities(sendText: true, focus: true, split: true),
        ),
        isTrue,
      );

      // UI: SpecialKeysBar 表示・未接続バナー非表示
      expect(find.byType(SpecialKeysBar), findsOneWidget);
      expect(find.text('Not connected — viewing only'), findsNothing);

      // `_scrollToCaret` の 100ms 遅延タイマーを消化してクリーンに終了。
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('T9: stale tmuxProvider 対策（clear()）', () {
    testWidgets('herdr セッション確立時に stale tmuxProvider が clear() される', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        // 接続前に stale な tmux 状態（残骸）を注入しておく。
        tmuxInitialState: TmuxState(
          sessions: [
            TmuxSession(
              name: 'stale-session',
              windows: [
                TmuxWindow(
                  index: 0,
                  name: 'stale-win',
                  panes: const [
                    TmuxPane(index: 0, id: 'stale-p1', active: true),
                  ],
                ),
              ],
            ),
          ],
          activeSessionName: 'stale-session',
          activeWindowIndex: 0,
          activePaneId: 'stale-p1',
        ),
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final state = container.read(tmuxProvider);
      // R3: 残骸（activePaneId / currentTarget 等）が herdr 操作へ混入しない。
      expect(
        state.activeSessionName,
        isNull,
        reason: 'stale tmuxProvider は herdr セッション確立時に clear() で破棄される',
      );
      expect(state.activePaneId, isNull);
      expect(state.sessions, isEmpty);

      // `_scrollToCaret` の 100ms 遅延タイマーを消化してクリーンに終了。
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('_disconnect 時に tmuxProvider が clear() される（両 backend）', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      // tmux 接続後はアクティブ状態が入っている（scaffold の list-panes fixture）。
      expect(container.read(tmuxProvider).activeSessionName, isNotNull);

      // 設定メニュー → Disconnect で切断（TERM-DIALOG-011 と同じ経路）。
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      // 確認ダイアログの確定ボタン（Disconnect ダイアログの Close）を押す。
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      final cleared = container.read(tmuxProvider);
      expect(cleared.activeSessionName, isNull);
      expect(cleared.activePaneId, isNull);
      expect(cleared.sessions, isEmpty);
    });
  });
}
