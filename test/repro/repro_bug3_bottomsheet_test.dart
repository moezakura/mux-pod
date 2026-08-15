// Repro: バグ3 ボトムシートを開くと一瞬表示され、すぐに閉じてしまう
//
// 再現条件（静的解析による推定）:
// - _showMultiplexerSheet は showModalBottomSheet(isDismissible: true,
//   enableDrag: true) でシートを表示する（terminal_screen.dart:3941-3948）
// - 親 (TerminalScreen) の rebuild は sshProvider リスナーの setState
//   （L788-791）が唯一の経路。ポーリング（L2411-2413 コメント）や
//   tmuxProvider（L794-803 コメント）は親 rebuild を起こさない設計
// - シート表示中に sshProvider の state が変化すると親が rebuild され、
//   シートが閉じる可能性がある
//
// このテストは「sshProvider の state 変化 → 親 rebuild → シートが閉じるか」を
// widget テストで確認する。実機では SSH 接続状態の遷移（keep-alive タイムアウト
// → 再接続、ネットワーク断など）が同様の変化を引き起こす。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';

import '../helpers/fake_ssh_notifier.dart';
import '../helpers/terminal_test_scaffold.dart';

// T10 テストと同じ herdr 2-workspace snapshot fixture。
const _kHerdrTwoWorkspaceSnapshot =
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
  group('Repro BUG-3: ボトムシートが sshProvider 変化で閉じる', () {
    testWidgets('セレクタ表示中に sshProvider の state が変化するとシートが閉じる', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        readOnly: true,
        execOutputs: {
          'herdr api snapshot': _kHerdrTwoWorkspaceSnapshot,
          'herdr pane read w1:p1': 'content from p1\n',
          'herdr pane read w2:p1': 'content from p2\n',
        },
        settle: false,
      );

      // workspace セレクタ（Select Session）を開く
      await tester.tap(find.text('lab-ws1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Select Session'),
        findsOneWidget,
        reason: '前提: シートが表示されている',
      );

      // sshProvider の state を変更（再接続 → disconnected に遷移）し、
      // 親 rebuild（L788-791 の setState）を誘発する。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;
      await notifier.reconnect();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // シートがまだ表示されているか（バグがあれば閉じている）
      final sheetStillVisible = find
          .text('Select Session')
          .evaluate()
          .isNotEmpty;
      debugPrint(
        '[Repro BUG-3] sshProvider 変化後のシート表示状態: '
        '${sheetStillVisible ? "表示継続" : "閉じた"}',
      );
      // NOTE: これは再現観察用。テスト環境では実機と挙動が異なる可能性があるため、
      // ここでは「閉じた場合にバグとして記録する」形にせず、観察結果を出力する。
      expect(
        sheetStillVisible,
        isTrue,
        reason:
            'バグ再現: sshProvider の state 変化でボトムシートが閉じた。'
            '実機では SSH 接続状態遷移（keep-alive タイムアウト / 再接続 / '
            'ネットワーク断）が同様にシートを閉じる',
      );
    });

    testWidgets('セレクタ表示中に sshProvider が変化しなければシートは安定表示される'
        '（比較対象: T10 正常系）', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        readOnly: true,
        execOutputs: {
          'herdr api snapshot': _kHerdrTwoWorkspaceSnapshot,
          'herdr pane read w1:p1': 'content from p1\n',
          'herdr pane read w2:p1': 'content from p2\n',
        },
        settle: false,
      );

      await tester.tap(find.text('lab-ws1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Session'), findsOneWidget);

      // 状態変化なしでポーリングを進めてもシートは表示されたまま
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Select Session'),
        findsOneWidget,
        reason: 'sshProvider が変化しない限りシートは安定表示される',
      );
    });
  });
}
