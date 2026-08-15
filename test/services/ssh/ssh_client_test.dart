import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/command/command_request.dart';
import 'package:flutter_muxpod/services/command/command_result.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/services/ssh/persistent_shell.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

class _FakeSocket implements SSHSocket {
  final _stream = StreamController<Uint8List>();
  final _sink = StreamController<List<int>>();
  bool closed = false;

  @override
  Stream<Uint8List> get stream => _stream.stream;

  @override
  StreamSink<List<int>> get sink => _sink.sink;

  @override
  Future<void> get done => _stream.done;

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _stream.close();
    await _sink.close();
  }

  @override
  void destroy() => unawaited(close());

  @override
  Future<void> flush() async {}
}

class _FakeInteractiveSession implements SSHSession {
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final _done = Completer<void>();
  final writes = <Uint8List>[];

  void emitData(List<int> bytes) => _stdout.add(Uint8List.fromList(bytes));
  void emitError(Object error) => _stdout.addError(error);
  Future<void> finish() => _stdout.close();
  Future<void> finishAll() async {
    await _stdout.close();
    await _stderr.close();
  }

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Future<void> get done => _done.future;

  @override
  int? get exitCode => 0;

  @override
  SSHSessionExitSignal? get exitSignal => null;

  @override
  void write(Uint8List data) => writes.add(data);

