import 'dart:typed_data';

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
      final options = SshConnectOptions(password: 'pw');
      expect(options.timeout, 30);
      expect(options.multiplexer, isNull);
      expect(options.multiplexer?.executablePath, isNull);
      expect(options.privateKey, isNull);
      expect(options.passphrase, isNull);
      expect(options.acceptNewHostKeys, isTrue);
    });

    test('SshConnectOptions uses multiplexer', () {
      final options = SshConnectOptions(
        password: 'pw',
        multiplexer: MultiplexerConfig.tmux('/usr/bin/tmux'),
      );
      expect(options.multiplexer?.backend, BackendType.tmux);
      expect(options.multiplexer?.executablePath, '/usr/bin/tmux');
      expect(options.password, 'pw');
    });

    test(
      'SshConnectOptions preserves key authentication and host-key policy',
      () {
        final options = SshConnectOptions(
          privateKey: 'pem',
          passphrase: 'secret',
          timeout: 12,
          acceptNewHostKeys: false,
        );
        expect(options.password, isNull);
        expect(options.privateKey, 'pem');
        expect(options.passphrase, 'secret');
        expect(options.timeout, 12);
        expect(options.acceptNewHostKeys, isFalse);
      },
    );

    test('ShellOptions defaults', () {
      const options = ShellOptions();
      expect(options.term, 'xterm-256color');
      expect(options.cols, 80);
      expect(options.rows, 24);
    });

    test('SshEvents copyWith', () {
      var closed = false;
      Object? reportedError;
      Uint8List? received;
      final events = SshEvents(
        onClose: () => closed = true,
        onError: (error) => reportedError = error,
      );
      final updated = events.copyWith(onData: (data) => received = data);
      expect(updated.onData, isNotNull);
      expect(updated.onClose, isNotNull);
      expect(updated.onError, isNotNull);
      updated.onClose!();
      updated.onError!('boom');
      updated.onData!(Uint8List.fromList([1, 2, 3]));
      expect(closed, isTrue);
      expect(reportedError, 'boom');
      expect(received, Uint8List.fromList([1, 2, 3]));
    });
  });
}
