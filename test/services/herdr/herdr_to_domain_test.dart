import 'package:flutter_muxpod/services/backend/domain/multiplexer_session.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_parser.dart';
import 'package:flutter_muxpod/services/herdr/herdr_to_domain.dart';
import 'package:flutter_test/flutter_test.dart';

// G4 実測の証跡フィクスチャ（/tmp/herdr-lab/work/evidence/read/12_api_snapshot.json）
const kSnapshotFixture =
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
  group('HerdrSnapshot.toDomainSessions', () {
    test('maps the G4 snapshot fixture to MultiplexerSessions', () {
      final snapshot = HerdrSnapshotParser.parse(kSnapshotFixture);
      final sessions = snapshot.toDomainSessions();

      expect(sessions, hasLength(1));
      final session = sessions.single;
      expect(session, isA<MultiplexerSession>());

      // workspace → session
      expect(session.name, 'lab-ws1'); // label
      expect(session.id, 'w1'); // workspace_id
      expect(session.windowCount, 1); // tab_count
      expect(session.attached, isTrue); // focused

      // tab → window
      final window = session.windows.single;
      expect(window.index, 1); // number
      expect(window.id, 'w1:t1'); // tab_id
      expect(window.name, '1'); // label
      expect(window.active, isTrue); // focused
      expect(window.paneCount, 1); // pane_count

      // pane → pane
      final pane = window.panes.single;
      expect(pane.index, 1); // pane_id "w1:p1" から数値抽出
      expect(pane.id, 'w1:p1'); // pane_id
      expect(pane.active, isTrue); // focused
      expect(pane.currentPath, '/tmp'); // cwd
    });

    test('workspace label が空なら id を session name にする', () {
      const snapshot = HerdrSnapshot(
        workspaces: [HerdrWorkspace(id: 'w9', label: '')],
      );
      final sessions = snapshot.toDomainSessions();
      expect(sessions.single.name, 'w9');
      expect(sessions.single.id, 'w9');
    });

    test('tab label が null なら id を window name にする', () {
      const snapshot = HerdrSnapshot(
        workspaces: [HerdrWorkspace(id: 'w9', label: 'ws', tabCount: 1)],
        tabs: [HerdrTab(id: 'w9:t3', workspaceId: 'w9', number: 3)],
      );
      final sessions = snapshot.toDomainSessions();
      final window = sessions.single.windows.single;
      expect(window.name, 'w9:t3');
      expect(window.index, 3);
    });

    test('cwd が null なら foreground_cwd を使う', () {
      const snapshot = HerdrSnapshot(
        workspaces: [HerdrWorkspace(id: 'w1', label: 'ws', tabCount: 1)],
        tabs: [HerdrTab(id: 'w1:t1', workspaceId: 'w1', number: 1)],
        panes: [
          HerdrPane(
            id: 'w1:t1:p7',
            workspaceId: 'w1',
            tabId: 'w1:t1',
            foregroundCwd: '/fg',
          ),
        ],
      );
      final sessions = snapshot.toDomainSessions();
      final pane = sessions.single.windows.single.panes.single;
      expect(pane.currentPath, '/fg');
      expect(pane.index, 7); // "w1:t1:p7" の末尾数値
    });

    test('pane_id から数値抽出できない場合はリスト順を使う', () {
      const snapshot = HerdrSnapshot(
        workspaces: [HerdrWorkspace(id: 'w1', label: 'ws', tabCount: 1)],
        tabs: [
          HerdrTab(id: 'w1:t1', workspaceId: 'w1', number: 1, paneCount: 2),
        ],
        panes: [
          HerdrPane(id: 'pane-alpha', workspaceId: 'w1', tabId: 'w1:t1'),
          HerdrPane(id: 'pane-beta', workspaceId: 'w1', tabId: 'w1:t1'),
        ],
      );
      final sessions = snapshot.toDomainSessions();
      final panes = sessions.single.windows.single.panes;
      expect(panes, hasLength(2));
      expect(panes[0].index, 0);
      expect(panes[1].index, 1);
    });

    test('workspace ごとに tab/pane をグループ化する', () {
      const snapshot = HerdrSnapshot(
        workspaces: [
          HerdrWorkspace(id: 'w1', label: 'one', tabCount: 2),
          HerdrWorkspace(id: 'w2', label: 'two', tabCount: 1),
        ],
        tabs: [
          HerdrTab(id: 'w1:t1', workspaceId: 'w1', number: 1),
          HerdrTab(id: 'w1:t2', workspaceId: 'w1', number: 2),
          HerdrTab(id: 'w2:t1', workspaceId: 'w2', number: 1),
        ],
        panes: [
          HerdrPane(id: 'w1:t1:p1', workspaceId: 'w1', tabId: 'w1:t1'),
          HerdrPane(id: 'w2:t1:p1', workspaceId: 'w2', tabId: 'w2:t1'),
        ],
      );
      final sessions = snapshot.toDomainSessions();
      expect(sessions, hasLength(2));
      expect(sessions[0].name, 'one');
      expect(sessions[0].windows, hasLength(2));
      expect(sessions[0].windows[0].panes, hasLength(1));
      expect(sessions[1].name, 'two');
      expect(sessions[1].windows, hasLength(1));
      expect(sessions[1].windows[0].panes, hasLength(1));
    });
  });
}
