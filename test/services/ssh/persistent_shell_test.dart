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

  void emitStdout(String value) =>
      _stdout.add(Uint8List.fromList(value.codeUnits));

  void emitError(Object error) => _stdout.addError(error);

  Future<void> finishStdout() => _stdout.close();

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
  int shellCalls = 0;
  SSHPtyConfig? lastPty;

  @override
  Future<SSHSession> shell({
    SSHPtyConfig? pty = const SSHPtyConfig(),
    Map<String, String>? environment,
  }) async {
    shellCalls++;
    lastPty = pty;
    return _session;
  }

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
      final client = _FakeSSHClient();
      final shell = PersistentShell(client);
      expect(shell.isStarted, isFalse);
      await shell.start();
      expect(shell.isStarted, isTrue);
      expect(client.shellCalls, 1);
      expect(client.lastPty?.type, 'dumb');
      expect(client.lastPty?.width, 200);
      expect(client.lastPty?.height, 50);
      final initialization = String.fromCharCodes(
        client._session.written.single,
      );
      expect(initialization, contains('HISTFILE=/dev/null'));
      expect(initialization, contains('stty -echo'));
      await shell.dispose();
    });

    test('start is idempotent', () async {
      final client = _FakeSSHClient();
      final shell = PersistentShell(client);
      await shell.start();
      await shell.start();
      expect(shell.isStarted, isTrue);
      expect(client.shellCalls, 1);
      await shell.dispose();
    });

    test(
      'exec writes unpredictable framed markers and extracts framed output',
      () async {
        final client = _FakeSSHClient();
        final shell = PersistentShell(client);
        await shell.start();

        final resultFuture = shell.exec('whoami');
        final command = String.fromCharCodes(client._session.written.last);
        final markerId = RegExp(
          r'START_([0-9a-f]{16})',
        ).firstMatch(command)!.group(1)!;
        expect(
          command,
          contains("printf '\\x01###START_$markerId###\\x01\\n'"),
        );
        expect(command, contains('; whoami;'));
        expect(command, contains("printf '\\x01###END_$markerId###\\x01\\n'"));

        final secondClient = _FakeSSHClient();
        final secondShell = PersistentShell(secondClient);
        await secondShell.start();
        final secondResult = secondShell.exec('whoami');
        final secondCommand = String.fromCharCodes(
          secondClient._session.written.last,
        );
        final secondMarkerId = RegExp(
          r'START_([0-9a-f]{16})',
        ).firstMatch(secondCommand)!.group(1)!;
        expect(secondMarkerId, isNot(markerId));
        secondClient._session.emitStdout(
          '\x01###START_$secondMarkerId###\x01\nsecond\n'
          '\x01###END_$secondMarkerId###\x01\n',
        );
        expect(await secondResult, 'second');
        await secondShell.dispose();

        client._session.emitStdout(
          '\x01###START_$markerId###\x01\r\nalice\r\n'
          '\x01###END_$markerId###\x01\r\n',
        );

        expect(await resultFuture, 'alice');
        await shell.dispose();
      },
    );

    test('stdout completion and errors fail a pending command', () async {
      final doneClient = _FakeSSHClient();
      final doneShell = PersistentShell(doneClient);
      await doneShell.start();
      final doneResult = doneShell.exec('slow');
      await doneClient._session.finishStdout();
      await expectLater(
        doneResult,
        throwsA(
          predicate((e) => e.toString().contains('Shell session closed')),
        ),
      );

      final errorClient = _FakeSSHClient();
      final errorShell = PersistentShell(errorClient);
      await errorShell.start();
      final errorResult = errorShell.exec('slow');
      errorClient._session.emitError('boom');
      await expectLater(
        errorResult,
        throwsA(predicate((e) => e.toString().contains('Shell error: boom'))),
      );
      await errorShell.dispose();
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
      expect(
        () => shell.sendNoWait('C-c'),
        throwsA(isA<TmuxTransportException>()),
      );
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

  group('PersistentShell.execWithExitCode', () {
    test('execWithExitCode returns output and exit code', () async {
      final client = _FakeSSHClient();
      final shell = PersistentShell(client);
      await shell.start();

      final resultFuture = shell.execWithExitCode('whoami');
      final command = String.fromCharCodes(client._session.written.last);
      final markerId = RegExp(
        r'START_([0-9a-f]{16})',
      ).firstMatch(command)!.group(1)!;
      // RC エコーがコマンド末尾に付与される（終了コード捕捉用）
      expect(
        command,
        contains("printf '\\x01###RC_$markerId###:%d\\n' \"\$__muxpod_rc\""),
      );

      client._session.emitStdout(
        '\x01###START_$markerId###\x01\nalice\r\n'
        '\x01###RC_$markerId###:0\x01\n'
        '\x01###END_$markerId###\x01\r\n',
      );

      final result = await resultFuture;
      expect(result.output, 'alice');
      expect(result.exitCode, 0);
      await shell.dispose();
    });

    test('execWithExitCode captures a non-zero exit code', () async {
      final client = _FakeSSHClient();
      final shell = PersistentShell(client);
      await shell.start();

      final resultFuture = shell.execWithExitCode('exit 3');
      final command = String.fromCharCodes(client._session.written.last);
      final markerId = RegExp(
        r'START_([0-9a-f]{16})',
      ).firstMatch(command)!.group(1)!;

      client._session.emitStdout(
        '\x01###START_$markerId###\x01\n'
        '\x01###RC_$markerId###:3\x01\n'
        '\x01###END_$markerId###\x01\n',
      );

      final result = await resultFuture;
      expect(result.output, '');
      expect(result.exitCode, 3);
      await shell.dispose();
    });

    test('exec (RC エコーなし) は exitCode を返さない', () async {
      final client = _FakeSSHClient();
      final shell = PersistentShell(client);
      await shell.start();

      final resultFuture = shell.exec('whoami');
      final command = String.fromCharCodes(client._session.written.last);
      final markerId = RegExp(
        r'START_([0-9a-f]{16})',
      ).firstMatch(command)!.group(1)!;
      // exec は RC エコーを付与しない（tmux 既存利用者に影響させない）
      expect(
        command,
        isNot(contains("printf '\\x01###RC_$markerId###:%d\\n'")),
      );

      client._session.emitStdout(
        '\x01###START_$markerId###\x01\nalice\r\n'
        '\x01###END_$markerId###\x01\r\n',
      );

      expect(await resultFuture, 'alice');
      await shell.dispose();
    });

    test('execWithExitCode throws before start', () async {
      final shell = PersistentShell(_FakeSSHClient());
      await expectLater(
        shell.execWithExitCode('whoami'),
        throwsA(isA<PersistentShellError>()),
      );
    });
  });
}
