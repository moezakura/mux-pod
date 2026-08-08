import 'package:flutter_muxpod/services/connection_error.dart';
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

    test(
      'throws SshConnectionError when the channel closes without exit status '
      'or output (SSH/transport anomaly, not a herdr command failure)',
      () async {
        final client = _FakeSshClientNullExit();

        final adapter = HerdrAdapter(client);
        await expectLater(
          adapter.snapshot(),
          throwsA(isA<SshConnectionError>()),
        );
      },
    );

    test(
      'treats exit code null with non-empty stdout as success '
      '(output obtained, exit status lost)',
      () async {
        final client = _FakeSshClientNullExitWithOutput(kSnapshotOk);

        final adapter = HerdrAdapter(client);
        final snapshot = await adapter.snapshot();

        expect(snapshot.workspaces, hasLength(1));
        expect(snapshot.workspaces.first.id, 'w1');
      },
    );

    test('throws HerdrTargetNotFoundException for workspace_not_found code',
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
          isA<HerdrTargetNotFoundException>()
              .having((e) => e.kind, 'kind', HerdrTargetNotFoundKind.workspace)
              .having((e) => e.errorCode, 'errorCode', 'workspace_not_found')
              .having(
                (e) => e.message,
                'message',
                contains('workspace_not_found'),
              ),
        ),
      );
    });

    test('throws HerdrCommandException with errorCode for non-target error code',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] =
          '{"error":{"code":"internal_error","message":"boom"},'
          '"id":"cli:api:snapshot"}';
      client.execExitCodes['herdr api snapshot'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.snapshot(),
        throwsA(
          isA<HerdrCommandException>()
              .having((e) => e.errorCode, 'errorCode', 'internal_error')
              .having((e) => e.message, 'message', contains('internal_error')),
        ),
      );
    });

    test('extracts error code from stderr', () async {
      final client = _FakeSshClientWithStderr(
        '{"error":{"code":"pane_not_found","message":"no pane"},'
        '"id":"cli:pane:get"}',
      );

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.paneRead('w1:p1'),
        throwsA(
          isA<HerdrTargetNotFoundException>()
              .having((e) => e.kind, 'kind', HerdrTargetNotFoundKind.pane)
              .having((e) => e.errorCode, 'errorCode', 'pane_not_found'),
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

  group('HerdrAdapter.paneRead', () {
    test('reads pane content with default options', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = 'hello\nworld\n';

      final adapter = HerdrAdapter(client);
      final content = await adapter.paneRead('w1:p1');

      expect(client.execCommands, contains('herdr pane read w1:p1 --source recent'));
      expect(content.rawText, 'hello\nworld');
      expect(content.lines, ['hello', 'world']);
      expect(content.hasAnsi, isFalse);
    });

    test('passes source, lines, and --raw through to the command', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = '\x1b[32mok\x1b[0m\n';

      final adapter = HerdrAdapter(client);
      await adapter.paneRead('w1:p1', source: 'visible', lines: 120, ansi: true);

      expect(
        client.execCommands,
        contains('herdr pane read w1:p1 --source visible --lines 120 --raw'),
      );
    });

    test('marks content as ANSI when --raw is requested', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = '\x1b[32mok\x1b[0m\n';

      final adapter = HerdrAdapter(client);
      final content = await adapter.paneRead('w1:p1', ansi: true);

      expect(content.hasAnsi, isTrue);
    });

    test('throws HerdrCommandException on non-zero exit', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = '';
      client.execExitCodes['herdr pane read'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.paneRead('w1:p1'),
        throwsA(
          isA<HerdrCommandException>().having((e) => e.exitCode, 'exitCode', 1),
        ),
      );
    });

    test('prefixes pane read with the user executable path', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = 'hello\n';
      client.userExecutablePath = '/usr/local/bin/herdr';

      final adapter = HerdrAdapter(client);
      await adapter.paneRead('w1:p1');

      expect(
        client.execCommands.first,
        startsWith('/usr/local/bin/herdr pane read w1:p1'),
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

/// exitCode null・出力なしで戻す [FakeSshClient] のスタブ。
///
/// SSH exec チャネルが終了コードも出力も返さず閉じた（SSH 断・transport 層の
/// 異常）ケースを模す。実機では `herdr command failed (exit code: null)` として
/// 「No herdr pane found」に誤って swallow されていた経路（TERM-HERDR 診断）。
class _FakeSshClientNullExit extends FakeSshClient {
  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    execCommands.add(command);
    return (stdout: '', stderr: '', exitCode: null);
  }
}

/// exitCode null だが stdout は返す [FakeSshClient] のスタブ。
///
/// 出力は得られたが終了コードだけ欠落したケース（dartssh2 の exit-status
/// 欠落）を模し、stdout が成功扱いで返ることを検証する。
class _FakeSshClientNullExitWithOutput extends FakeSshClient {
  final String output;
  _FakeSshClientNullExitWithOutput(this.output);

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    execCommands.add(command);
    return (stdout: output, stderr: '', exitCode: null);
  }
}
