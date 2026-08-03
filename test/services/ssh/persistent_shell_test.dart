import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/ssh/persistent_shell.dart';
import 'package:flutter_muxpod/services/tmux/tmux_backend.dart';

class _FakeSSHSession implements SSHSession {
  final _stdout = StreamController<Uint8List>.broadcast();
  final _stderr = StreamController<Uint8List>.broadcast();
  final _stdin = StreamController<Uint8List>();
  final written = <Uint8List>[];
  bool closed = false;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  StreamSink<Uint8List> get stdin => _stdin.sink;

  @override
  Future<void> get done => Completer<void>().future;

  @override
  int? get exitCode => null;

  @override
  SSHSessionExitSignal? get exitSignal => null;

  @override
  void write(Uint8List data) {
    written.add(data);
  }

  @override
  void close() {
    closed = true;
    _stdout.close();
    _stderr.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSSHClient implements SSHClient {
  final _session = _FakeSSHSession();

  @override
  Future<SSHSession> shell({
    SSHPtyConfig? pty = const SSHPtyConfig(),
    Map<String, String>? environment,
  }) async => _session;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter && invocation.memberName == #done) {
      return Completer<void>().future;
    }
    if (invocation.isGetter && invocation.memberName == #isClosed) {
      return false;
    }
    return null;
  }
}

void main() {
  group('PersistentShell', () {
    test('PersistentShellError toString', () {
      final e = PersistentShellError('test');
      expect(e.toString(), 'PersistentShellError: test');
    });

    test('start sets isStarted', () async {
      final shell = PersistentShell(_FakeSSHClient());
      expect(shell.isStarted, isFalse);
      await shell.start();
      expect(shell.isStarted, isTrue);
      await shell.dispose();
    });

    test('start is idempotent', () async {
      final shell = PersistentShell(_FakeSSHClient());
      await shell.start();
      await shell.start();
      expect(shell.isStarted, isTrue);
      await shell.dispose();
    });

    test('exec throws before start', () async {
      final shell = PersistentShell(_FakeSSHClient());
      await expectLater(
        shell.exec('whoami'),
        throwsA(isA<PersistentShellError>()),
      );
    });

    test('sendNoWait writes to session', () async {
      final client = _FakeSSHClient();
      final shell = PersistentShell(client);
      await shell.start();
      shell.sendNoWait('C-c');
      expect(client._session.written, hasLength(2));
      final last = String.fromCharCodes(client._session.written.last);
      expect(last, 'C-c\n');
      await shell.dispose();
    });

    test('sendNoWait throws before start', () {
      final shell = PersistentShell(_FakeSSHClient());
      expect(() => shell.sendNoWait('C-c'), throwsA(isA<TmuxTransportException>()));
    });

    test('dispose closes session', () async {
      final client = _FakeSSHClient();
      final shell = PersistentShell(client);
      await shell.start();
      await shell.dispose();
      expect(client._session.closed, isTrue);
      expect(shell.isStarted, isFalse);
    });

    test('restart disposes and starts again', () async {
      final client = _FakeSSHClient();
      final shell = PersistentShell(client);
      await shell.start();
      await shell.restart();
      expect(shell.isStarted, isTrue);
      await shell.dispose();
    });

    test('sendNoWait throws TmuxTransportException when not started', () {
      final client = _FakeSSHClient();
      final shell = PersistentShell(client);
      expect(
        () => shell.sendNoWait('hello'),
        throwsA(isA<TmuxTransportException>()),
      );
    });

    test('sendNoWait throws TmuxTransportException when closed', () async {
      final client = _FakeSSHClient();
      final shell = PersistentShell(client);
      await shell.start();
      await shell.dispose();
      expect(
        () => shell.sendNoWait('hello'),
        throwsA(isA<TmuxTransportException>()),
      );
    });
  });
}
