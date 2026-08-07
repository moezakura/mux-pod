import 'package:flutter_muxpod/services/herdr/herdr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// G4 実測の証跡フィクスチャ（byte-for-byte）:
//   /tmp/herdr-lab/work/evidence/read/12_api_snapshot.json
//   /tmp/herdr-lab/work/evidence/compat/status_client_server.json
const kSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[{"area":{"height":23,"width":54,'
    '"x":26,"y":1},"focused_pane_id":"w1:p1","panes":[{"focused":true,'
    '"pane_id":"w1:p1","rect":{"height":23,"width":54,"x":26,"y":1}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
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

const kStatusFixture =
    '{"client":{"version":"0.7.5","channel":"stable","protocol":17,'
    '"binary":"/lab/herdr","session":null},"server":{"status":"running",'
    '"running":true,"version":"0.7.5","protocol":17,'
    '"capabilities":{"live_handoff":true,"detached_server_daemon":true},'
    '"compatible":true,"socket":"/home/lab/.config/herdr/herdr.sock",'
    '"session":null,"restart_needed":false},"update":{"restart_needed":false}}';

// 実測: server 非稼働時の `herdr status --json`（`server.protocol` が null）。
const kStatusNotRunningFixture =
    '{"client":{"version":"0.7.5","channel":"stable","protocol":17,'
    '"binary":"/lab/herdr","session":null},"server":{"status":"not_running",'
    '"running":false,"version":null,"protocol":null,"capabilities":null,'
    '"compatible":null,"socket":"/home/lab/.config/herdr/herdr.sock",'
    '"session":null,"restart_needed":false},"update":{"restart_needed":false}}';

void main() {
  group('HerdrSnapshotParser', () {
    test('parses the G4 api snapshot fixture', () {
      final snapshot = HerdrSnapshotParser.parse(kSnapshotFixture);

      expect(snapshot.protocol, 17);
      expect(snapshot.version, '0.7.5');
      expect(snapshot.focusedWorkspaceId, 'w1');
      expect(snapshot.focusedTabId, 'w1:t1');
      expect(snapshot.focusedPaneId, 'w1:p1');

      // workspace
      expect(snapshot.workspaces, hasLength(1));
      final ws = snapshot.workspaces.first;
      expect(ws.id, 'w1');
      expect(ws.label, 'lab-ws1');
      expect(ws.number, 1);
      expect(ws.focused, isTrue);
      expect(ws.agentStatus, 'unknown');
      expect(ws.paneCount, 1);
      expect(ws.tabCount, 1);
      expect(ws.activeTabId, 'w1:t1');

      // tab
      expect(snapshot.tabs, hasLength(1));
      final tab = snapshot.tabs.first;
      expect(tab.id, 'w1:t1');
      expect(tab.workspaceId, 'w1');
      expect(tab.label, '1');
      expect(tab.number, 1);
      expect(tab.focused, isTrue);
      expect(tab.paneCount, 1);

      // pane
      expect(snapshot.panes, hasLength(1));
      final pane = snapshot.panes.first;
      expect(pane.id, 'w1:p1');
      expect(pane.workspaceId, 'w1');
      expect(pane.tabId, 'w1:t1');
      expect(pane.focused, isTrue);
      expect(pane.cwd, '/tmp');
      expect(pane.foregroundCwd, '/tmp');
      expect(pane.revision, 0);
      expect(pane.terminalId, 'term_6586edf6f766f1');
    });

    test('hierarchy helpers group tabs and panes by parent id', () {
      final snapshot = HerdrSnapshotParser.parse(kSnapshotFixture);
      final ws = snapshot.workspaces.first;
      final tab = snapshot.tabs.first;

      expect(snapshot.tabsFor(ws), hasLength(1));
      expect(snapshot.tabsFor(ws).first.id, 'w1:t1');
      expect(snapshot.panesFor(tab), hasLength(1));
      expect(snapshot.panesFor(tab).first.id, 'w1:p1');
    });

    test('tolerates missing optional fields', () {
      const json =
          '{"id":"cli:api:snapshot","result":{"snapshot":{"protocol":17,'
          '"version":"0.7.5","workspaces":[],"tabs":[],"panes":[]},'
          '"type":"session_snapshot"}}';
      final snapshot = HerdrSnapshotParser.parse(json);
      expect(snapshot.protocol, 17);
      expect(snapshot.focusedWorkspaceId, isNull);
      expect(snapshot.focusedTabId, isNull);
      expect(snapshot.focusedPaneId, isNull);
      expect(snapshot.workspaces, isEmpty);
    });

    test('throws FormatException on malformed JSON', () {
      expect(
        () => HerdrSnapshotParser.parse('not json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when snapshot key is missing', () {
      const json =
          '{"id":"cli:api:snapshot","result":{"type":"session_snapshot"}}';
      expect(
        () => HerdrSnapshotParser.parse(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException on error response', () {
      const json = '{"error":{"code":"pane_not_found","message":"x"},'
          '"id":"cli:pane:get"}';
      expect(
        () => HerdrSnapshotParser.parse(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HerdrStatusParser', () {
    test('parses the G4 status fixture', () {
      final status = HerdrStatusParser.parse(kStatusFixture);
      expect(status.clientVersion, '0.7.5');
      expect(status.clientProtocol, 17);
      expect(status.serverVersion, '0.7.5');
      expect(status.serverProtocol, 17);
      expect(status.serverStatus, 'running');
      expect(status.running, isTrue);
      expect(status.compatible, isTrue);
      expect(status.socket, '/home/lab/.config/herdr/herdr.sock');
    });

    test('defaults missing protocol fields to 0', () {
      const json = '{"client":{},"server":{},"update":{}}';
      final status = HerdrStatusParser.parse(json);
      expect(status.clientProtocol, 0);
      expect(status.serverProtocol, 0);
      expect(status.running, isFalse);
      expect(status.compatible, isFalse);
    });

    test('parses server-not-running status (protocol null -> 0)', () {
      final status = HerdrStatusParser.parse(kStatusNotRunningFixture);
      // server.protocol が null でも _asInt のフォールバックで 0 になる。
      // server 未稼働の判定は running == false が正信号。
      expect(status.serverProtocol, 0);
      expect(status.clientProtocol, 17);
      expect(status.running, isFalse);
      expect(status.serverStatus, 'not_running');
      expect(status.serverVersion, isNull);
      expect(status.compatible, isFalse);
      expect(status.socket, '/home/lab/.config/herdr/herdr.sock');
    });

    test('throws FormatException on malformed JSON', () {
      expect(
        () => HerdrStatusParser.parse('not json'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
