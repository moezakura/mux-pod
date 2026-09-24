import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_muxpod/services/connection_error.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/fake_ssh_client.dart';
import 'helpers/herdr_adapter_fixtures.dart';
import 'helpers/herdr_adapter_fakes.dart';

void main() {
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
        final client = FakeSshClientNullExit();

        final adapter = HerdrAdapter(client);
        await expectLater(
          adapter.snapshot(),
          throwsA(isA<SshConnectionError>()),
        );
      },
    );

    test('treats exit code null with non-empty stdout as success '
        '(output obtained, exit status lost)', () async {
      final client = FakeSshClientNullExitWithOutput(kSnapshotOk);

      final adapter = HerdrAdapter(client);
      final snapshot = await adapter.snapshot();

      expect(snapshot.workspaces, hasLength(1));
      expect(snapshot.workspaces.first.id, 'w1');
    });

    test(
      'throws HerdrTargetNotFoundException for workspace_not_found code',
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
                .having(
                  (e) => e.kind,
                  'kind',
                  HerdrTargetNotFoundKind.workspace,
                )
                .having((e) => e.errorCode, 'errorCode', 'workspace_not_found')
                .having(
                  (e) => e.message,
                  'message',
                  contains('workspace_not_found'),
                ),
          ),
        );
      },
    );

    test(
      'throws HerdrCommandException with errorCode for non-target error code',
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
                .having(
                  (e) => e.message,
                  'message',
                  contains('internal_error'),
                ),
          ),
        );
      },
    );

    test('extracts error code from stderr', () async {
      final client = FakeSshClientWithStderr(
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
  group('HerdrAdapter.paneRead', () {
    test('reads pane content with default options', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = 'hello\nworld\n';

      final adapter = HerdrAdapter(client);
      final content = await adapter.paneRead('w1:p1');

      expect(
        client.execCommands,
        contains('herdr pane read w1:p1 --source recent'),
      );
      expect(content.rawText, 'hello\nworld');
      expect(content.lines, ['hello', 'world']);
      expect(content.hasAnsi, isFalse);
    });

    test('passes source, lines, and --raw through to the command', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = '\x1b[32mok\x1b[0m\n';

      final adapter = HerdrAdapter(client);
      await adapter.paneRead(
        'w1:p1',
        source: 'visible',
        lines: 120,
        ansi: true,
      );

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

    test('viaPersistent: true は execPersistentWithExitCode 経由で取得する', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = 'hello\n';

      final adapter = HerdrAdapter(client);
      final content = await adapter.paneRead('w1:p1', viaPersistent: true);

      expect(content.rawText, 'hello');
      // FakeSshClient.execPersistentWithExitCode は execPersistentCommands に記録する。
      expect(
        client.execPersistentCommands,
        contains('herdr pane read w1:p1 --source recent'),
      );
    });

    test('viaPersistent でも target-not-found の例外分類は維持される', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] =
          '{"error":{"code":"pane_not_found","message":"no pane"}}';
      client.execExitCodes['herdr pane read'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.paneRead('w1:p1', viaPersistent: true),
        throwsA(
          isA<HerdrTargetNotFoundException>().having(
            (e) => e.kind,
            'kind',
            HerdrTargetNotFoundKind.pane,
          ),
        ),
      );
    });
  });
}
