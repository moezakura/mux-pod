import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/command/command_request.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

void main() {
  group('SshClient no-connection', () {
    test('createSshClient creates SshClient', () {
      final client = createSshClient();
      expect(client.isConnected, isFalse);
      expect(client.state, SshConnectionState.disconnected);
      expect(client.lastError, isNull);
      expect(client.userExecutablePath, isNull);
      expect(client.connectOptions?.multiplexer, isNull);
    });

    test('state stream emits when connected is toggled', () {
      final client = createSshClient();
      final states = <SshConnectionState>[];
      client.connectionStateStream.listen(states.add);

      client.setEventHandlers(
        SshEvents(onData: (_) {}, onClose: () {}, onError: (_) {}),
      );
      expect(states, isEmpty);
    });

    test(
      'disconnect invokes close event and restart methods are safe while disconnected',
      () async {
        final client = createSshClient();
        var closeCount = 0;
        client.setEventHandlers(SshEvents(onClose: () => closeCount++));

        await client.restartPersistentShell();
        await client.restartInputShell();
        await client.disconnect();

        expect(client.state, SshConnectionState.disconnected);
        expect(client.isConnected, isFalse);
        expect(closeCount, 1);
        expect(client.persistentShell, isNull);
        expect(client.inputShell, isNull);
      },
    );

    test('interactive shell operations fail before connection', () async {
      final client = createSshClient();
      await expectLater(
        client.startShell(),
        throwsA(isA<SshConnectionError>()),
      );
      expect(() => client.write('x'), throwsA(isA<SshConnectionError>()));
    });

    test('openSftp throws when not connected', () async {
      final client = createSshClient();
      await expectLater(client.openSftp(), throwsA(isA<SshConnectionError>()));
    });

    test('execute throws when not connected', () async {
      final client = createSshClient();
      await expectLater(
        client.execute(
          const CommandRequest(
            command: 'whoami',
            transport: CommandTransportPreference.ephemeralOnly,
            output: CommandOutputRequirement.outputOnly,
          ),
        ),
        throwsA(isA<SshConnectionError>()),
      );
    });

    test('connect validates required parameters', () async {
      final client = createSshClient();
      await expectLater(
        client.connect(
          host: '  ',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        ),
        throwsA(isA<SshConnectionError>()),
      );

      await expectLater(
        client.connect(
          host: 'host',
          port: 0,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        ),
        throwsA(isA<SshConnectionError>()),
      );

      await expectLater(
        client.connect(
          host: 'host',
          port: 70000,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        ),
        throwsA(isA<SshConnectionError>()),
      );

      await expectLater(
        client.connect(
          host: 'host',
          port: 22,
          username: '  ',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        ),
        throwsA(isA<SshConnectionError>()),
      );

      await expectLater(
        client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(),
          lightweight: true,
        ),
        throwsA(isA<SshAuthenticationError>()),
      );
    });
  });
}
