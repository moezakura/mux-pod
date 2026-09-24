import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_muxpod/services/ssh/persistent_shell.dart';

/// ssh_client_test の fake 群（元ファイルから verbatim 抽出し private→public 化）。
class FakeSocket implements SSHSocket {
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

class FakeInteractiveSession implements SSHSession {
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

class FakeRawSshClient implements SSHClient {
  final Completer<void> authentication = Completer<void>();
  final interactiveSession = FakeInteractiveSession();
  final execSessions = <FakeInteractiveSession>[];
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
    final session = FakeInteractiveSession();
    execSessions.add(session);
    return session;
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakePersistentShell extends PersistentShell {
  FakePersistentShell(super.client);

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

class FakeTimer implements Timer {
  FakeTimer(this.duration, this.callback);

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
