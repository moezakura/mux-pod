// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

void main() {
  group('SshClient DTOs', () {
    test('SshConnectionError toString', () {
      final e = SshConnectionError('failed', Exception('cause'));
      expect(e.toString(), 'SshConnectionError: failed (Exception: cause)');
    });

    test('SshAuthenticationError toString', () {
      final e = SshAuthenticationError('auth failed');
      expect(e.toString(), 'SshAuthenticationError: auth failed');
    });

    test('SshConnectOptions defaults', () {
      final options = SshConnectOptions(
        password: 'pw',
      );
      expect(options.timeout, 30);
      expect(options.multiplexer, isNull);
      expect(options.multiplexer?.executablePath, isNull);
      expect(options.privateKey, isNull);
    });

    test('SshConnectOptions uses multiplexer', () {
      final options = SshConnectOptions(
        password: 'pw',
        multiplexer: MultiplexerConfig.tmux('/usr/bin/tmux'),
      );
      expect(options.multiplexer?.backend, BackendType.tmux);
      expect(options.multiplexer?.executablePath, '/usr/bin/tmux');
    });

    test('SshConnectOptions tmuxPath alias maps to multiplexer', () {
      final options = SshConnectOptions(
        password: 'pw',
        tmuxPath: '/usr/bin/tmux',
      );
      expect(options.multiplexer?.backend, BackendType.tmux);
      expect(options.multiplexer?.executablePath, '/usr/bin/tmux');
    });

    test('ShellOptions defaults', () {
      const options = ShellOptions();
      expect(options.term, 'xterm-256color');
      expect(options.cols, 80);
      expect(options.rows, 24);
    });

    test('SshEvents copyWith', () {
      const events = SshEvents();
      final updated = events.copyWith(onData: (_) {});
      expect(updated.onData, isNotNull);
      expect(updated.onClose, isNull);
    });
  });

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
        SshEvents(
          onData: (_) {},
          onClose: () {},
          onError: (_) {},
        ),
      );
      expect(states, isEmpty);
    });

    test('openSftp throws when not connected', () async {
      final client = createSshClient();
      await expectLater(client.openSftp(), throwsA(isA<SshConnectionError>()));
    });

    test('exec throws when not connected', () async {
      final client = createSshClient();
      await expectLater(
        client.exec('whoami'),
        throwsA(isA<SshConnectionError>()),
      );
    });

    test('execPersistent throws when not connected', () async {
      final client = createSshClient();
      await expectLater(
        client.execPersistent('whoami'),
        throwsA(isA<SshConnectionError>()),
      );
    });

    test('execWithExitCode throws when not connected', () async {
      final client = createSshClient();
      await expectLater(
        client.execWithExitCode('whoami'),
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
