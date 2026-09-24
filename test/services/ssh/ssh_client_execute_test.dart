import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/command/command_request.dart';
import 'package:flutter_muxpod/services/command/command_result.dart';
import 'package:flutter_muxpod/services/ssh/persistent_shell.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'helpers/ssh_client_fakes.dart';

void main() {
  group('SshClient lifecycle contracts', () {
    test(
      'execute: persistentPreferred + exitCode uses the persistent shell',
      () async {
        final rawClient = FakeRawSshClient();
        final shells = <FakePersistentShell>[];
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: FakeSocket(), client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = FakePersistentShell(raw);
            shells.add(shell);
            return shell;
          },
        );

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
        );

        final result = await client.execute(
          const CommandRequest(
            command: 'echo hi',
            transport: CommandTransportPreference.persistentPreferred,
            output: CommandOutputRequirement.exitCode,
          ),
        );

        expect(shells, hasLength(2));
        expect(shells.first.commands, ['echo hi']);
        expect(result.outputSeparation, CommandOutputSeparation.merged);
        expect(result.mergedOutput, 'ping');
        expect(result.exitCode, 0);
        await client.disconnect();
      },
    );

    test(
      'execute: persistentPreferred restarts the shell and retries when closed',
      () async {
        final rawClient = FakeRawSshClient();
        final shells = <FakePersistentShell>[];
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: FakeSocket(), client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = FakePersistentShell(raw);
            shells.add(shell);
            return shell;
          },
        );

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
        );

        // 最初のシェルを切断状態にして再起動を誘発する
        shells.first.error = PersistentShellError('Shell session closed');
        final result = await client.execute(
          const CommandRequest(
            command: 'echo hi',
            transport: CommandTransportPreference.persistentPreferred,
            output: CommandOutputRequirement.exitCode,
          ),
        );

        expect(shells, hasLength(3)); // 初期2 + 再起動1
        expect(result.outputSeparation, CommandOutputSeparation.merged);
        expect(result.mergedOutput, 'ping');
        expect(result.exitCode, 0);
        await client.disconnect();
      },
    );

    test(
      'execute: ephemeralOnly + separatedOutput returns separated result',
      () async {
        final rawClient = FakeRawSshClient();
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: FakeSocket(), client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = FakePersistentShell(raw);
            return shell;
          },
        );

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
        );

        final future = client.execute(
          const CommandRequest(
            command: 'echo hi',
            transport: CommandTransportPreference.ephemeralOnly,
            output: CommandOutputRequirement.separatedOutput,
          ),
        );

        // exec チャネルの stdout/stderr を閉じて結果を確定させる。
        final session = rawClient.execSessions.single;
        await session.finishAll();

        final result = await future;
        expect(result.outputSeparation, CommandOutputSeparation.separated);
        expect(result.actualTransport, CommandTransport.ephemeral);
        await client.disconnect();
      },
    );

    test(
      'execute: persistentPreferred + exitCode routes to persistent shell',
      () async {
        final rawClient = FakeRawSshClient();
        final shells = <FakePersistentShell>[];
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: FakeSocket(), client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = FakePersistentShell(raw);
            shells.add(shell);
            return shell;
          },
        );

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
        );

        final result = await client.execute(
          const CommandRequest(
            command: 'herdr pane read w1:p1',
            transport: CommandTransportPreference.persistentPreferred,
            output: CommandOutputRequirement.exitCode,
          ),
        );

        expect(result.outputSeparation, CommandOutputSeparation.merged);
        expect(result.actualTransport, CommandTransport.persistent);
        expect(result.mergedOutput, 'ping');
        expect(shells.first.commands, contains('herdr pane read w1:p1'));
        await client.disconnect();
      },
    );
  });
}
