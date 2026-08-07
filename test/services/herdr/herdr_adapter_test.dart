import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ssh_client.dart';

const kStatusOk =
    '{"client":{"version":"0.7.5","protocol":17},"server":{"status":"running",'
    '"running":true,"version":"0.7.5","protocol":17,"compatible":true,'
    '"socket":"/tmp/herdr.sock"},"update":{}}';

const kStatusProtocol16 =
    '{"client":{"version":"0.7.5","protocol":17},"server":{"status":"running",'
    '"running":true,"version":"0.7.5","protocol":16,"compatible":false,'
    '"socket":"/tmp/herdr.sock"},"update":{}}';

// 実測: server 非稼働時の `herdr status --json`（protocol が null）。
const kStatusNotRunning =
    '{"client":{"version":"0.7.5","channel":"stable","protocol":17,'
    '"binary":"/lab/herdr","session":null},"server":{"status":"not_running",'
    '"running":false,"version":null,"protocol":null,"capabilities":null,'
    '"compatible":null,"socket":"/home/lab/.config/herdr/herdr.sock",'
    '"session":null,"restart_needed":false},"update":{"restart_needed":false}}';

const kSnapshotOk =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"protocol":17,'
    '"version":"0.7.5","focused_workspace_id":"w1","focused_tab_id":"w1:t1",'
    '"focused_pane_id":"w1:p1","workspaces":[{"workspace_id":"w1",'
    '"label":"lab-ws1","number":1,"focused":true,"agent_status":"unknown",'
    '"pane_count":1,"tab_count":1,"active_tab_id":"w1:t1"}],'
    '"tabs":[{"tab_id":"w1:t1","workspace_id":"w1","label":"1","number":1,'
    '"focused":true,"agent_status":"unknown","pane_count":1}],'
    '"panes":[{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1",'
    '"focused":true,"agent_status":"unknown","cwd":"/tmp",'
    '"foreground_cwd":"/tmp","revision":0,"terminal_id":"term_x"}]},'
    '"type":"session_snapshot"}}';

void main() {
  group('HerdrAdapter.preflight', () {
    test('returns status when protocol is 17', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = kStatusOk;

      final adapter = HerdrAdapter(client);
      final status = await adapter.preflight();

      expect(status.serverProtocol, 17);
      expect(status.clientProtocol, 17);
      expect(status.compatible, isTrue);
    });

    test('throws HerdrProtocolMismatchException when protocol is not 17',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = kStatusProtocol16;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(
          isA<HerdrProtocolMismatchException>()
              .having((e) => e.actual, 'actual', 16)
              .having((e) => e.supported, 'supported', 17),
        ),
      );
    });

    test('throws HerdrServerNotRunningException when server is not running',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = kStatusNotRunning;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(isA<HerdrServerNotRunningException>()),
      );
    });

    test('throws HerdrCommandException when herdr binary is missing',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = '';
      client.execExitCodes['herdr status --json'] = 127;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(
          isA<HerdrCommandException>().having((e) => e.exitCode, 'exitCode', 127),
        ),
      );
    });

    test('throws HerdrCommandException when stderr is non-empty', () async {
      final client = _FakeSshClientWithStderr('herdr: command not found');

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(
          isA<HerdrCommandException>()
              .having((e) => e.message, 'message', contains('command not found')),
        ),
      );
    });

    test('throws HerdrCommandException when output is not valid status JSON',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = 'garbage output';

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(isA<HerdrCommandException>()),
      );
    });
  });

  group('HerdrAdapter.snapshot', () {
    test('parses a snapshot response', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] = kSnapshotOk;

      final adapter = HerdrAdapter(client);
      final snapshot = await adapter.snapshot();

      expect(snapshot.protocol, 17);
      expect(snapshot.version, '0.7.5');
      expect(snapshot.workspaces, hasLength(1));
      expect(snapshot.workspaces.first.id, 'w1');
      expect(snapshot.tabs, hasLength(1));
      expect(snapshot.panes, hasLength(1));
      expect(snapshot.panes.first.cwd, '/tmp');
    });

    test('throws HerdrCommandException with error code on structured error',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] =
          '{"error":{"code":"workspace_not_found","message":"no ws"},'
          '"id":"cli:api:snapshot"}';
      client.execExitCodes['herdr api snapshot'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.snapshot(),
        throwsA(
          isA<HerdrCommandException>()
              .having((e) => e.message, 'message', contains('workspace_not_found')),
        ),
      );
    });

    test('throws HerdrCommandException when output is malformed', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] = 'not json';

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.snapshot(),
        throwsA(isA<HerdrCommandException>()),
      );
    });
  });

  group('HerdrAdapter executable resolution', () {
    test('prefixes commands with the user executable path', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] = kSnapshotOk;
      client.userExecutablePath = '/usr/local/bin/herdr';

      final adapter = HerdrAdapter(client);
      await adapter.snapshot();

      expect(client.execCommands, isNotEmpty);
      expect(
        client.execCommands.first,
        startsWith('/usr/local/bin/herdr api snapshot'),
      );
    });

    test('keeps plain herdr when no user path is set', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] = kSnapshotOk;

      final adapter = HerdrAdapter(client);
      await adapter.snapshot();

      expect(client.execCommands.first, 'herdr api snapshot');
    });

    test('explicit userExecutablePath wins over backend path', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = kStatusOk;
      client.userExecutablePath = '/from/backend/herdr';

      final adapter = HerdrAdapter(
        client,
        userExecutablePath: '/from/constructor/herdr',
      );
      await adapter.preflight();

      expect(
        client.execCommands.first,
        startsWith('/from/constructor/herdr status --json'),
      );
    });
  });
}

/// stderr を返す [FakeSshClient] のスタブ。
class _FakeSshClientWithStderr extends FakeSshClient {
  final String stderr;
  _FakeSshClientWithStderr(this.stderr);

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    execCommands.add(command);
    return (stdout: '', stderr: stderr, exitCode: 0);
  }
}
