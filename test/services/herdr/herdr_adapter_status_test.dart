import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/fake_ssh_client.dart';
import 'helpers/herdr_adapter_fixtures.dart';
import 'helpers/herdr_adapter_fakes.dart';

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

    test(
      'throws HerdrProtocolMismatchException when server protocol is below 17',
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
      },
    );

    test(
      'throws HerdrServerNotRunningException when server is not running',
      () async {
        final client = FakeSshClient();
        client.execOutputs['herdr status --json'] = kStatusNotRunning;

        final adapter = HerdrAdapter(client);
        await expectLater(
          adapter.preflight(),
          throwsA(isA<HerdrServerNotRunningException>()),
        );
      },
    );

    test('throws HerdrCommandException when herdr binary is missing', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = '';
      client.execExitCodes['herdr status --json'] = 127;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(
          isA<HerdrCommandException>().having(
            (e) => e.exitCode,
            'exitCode',
            127,
          ),
        ),
      );
    });

    test('throws HerdrCommandException when stderr is non-empty', () async {
      final client = FakeSshClientWithStderr('herdr: command not found');

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(
          isA<HerdrCommandException>().having(
            (e) => e.message,
            'message',
            contains('command not found'),
          ),
        ),
      );
    });

    test(
      'throws HerdrCommandException when output is not valid status JSON',
      () async {
        final client = FakeSshClient();
        client.execOutputs['herdr status --json'] = 'garbage output';

        final adapter = HerdrAdapter(client);
        await expectLater(
          adapter.preflight(),
          throwsA(isA<HerdrCommandException>()),
        );
      },
    );
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