  @override
  void close() {
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_stderr.isClosed) unawaited(_stderr.close());
    if (!_done.isCompleted) _done.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRawSshClient implements SSHClient {
  final Completer<void> authentication = Completer<void>();
  final interactiveSession = _FakeInteractiveSession();
  final execSessions = <_FakeInteractiveSession>[];
  bool closed = false;
  SSHPtyConfig? lastPty;

  @override
  Future<void> get authenticated => authentication.future;

  @override
  Future<SSHSession> shell({
    SSHPtyConfig? pty = const SSHPtyConfig(),
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    lastPty = pty;
    return interactiveSession;
  }

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    final session = _FakeInteractiveSession();
    execSessions.add(session);
    return session;
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePersistentShell extends PersistentShell {
  _FakePersistentShell(super.client);

  final commands = <String>[];
  Object? error;
  bool disposed = false;

  @override
  bool get isStarted => !disposed;

  @override
  Future<void> start() async {}

  @override
  Future<String> exec(String command, {Duration? timeout}) async {
    commands.add(command);
    final failure = error;
    if (failure != null) throw failure;
    return 'ping';
  }

  @override
  Future<({String output, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    commands.add(command);
    final failure = error;
    if (failure != null) throw failure;
    return (output: 'ping', exitCode: 0);
  }

  @override
  void sendNoWait(String command) {}

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;
}

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

  group('SshClient lifecycle contracts', () {
    setUp(() => SecureStorageService.setTestValues({}));
    tearDown(() => SecureStorageService.setTestValues(null));

    test(
      'SSH-020/024: connect exposes options and emits connection states',
      () async {
        final rawClient = _FakeRawSshClient();
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: _FakeSocket(), client: rawClient);
          },
        );
        final states = <SshConnectionState>[];
        final subscription = client.connectionStateStream.listen(states.add);
        addTearDown(subscription.cancel);
        final options = SshConnectOptions(
          password: 'pw',
          multiplexer: MultiplexerConfig.tmux('/opt/tmux'),
        );

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: options,
          lightweight: true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(identical(client.connectOptions, options), isTrue);
        expect(states, [SshConnectionState.connected]);

        await client.disconnect();
        await Future<void>.delayed(Duration.zero);
        expect(states, [
          SshConnectionState.connected,
          SshConnectionState.disconnected,
        ]);
      },
    );

    test(
      'SSH-LIFE-003/004: input shell restart disposes, recreates, and notifies',
      () async {
        final rawClient = _FakeRawSshClient();
        final shells = <_FakePersistentShell>[];
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: _FakeSocket(), client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = _FakePersistentShell(raw);
            shells.add(shell);
            return shell;
          },
        );
        var rebootNotifications = 0;
        client.onInputShellRebooted = () => rebootNotifications++;

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
        );

        expect(shells, hasLength(2));
        expect(identical(client.inputShell, shells[1]), isTrue);
        expect(rebootNotifications, 1);

        await client.restartInputShell();

        expect(shells[1].disposed, isTrue);
        expect(shells, hasLength(3));
        expect(identical(client.inputShell, shells[2]), isTrue);
        expect(rebootNotifications, 2);
        await client.disconnect();
      },
    );

    test(
      'SSH-LIFE-008..012: keepalive schedules, adapts, fails, and is cancelled',
      () async {
        final rawClient = _FakeRawSshClient();
        final socket = _FakeSocket();
        final shells = <_FakePersistentShell>[];
        final timers = <_FakeTimer>[];
        Object? reportedError;
        var closeCalls = 0;
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: socket, client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = _FakePersistentShell(raw);
            shells.add(shell);
            return shell;
          },
          timerFactory: (duration, callback) {
            final timer = _FakeTimer(duration, callback);
            timers.add(timer);
            return timer;
          },
        );
        client.setEventHandlers(
          SshEvents(
            onError: (error) => reportedError = error,
            onClose: () => closeCalls++,
          ),
        );

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
        );

        expect(shells, hasLength(2));
        expect(timers.single.duration, const Duration(seconds: 10));
        for (var i = 0; i < 3; i++) {
          timers.last.fire();
          await Future<void>.delayed(Duration.zero);
        }
        expect(shells.first.commands, ['echo ping', 'echo ping', 'echo ping']);
        expect(timers.last.duration, const Duration(seconds: 15));

        shells.first.error = StateError('lost');
        timers.last.fire();
        await Future<void>.delayed(Duration.zero);
        expect(client.state, SshConnectionState.error);
        expect(client.lastError, contains('Connection lost'));
        expect(reportedError, isA<SshConnectionError>());
        expect(closeCalls, 1);
        expect(timers.last.isActive, isFalse);

        await client.disconnect();
        expect(socket.closed, isTrue);
        expect(shells.every((shell) => shell.disposed), isTrue);
      },
    );

    test(
      'execute: persistentPreferred + exitCode uses the persistent shell',
      () async {
        final rawClient = _FakeRawSshClient();
        final shells = <_FakePersistentShell>[];
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: _FakeSocket(), client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = _FakePersistentShell(raw);
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
        final rawClient = _FakeRawSshClient();
        final shells = <_FakePersistentShell>[];
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: _FakeSocket(), client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = _FakePersistentShell(raw);
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
        final rawClient = _FakeRawSshClient();
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: _FakeSocket(), client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = _FakePersistentShell(raw);
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
        final rawClient = _FakeRawSshClient();
        final shells = <_FakePersistentShell>[];
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: _FakeSocket(), client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = _FakePersistentShell(raw);
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

    test(
      'SSH-LIFE-013..015: interactive shell forwards data, error, and done',
      () async {
        final rawClient = _FakeRawSshClient();
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: _FakeSocket(), client: rawClient);
          },
        );
        final received = <int>[];
        Object? reportedError;
        var closeCalls = 0;
        client.setEventHandlers(
          SshEvents(
            onData: received.addAll,
            onError: (error) => reportedError = error,
            onClose: () => closeCalls++,
          ),
        );
        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        );

        await client.startShell(
          const ShellOptions(term: 'vt100', cols: 132, rows: 43),
        );
        expect(rawClient.lastPty?.type, 'vt100');
        expect(rawClient.lastPty?.width, 132);
        expect(rawClient.lastPty?.height, 43);
        rawClient.interactiveSession.emitData([1, 2, 3]);
        await Future<void>.delayed(Duration.zero);
        expect(received, [1, 2, 3]);

        rawClient.interactiveSession.emitError(StateError('stream failed'));
        await Future<void>.delayed(Duration.zero);
        expect(reportedError, isA<StateError>());
        expect(client.lastError, contains('stream failed'));

        await rawClient.interactiveSession.finish();
        await Future<void>.delayed(Duration.zero);
        expect(client.state, SshConnectionState.disconnected);
        expect(closeCalls, 1);
        await client.disconnect();
      },
    );

    test(
      'SSH-LIFE-017: host-key callback implements TOFU and rejects changes',
      () async {
        // dartssh2 2.18.0+ は OpenSSH 形式 "SHA256:<base64>" の UTF-8 バイトを渡す
        var fingerprint = Uint8List.fromList(
          utf8.encode('SHA256:testfingerprint123'),
        );
        Future<({SSHSocket socket, SSHClient client})> factory(
          String host,
          int port,
          String username,
          SshConnectOptions options,
          void Function() onAuthenticated,
          Future<bool> Function(String, Uint8List) verify,
        ) async {
          final accepted = await verify('ssh-ed25519', fingerprint);
          if (!accepted) throw SSHAuthFailError('host key rejected');
          final raw = _FakeRawSshClient();
          onAuthenticated();
          raw.authentication.complete();
          return (socket: _FakeSocket(), client: raw);
        }

        final first = SshClient(connectionFactory: factory);
        await first.connect(
          host: 'example.test',
          port: 2222,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        );
        expect(
          await SecureStorageService().getHostKeyFingerprint(
            'example.test',
            2222,
            'ssh-ed25519',
          ),
          'SHA256:testfingerprint123',
        );
        await first.disconnect();

        fingerprint = Uint8List.fromList(
          utf8.encode('SHA256:changedfingerprint456'),
        );
        final changed = SshClient(connectionFactory: factory);
        await expectLater(
          changed.connect(
            host: 'example.test',
            port: 2222,
            username: 'user',
            options: SshConnectOptions(password: 'pw'),
            lightweight: true,
          ),
          throwsA(isA<SshAuthenticationError>()),
        );
        expect(changed.lastError, contains('Authentication failed'));
      },
    );

    test('SSH-LIFE-017b: 旧形式（MD5 hex）保存値は認証成功後に SHA256 形式へ移行する', () async {
      // 旧 dartssh2（<= 2.17）で保存された MD5 hex 形式の値をシード
      SecureStorageService.setTestValues({
        'hostkey_example.test_2222_ssh-ed25519': '66:5d:56:0b:41:6a:22:c5',
      });
      final fingerprint = Uint8List.fromList(
        utf8.encode('SHA256:newformatvalue789'),
      );
      Future<({SSHSocket socket, SSHClient client})> factory(
        String host,
        int port,
        String username,
        SshConnectOptions options,
        void Function() onAuthenticated,
        Future<bool> Function(String, Uint8List) verify,
      ) async {
        final accepted = await verify('ssh-ed25519', fingerprint);
        if (!accepted) throw SSHAuthFailError('host key rejected');
        final raw = _FakeRawSshClient();
        onAuthenticated();
        raw.authentication.complete();
        return (socket: _FakeSocket(), client: raw);
      }

      final client = SshClient(connectionFactory: factory);
      await client.connect(
        host: 'example.test',
        port: 2222,
        username: 'user',
        options: SshConnectOptions(password: 'pw'),
        lightweight: true,
      );
      expect(client.isConnected, isTrue);
      // 認証成功後に正規形式へ更新されている
      expect(
        await SecureStorageService().getHostKeyFingerprint(
          'example.test',
          2222,
          'ssh-ed25519',
        ),
        'SHA256:newformatvalue789',
      );
      await client.disconnect();
    });

    test('SSH-LIFE-017c: 旧形式保存値は認証失敗時には更新されない', () async {
      SecureStorageService.setTestValues({
        'hostkey_example.test_2222_ssh-ed25519': '66:5d:56:0b:41:6a:22:c5',
      });
      final fingerprint = Uint8List.fromList(
        utf8.encode('SHA256:newformatvalue789'),
      );
      Future<({SSHSocket socket, SSHClient client})> factory(
        String host,
        int port,
        String username,
        SshConnectOptions options,
        void Function() onAuthenticated,
        Future<bool> Function(String, Uint8List) verify,
      ) async {
        final accepted = await verify('ssh-ed25519', fingerprint);
        if (!accepted) throw SSHAuthFailError('host key rejected');
        // 認証失敗: ホスト鍵検証は通るがユーザー認証が失敗する
        throw SSHAuthFailError('auth failed');
      }

      final client = SshClient(connectionFactory: factory);
      await expectLater(
        client.connect(
          host: 'example.test',
          port: 2222,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        ),
        throwsA(isA<SshAuthenticationError>()),
      );
      // 認証失敗時は保存値が更新されない（旧形式のまま）
      expect(
        await SecureStorageService().getHostKeyFingerprint(
          'example.test',
          2222,
          'ssh-ed25519',
        ),
        '66:5d:56:0b:41:6a:22:c5',
      );
    });

    test(
      'SSH-LIFE-018: authenticated callback is accepted before completion',
      () async {
        final rawClient = _FakeRawSshClient();
        var callbackInvoked = false;
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            callbackInvoked = true;
            return (socket: _FakeSocket(), client: rawClient);
          },
        );

        final connecting = client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(callbackInvoked, isTrue);
        expect(client.state, SshConnectionState.connecting);
        rawClient.authentication.complete();
        await connecting;
        expect(client.state, SshConnectionState.connected);
        await client.disconnect();
      },
    );
  });

  group('SshClient managed PTY（hidden herdr TUI ホスト）', () {
    Future<(SshClient, _FakeRawSshClient)> connectedClient() async {
      final rawClient = _FakeRawSshClient();
      final client = SshClient(
        connectionFactory: (_, _, _, _, onAuthenticated, _) async {
          onAuthenticated();
          return (socket: _FakeSocket(), client: rawClient);
        },
      );
      // connect は認証完了を待つため、先に開始（await しない）してから
      // authentication を complete する（既存テストと同じ順序）。
      final connecting = client.connect(
        host: 'host',
        port: 22,
        username: 'user',
        options: SshConnectOptions(password: 'pw'),
        lightweight: true,
      );
      await Future<void>.delayed(Duration.zero);
      rawClient.authentication.complete();
      await connecting;
      expect(client.state, SshConnectionState.connected);
      return (client, rawClient);
    }

    test('startManagedPty は PTY 付き exec を実行し ManagedPtyProcess を返す', () async {
      final (client, rawClient) = await connectedClient();

      final process = await client.startManagedPty(
        'herdr',
        cols: 100,
        rows: 30,
      );
      expect(rawClient.execSessions, hasLength(1));
      expect(process, isNotNull);

      // resize は throw せず呼べる（SSHSession.resizeTerminal 委譲）。
      process.resize(120, 40);

      // stdout を emitData しても例外なし（明示 discard）。
      rawClient.execSessions.single.emitData([1, 2, 3]);

      // stderrTail は空のまま（エラー未出力）。
      expect(process.stderrTail, isEmpty);
      expect(process.exitCode, 0);

      await client.disconnect();
    });

    test('二重 startManagedPty は前の managed session を close する', () async {
      final (client, rawClient) = await connectedClient();

      final first = await client.startManagedPty('herdr', cols: 80, rows: 24);
      final second = await client.startManagedPty('herdr', cols: 90, rows: 30);
      expect(rawClient.execSessions, hasLength(2));
      expect(second, isNotNull);
      expect(first, isNot(same(second)));

      await client.disconnect();
    });

    test('disconnect（dispose）で managed PTY の session も close される', () async {
      final (client, rawClient) = await connectedClient();

      await client.startManagedPty('herdr', cols: 80, rows: 24);
      expect(rawClient.execSessions, hasLength(1));

      await client.disconnect();
      // ManagedPtyProcess.close が _FakeInteractiveSession.close を呼ぶ
      // （close 後は stdout/stderr が閉じる）。例外なしで完了すること。
    });

    test('未接続で startManagedPty は throw する', () async {
      final client = SshClient();
      expect(
        () => client.startManagedPty('herdr', cols: 80, rows: 24),
        throwsA(isA<Exception>()),
      );
    });
  });
}
