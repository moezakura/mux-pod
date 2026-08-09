import 'package:flutter_muxpod/services/backend/domain/pane_content_reader.dart';
import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_pane_content_reader.dart';
import 'package:flutter_muxpod/services/tmux/tmux_pane_content_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_ssh_client.dart';

// G4 実測のスナップショット fixture（pane 解決用）。
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

void main() {
  group('MultiplexerPaneSnapshot', () {
    test('defaults cursor, mode, and size for backends without them', () {
      const snapshot = MultiplexerPaneSnapshot(content: 'hello');
      expect(snapshot.width, 0);
      expect(snapshot.height, 0);
      expect(snapshot.cursorX, 0);
      expect(snapshot.cursorY, 0);
      expect(snapshot.paneMode, '');
      expect(snapshot.hasAnsi, isFalse);
    });
  });

  group('TmuxPaneContentReader', () {
    test('poll path maps cursor, size, and mode into the snapshot', () async {
      final client = FakeSshClient();
      // capture-pane + カーソル + モードの複合出力（pollPane 形式）。
      // 末尾は display-message の改行1つ分（scaffold と同じ形式）。
      client.execOutputs['capture-pane'] = 'hello\n7,8,90,30\n';

      final reader = TmuxPaneContentReader(client);
      final snapshot = await reader.readPane(
        paneId: '%0',
        historyLines: -120,
      );

      expect(snapshot.content, 'hello');
      expect(snapshot.cursorX, 7);
      expect(snapshot.cursorY, 8);
      expect(snapshot.width, 90);
      expect(snapshot.height, 30);
      expect(
        client.execPersistentCommands.any((c) => c.contains('capture-pane')),
        isTrue,
      );
    });

    test('deep history path uses capturePane with the start line', () async {
      final client = FakeSshClient();
      client.execOutputs['capture-pane'] = 'deep-line-1\ndeep-line-2\n';

      final reader = TmuxPaneContentReader(client);
      final snapshot = await reader.readPane(
        paneId: '%0',
        historyLines: -100000,
      );

      expect(snapshot.content, 'deep-line-1\ndeep-line-2');
      expect(
        client.execCommands.any((c) => c.contains('capture-pane -t %0 -p -e -S -100000')),
        isTrue,
      );
      // 深い履歴は exec チャネル（poll の persistent ではない）で実行される。
      expect(
        client.execPersistentCommands.any((c) => c.contains('capture-pane')),
        isFalse,
      );
    });

    test('null historyLines uses the live poll default window', () async {
      final client = FakeSshClient();
      client.execOutputs['capture-pane'] = 'hello\n0,0,80,24\n';

      final reader = TmuxPaneContentReader(client);
      final snapshot = await reader.readPane(paneId: '%0');

      expect(snapshot.content, 'hello');
      expect(snapshot.width, 80);
      expect(snapshot.height, 24);
    });
  });

  group('HerdrPaneContentReader', () {
    test('reads pane output with --raw and maps to a fallback snapshot',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = '\x1b[32mok\x1b[0m\nnext\n';

      final reader = HerdrPaneContentReader(HerdrAdapter(client));
      final snapshot = await reader.readPane(paneId: 'w1:p1', historyLines: -120);

      expect(
        client.execCommands,
        contains('herdr pane read w1:p1 --source recent --lines 120 --raw'),
      );
      expect(snapshot.content, '\x1b[32mok\x1b[0m\nnext');
      expect(snapshot.hasAnsi, isTrue);
      // herdr には無い情報はフォールバック値のまま。
      expect(snapshot.cursorX, 0);
      expect(snapshot.cursorY, 0);
      expect(snapshot.paneMode, '');
      expect(snapshot.width, 0);
      expect(snapshot.height, 0);
    });

    test('deep history requests a large line count', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = 'line1\nline2\n';

      final reader = HerdrPaneContentReader(HerdrAdapter(client));
      await reader.readPane(paneId: 'w1:p1', historyLines: -100000);

      expect(
        client.execCommands,
        contains('herdr pane read w1:p1 --source recent --lines 100000 --raw'),
      );
    });
  });
}
