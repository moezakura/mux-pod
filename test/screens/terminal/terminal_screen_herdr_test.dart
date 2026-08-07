import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

import '../../helpers/terminal_test_scaffold.dart';

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
      expect(
        client.execCommands.any((c) => c.contains('set-option')),
        isFalse,
      );

      // スナップショットから pane を解決し、pane read で内容を取得する。
      expect(
        client.execCommands.any((c) => c.contains('herdr api snapshot')),
        isTrue,
      );
      expect(
        client.execCommands.any(
          (c) => c.contains('herdr pane read w1:p1 --source recent --lines 120 --raw'),
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
          (c) => c.contains('herdr pane read w1:p1 --source recent --lines 120 --raw'),
        ),
        isTrue,
      );
      expect(find.textContaining('injected content'), findsWidgets);
    });
  });
}
