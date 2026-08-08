import 'dart:async';

import 'package:flutter_muxpod/services/agent/agent_types.dart';
import 'package:flutter_muxpod/services/agent/headless/chat_event.dart';
import 'package:flutter_muxpod/services/agent/headless/headless_agent_session.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hand-written fake that serves canned exec output and records commands.
class _FakeSshClient extends SshClient {
  final List<String> commands = [];
  Stream<String> Function(String command)? onExecStream;

  @override
  Stream<String> execStream(String command) {
    commands.add(command);
    final factory = onExecStream;
    if (factory == null) {
      throw StateError('onExecStream not set');
    }
    return factory(command);
  }
}

void main() {
  group('HeadlessAgentSession', () {
    late _FakeSshClient ssh;
    late HeadlessAgentSession session;

    setUp(() {
      ssh = _FakeSshClient();
      session = HeadlessAgentSession(
        ssh: ssh,
        kind: AgentKind.claudeCode,
        workingDirectory: '/repo',
      );
    });

    tearDown(() async {
      await session.dispose();
    });

    test('streams parsed events and captures the session id', () async {
      ssh.onExecStream = (_) => Stream.fromIterable([
            '{"type":"system","subtype":"init","session_id":"sess-1"}\n',
            '{"type":"assistant","message":{"content":[{"type":"text","text":"Hi"}]}}\n',
            '{"type":"result","subtype":"success","is_error":false,'
                '"usage":{"input_tokens":10,"output_tokens":5}}\n',
          ]);

      final events = <ChatEvent>[];
      final sub = session.events.listen(events.add);

      await session.start('hello');
      await sub.cancel();

      expect(events[0], isA<SessionStarted>());
      expect(events[1], isA<TextDelta>());
      expect(events[2], isA<UsageUpdated>());
      expect(events[3], isA<RunCompleted>());
      expect(session.sessionId, 'sess-1');
      expect(session.isRunning, isFalse);

      expect(ssh.commands, hasLength(1));
      expect(ssh.commands[0], startsWith("cd '/repo' && claude -p 'hello'"));
      expect(ssh.commands[0], isNot(contains('--resume')));
    });

    test('synthesizes RunCompleted when the stream ends silently', () async {
      ssh.onExecStream = (_) => Stream.value('noise line\n');

      final events = <ChatEvent>[];
      final sub = session.events.listen(events.add);

      await session.start('hello');
      await sub.cancel();

      expect(events, hasLength(1));
      expect(events[0], isA<RunCompleted>());
    });

    test('emits RunFailed when the stream errors (SSH disconnect)', () async {
      ssh.onExecStream =
          (_) => Stream.error(SshConnectionError('Connection lost'));

      final events = <ChatEvent>[];
      final sub = session.events.listen(events.add);

      await session.start('hello');
      await sub.cancel();

      expect(events, hasLength(1));
      expect(events[0], isA<RunFailed>());
      expect((events[0] as RunFailed).message, contains('Connection lost'));
      expect(session.isRunning, isFalse);
    });

    test('send() resumes with the stored session id', () async {
      ssh.onExecStream = (_) => Stream.fromIterable([
            '{"type":"system","subtype":"init","session_id":"sess-1"}\n',
            '{"type":"result","subtype":"success","is_error":false}\n',
          ]);

      final sub = session.events.listen((_) {});
      await session.start('first');
      await session.send('second');
      await sub.cancel();

      expect(ssh.commands, hasLength(2));
      expect(ssh.commands[1], contains("--resume 'sess-1'"));
      expect(ssh.commands[1], contains("-p 'second'"));
    });

    test('send() throws when no session id was captured', () {
      expect(
        () => session.send('follow-up'),
        throwsA(isA<StateError>()),
      );
    });

    test('start() throws while a run is active', () async {
      final controller = StreamController<String>();
      ssh.onExecStream = (_) => controller.stream;

      final sub = session.events.listen((_) {});
      final runFuture = session.start('hello');
      expect(session.isRunning, isTrue);
      expect(() => session.start('again'), throwsA(isA<StateError>()));

      await session.cancel();
      await runFuture;
      await sub.cancel();
      await controller.close();
    });

    test('cancel() kills the run and unblocks start()', () async {
      final controller = StreamController<String>();
      var sourceCancelled = false;
      controller.onCancel = () {
        sourceCancelled = true;
      };
      ssh.onExecStream = (_) => controller.stream;

      final sub = session.events.listen((_) {});
      final runFuture = session.start('hello');

      await session.cancel();
      // start()'s future must complete even though the stream never did.
      await runFuture;

      expect(sourceCancelled, isTrue);
      expect(session.isRunning, isFalse);
      await sub.cancel();
      await controller.close();
    });
  });
}
