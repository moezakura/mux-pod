import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/dashboard/dashboard_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';

// T16（Q-05）: dashboard からの herdr workspace 操作（New / Kill）。

// G4 実測の snapshot fixture（w1 / lab-ws1）。
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

class _StaticConnectionsNotifier extends ConnectionsNotifier {
  _StaticConnectionsNotifier(this.connection);

  final Connection connection;

  @override
  ConnectionsState build() => ConnectionsState(connections: [connection]);
}

class _HerdrActiveSessionsNotifier extends ActiveSessionsNotifier {
  @override
  ActiveSessionsState build() {
    return ActiveSessionsState(
      sessions: [
        ActiveSession(
          connectionId: 'connection-herdr',
          connectionName: 'Herdr Server',
          host: 'localhost',
          sessionName: 'lab-ws1',
          sessionId: 'w1',
          windowCount: 1,
          connectedAt: DateTime(2026, 1, 1),
          backend: MultiplexerBackendKind.herdr,
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setTestValues(const {});
    addTearDown(() => SecureStorageService.setTestValues(null));
  });

  Future<FakeSshClient> pumpDashboard(
    WidgetTester tester, {
    Map<String, String> execOutputs = const {},
    Map<String, List<String>> execOutputQueues = const {},
  }) async {
    final connection = Connection(
      id: 'connection-herdr',
      name: 'Herdr Server',
      host: 'localhost',
      username: 'tester',
      multiplexer: const MultiplexerConfig(backend: BackendType.herdr),
      createdAt: DateTime(2026),
    );
    final client = FakeSshClient();
    client.execOutputs['herdr api snapshot'] = kHerdrSnapshotFixture;
    client.execOutputs.addAll(execOutputs);
    client.execOutputQueues.addAll(execOutputQueues);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionsProvider.overrideWith(
            () => _StaticConnectionsNotifier(connection),
          ),
          activeSessionsProvider.overrideWith(
            () => _HerdrActiveSessionsNotifier(),
          ),
          sshProvider.overrideWith(() => FakeSshNotifier(client: client)),
        ],
        child: MaterialApp(
          home: DashboardScreen(
            sshClientFactory: (_) async {
              client.setConnected(SshConnectionState.connected);
              return client;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return client;
  }

  testWidgets(
    'herdr session card shows workspace actions and no READ ONLY badge '
    '(T16/Q-05)',
    (tester) async {
      await pumpDashboard(tester);

      expect(find.text('Herdr Server: lab-ws1'), findsOneWidget);
      expect(find.text('READ ONLY'), findsNothing);
      expect(find.byTooltip('Workspace actions'), findsOneWidget);
    },
  );

  testWidgets(
    'dashboard Kill Workspace confirms the chain close and closes the '
    'workspace (T16/Q-05)',
    (tester) async {
      final client = await pumpDashboard(
        tester,
        // kill 後の snapshot は workspace が消える。
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotFixture,
            '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
            '"focused_pane_id":null,"focused_tab_id":null,'
            '"focused_workspace_id":null,"layouts":[],"panes":[],'
            '"protocol":17,"tabs":[],"version":"0.7.5","workspaces":[]},'
            '"type":"session_snapshot"}}',
          ],
        },
      );

      await tester.tap(find.byTooltip('Workspace actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kill Workspace'));
      await tester.pumpAndSettle();

      // 連鎖 close の警告ダイアログ。
      expect(find.text('Close Workspace?'), findsOneWidget);
      expect(
        find.textContaining('All tabs and panes in this workspace'),
        findsOneWidget,
        reason: '連鎖 close の警告が表示されること（R2）',
      );

      // Cancel では close されない。
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        client.execCommands.any((c) => c.contains('herdr workspace close')),
        isFalse,
        reason: 'キャンセル時は workspace close を発行しないこと',
      );

      // 再度 Kill → Close で workspace close が発行され、履歴から消える。
      await tester.tap(find.byTooltip('Workspace actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kill Workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(
        client.execCommands.any(
          (c) => c.contains('herdr workspace close') && c.contains('w1'),
        ),
        isTrue,
        reason: 'dashboard の Kill Workspace は workspace close w1 を発行すること',
      );
      expect(find.text('Herdr Server: lab-ws1'), findsNothing);
    },
  );

  testWidgets(
    'dashboard New Workspace creates a workspace via workspace create '
    '(T16/Q-05)',
    (tester) async {
      // 作成後の snapshot（最初の取得が create 後なので、これが唯一の fixture）。
      const withApiSnapshot =
          '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
          '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
          '"focused_workspace_id":"w1","layouts":[],'
          '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
          '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
          '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
          '"viewport_rows":23},"tab_id":"w1:t1",'
          '"terminal_id":"term_1","workspace_id":"w1"},'
          '{"agent_status":"unknown","cwd":"/root","focused":false,'
          '"foreground_cwd":"/root","pane_id":"w2:p1","revision":0,'
          '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
          '"viewport_rows":23},"tab_id":"w2:t1",'
          '"terminal_id":"term_2","workspace_id":"w2"}],"protocol":17,'
          '"tabs":[{"agent_status":"unknown","focused":true,"label":"1",'
          '"number":1,"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"},'
          '{"agent_status":"unknown","focused":false,"label":"1","number":1,'
          '"pane_count":1,"tab_id":"w2:t1","workspace_id":"w2"}],'
          '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
          '"agent_status":"unknown","focused":true,"label":"lab-ws1",'
          '"number":1,"pane_count":1,"tab_count":1,"workspace_id":"w1"},'
          '{"active_tab_id":"w2:t1","agent_status":"unknown",'
          '"focused":false,"label":"api","number":2,"pane_count":1,'
          '"tab_count":1,"workspace_id":"w2"}]},"type":"session_snapshot"}}';
      final client = await pumpDashboard(
        tester,
        execOutputs: {'herdr api snapshot': withApiSnapshot},
      );

      await tester.tap(find.byTooltip('Workspace actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Workspace'));
      await tester.pumpAndSettle();
      expect(find.text('New Workspace'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'api');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // `herdr workspace create` が発行され、一覧に新しい workspace が表示される。
      expect(
        client.execCommands.any(
          (c) => c.contains('herdr workspace create') && c.contains('api'),
        ),
        isTrue,
        reason: 'dashboard の New Workspace は workspace create を発行すること',
      );
      expect(find.text('Herdr Server: api'), findsOneWidget);
    },
  );
}
