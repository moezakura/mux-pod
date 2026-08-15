import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/connections/connections_screen.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

import '../../helpers/fake_settings_notifier.dart';
import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/fake_tmux_notifier.dart';

// G4 実測の証跡フィクスチャ（/tmp/herdr-lab/work/evidence/read/12_api_snapshot.json）
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

class _EmptyActiveSessionsNotifier extends ActiveSessionsNotifier {
  @override
  ActiveSessionsState build() => const ActiveSessionsState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // TerminalScreen の _getAuthOptions が platform channel に到達しないよう
    // SecureStorage をテスト値モードにする（TerminalTestScaffold と同じ）。
    SecureStorageService.setTestValues(const {});
    addTearDown(() => SecureStorageService.setTestValues(null));
  });

  testWidgets(
    'herdr connection expands to a session list with workspace operations '
    'enabled (T16/Q-05)',
    (tester) async {
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
      client.execOutputs['herdr pane read'] = 'hello\nworld\n';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionsProvider.overrideWith(
              () => _StaticConnectionsNotifier(connection),
            ),
            activeSessionsProvider.overrideWith(
              () => _EmptyActiveSessionsNotifier(),
            ),
            sshProvider.overrideWith(() => FakeSshNotifier(client: client)),
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                settings: const AppSettings(keepScreenOn: false),
              ),
            ),
            tmuxProvider.overrideWith(
              () => FakeTmuxNotifier(initialState: const TmuxState()),
            ),
          ],
          child: MaterialApp(
            home: ConnectionsScreen(
              sshClientFactory: (_) async {
                client.setConnected(SshConnectionState.connected);
                return client;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Herdr Server'));
      await tester.pumpAndSettle();

      // 共通 domain 表示: workspace label → session 名、tab_count → window 数
      expect(find.text('lab-ws1'), findsOneWidget);
      expect(find.text('1 windows'), findsOneWidget);

      // T16（Q-05）: READ ONLY バッジは表示されない（Attached バッジ表示）。
      expect(find.text('READ ONLY'), findsNothing);
      expect(find.text('Attached'), findsOneWidget);

      // workspace 操作が有効化される（New Workspace / Kill workspace）。
      expect(find.text('New Workspace'), findsOneWidget);
      expect(find.byTooltip('Kill workspace'), findsOneWidget);

      // スナップショットコマンドが実行された
      expect(
        client.execCommands.any((c) => c.contains('herdr api snapshot')),
        isTrue,
      );

      // タップすると TerminalScreen（mutation 可能）が開く
      await tester.tap(find.text('lab-ws1'));
      // 遷移アニメーション + 接続 + 初回ポーリング分だけ進める
      // （ライブポーリングが動き続けるため pumpAndSettle は使わない）
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(TerminalScreen), findsOneWidget);

      // read-only 表示ではなく、mutation UI（SpecialKeysBar）が表示される。
      expect(find.text('READ ONLY — viewing only'), findsNothing);
      expect(find.byType(SpecialKeysBar), findsOneWidget);
    },
  );

  testWidgets(
    'herdr New Workspace creates a workspace via workspace create and refreshes '
    'the list (T16/Q-05)',
    (tester) async {
      final connection = Connection(
        id: 'connection-herdr',
        name: 'Herdr Server',
        host: 'localhost',
        username: 'tester',
        multiplexer: const MultiplexerConfig(backend: BackendType.herdr),
        createdAt: DateTime(2026),
      );
      final client = FakeSshClient();
      // 作成後の snapshot には新しい workspace（w2 / api）が含まれる。
      client.execOutputs['herdr api snapshot'] = kHerdrSnapshotFixture;
      client.execOutputs['herdr pane read'] = 'hello\n';
      client.execOutputQueues['herdr api snapshot'] = [
        kHerdrSnapshotFixture,
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
            '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
            '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"},'
            '{"agent_status":"unknown","focused":false,"label":"1","number":1,'
            '"pane_count":1,"tab_id":"w2:t1","workspace_id":"w2"}],'
            '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
            '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
            '"pane_count":1,"tab_count":1,"workspace_id":"w1"},'
            '{"active_tab_id":"w2:t1","agent_status":"unknown","focused":false,'
            '"label":"api","number":2,"pane_count":1,"tab_count":1,'
            '"workspace_id":"w2"}]},"type":"session_snapshot"}}',
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionsProvider.overrideWith(
              () => _StaticConnectionsNotifier(connection),
            ),
            activeSessionsProvider.overrideWith(
              () => _EmptyActiveSessionsNotifier(),
            ),
            sshProvider.overrideWith(() => FakeSshNotifier(client: client)),
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                settings: const AppSettings(keepScreenOn: false),
              ),
            ),
            tmuxProvider.overrideWith(
              () => FakeTmuxNotifier(initialState: const TmuxState()),
            ),
          ],
          child: MaterialApp(
            home: ConnectionsScreen(
              sshClientFactory: (_) async {
                client.setConnected(SshConnectionState.connected);
                return client;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Herdr Server'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New Workspace'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'api');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // `herdr workspace create` が発行される。
      expect(
        client.execCommands.any(
          (c) => c.contains('herdr workspace create') && c.contains('api'),
        ),
        isTrue,
        reason: 'herdr の New Workspace は workspace create を発行すること',
      );

      // 一覧が再取得され、新しい workspace（api）が表示される。
      expect(find.text('api'), findsOneWidget);
      expect(find.text('lab-ws1'), findsOneWidget);
    },
  );

  testWidgets(
    'herdr Kill Workspace confirms the chain close and closes the workspace '
    '(T16/Q-05)',
    (tester) async {
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
      client.execOutputs['herdr pane read'] = 'hello\n';
      // kill 後の snapshot は workspace が消える。
      client.execOutputQueues['herdr api snapshot'] = [
        kHerdrSnapshotFixture,
        '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
            '"focused_pane_id":null,"focused_tab_id":null,'
            '"focused_workspace_id":null,"layouts":[],"panes":[],"protocol":17,'
            '"tabs":[],"version":"0.7.5","workspaces":[]},'
            '"type":"session_snapshot"}}',
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionsProvider.overrideWith(
              () => _StaticConnectionsNotifier(connection),
            ),
            activeSessionsProvider.overrideWith(
              () => _EmptyActiveSessionsNotifier(),
            ),
            sshProvider.overrideWith(() => FakeSshNotifier(client: client)),
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                settings: const AppSettings(keepScreenOn: false),
              ),
            ),
            tmuxProvider.overrideWith(
              () => FakeTmuxNotifier(initialState: const TmuxState()),
            ),
          ],
          child: MaterialApp(
            home: ConnectionsScreen(
              sshClientFactory: (_) async {
                client.setConnected(SshConnectionState.connected);
                return client;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Herdr Server'));
      await tester.pumpAndSettle();

      // Kill workspace（連鎖 close の警告ダイアログ）。
      await tester.tap(find.byTooltip('Kill workspace'));
      await tester.pumpAndSettle();
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

      // 再度 Kill → Close で workspace close が発行され、一覧から消える。
      await tester.tap(find.byTooltip('Kill workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(
        client.execCommands.any(
          (c) => c.contains('herdr workspace close') && c.contains('w1'),
        ),
        isTrue,
        reason: 'herdr の Kill Workspace は workspace close w1 を発行すること',
      );
      expect(find.text('lab-ws1'), findsNothing);
    },
  );

  testWidgets('tmux connection keeps the existing session UI unchanged', (
    tester,
  ) async {
    final connection = Connection(
      id: 'connection-tmux',
      name: 'Tmux Server',
      host: 'localhost',
      username: 'tester',
      multiplexer: const MultiplexerConfig.tmux(),
      createdAt: DateTime(2026),
    );
    final client = FakeSshClient();
    client.execOutputs['list-sessions'] =
        'mysession\x1f1735689700\x1f0\x1f1\x1f\$1\x1e';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionsProvider.overrideWith(
            () => _StaticConnectionsNotifier(connection),
          ),
          activeSessionsProvider.overrideWith(
            () => _EmptyActiveSessionsNotifier(),
          ),
        ],
        child: MaterialApp(
          home: ConnectionsScreen(
            sshClientFactory: (_) async {
              client.setConnected(SshConnectionState.connected);
              return client;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tmux Server'));
    await tester.pumpAndSettle();

    // 既存の tmux 表示（New Session / Kill ボタン / Attached バッジ）が維持される
    expect(find.text('mysession'), findsOneWidget);
    expect(find.text('New Session'), findsOneWidget);
    expect(find.byTooltip('Kill session'), findsOneWidget);
    expect(find.text('READ ONLY'), findsNothing);
  });
}
