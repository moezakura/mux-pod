import 'package:flutter_muxpod/services/agent/agent_types.dart';
import 'package:flutter_muxpod/services/agent/headless/chat_event.dart';
import 'package:flutter_muxpod/services/agent/headless/chat_event_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAgentOutputLine', () {
    group('noise tolerance', () {
      test('ignores blank lines', () {
        expect(parseAgentOutputLine(AgentKind.claudeCode, '   '), isEmpty);
      });

      test('ignores non-JSON lines', () {
        expect(
          parseAgentOutputLine(AgentKind.claudeCode, 'Loading plugins...'),
          isEmpty,
        );
      });

      test('ignores JSON values that are not objects', () {
        expect(parseAgentOutputLine(AgentKind.codex, '[1, 2, 3]'), isEmpty);
        expect(parseAgentOutputLine(AgentKind.codex, '"text"'), isEmpty);
        expect(parseAgentOutputLine(AgentKind.codex, '42'), isEmpty);
      });
    });

    group('claudeCode', () {
      test('parses system/init into SessionStarted', () {
        final events = parseAgentOutputLine(
          AgentKind.claudeCode,
          '{"type":"system","subtype":"init","session_id":"sess-1","model":"claude-sonnet-5"}',
        );
        expect(events, hasLength(1));
        expect(events[0], isA<SessionStarted>());
        expect((events[0] as SessionStarted).sessionId, 'sess-1');
      });

      test('parses assistant text block into TextDelta', () {
        final events = parseAgentOutputLine(
          AgentKind.claudeCode,
          '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello world"}]}}',
        );
        expect(events, hasLength(1));
        expect(events[0], isA<TextDelta>());
        expect((events[0] as TextDelta).text, 'Hello world');
      });

      test('parses thinking, text and tool_use blocks from one message', () {
        final events = parseAgentOutputLine(
          AgentKind.claudeCode,
          '{"type":"assistant","message":{"content":['
          '{"type":"thinking","thinking":"let me think"},'
          '{"type":"text","text":"answer"},'
          '{"type":"tool_use","name":"Bash","input":{"command":"ls"}}'
          ']}}',
        );
        expect(events, hasLength(3));
        expect(events[0], isA<ThinkingDelta>());
        expect((events[0] as ThinkingDelta).text, 'let me think');
        expect(events[1], isA<TextDelta>());
        expect(events[2], isA<ToolCallStarted>());
        expect((events[2] as ToolCallStarted).name, 'Bash');
      });

      test('parses successful result into UsageUpdated + RunCompleted', () {
        final events = parseAgentOutputLine(
          AgentKind.claudeCode,
          '{"type":"result","subtype":"success","is_error":false,'
          '"session_id":"sess-1","total_cost_usd":0.0123,'
          '"usage":{"input_tokens":100,"output_tokens":50}}',
        );
        expect(events, hasLength(2));
        final usage = events[0] as UsageUpdated;
        expect(usage.inputTokens, 100);
        expect(usage.outputTokens, 50);
        expect(usage.costUsd, closeTo(0.0123, 1e-9));
        expect(events[1], isA<RunCompleted>());
      });

      test('parses error result into RunFailed with result text', () {
        final events = parseAgentOutputLine(
          AgentKind.claudeCode,
          '{"type":"result","subtype":"error_max_turns","is_error":true,"result":"too many turns"}',
        );
        expect(events, hasLength(1));
        expect(events[0], isA<RunFailed>());
        expect((events[0] as RunFailed).message, 'too many turns');
      });

      test('ignores user tool_result messages', () {
        final events = parseAgentOutputLine(
          AgentKind.claudeCode,
          '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}',
        );
        expect(events, isEmpty);
      });
    });

    group('codex', () {
      test('parses thread.started into SessionStarted', () {
        final events = parseAgentOutputLine(
          AgentKind.codex,
          '{"type":"thread.started","thread_id":"0199a213-81c0-7800-8aa1-bbab2a035a53"}',
        );
        expect(events, hasLength(1));
        expect(
          (events[0] as SessionStarted).sessionId,
          '0199a213-81c0-7800-8aa1-bbab2a035a53',
        );
      });

      test('parses item.started tool item into ToolCallStarted', () {
        final events = parseAgentOutputLine(
          AgentKind.codex,
          '{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"bash -lc ls","status":"in_progress"}}',
        );
        expect(events, hasLength(1));
        expect((events[0] as ToolCallStarted).name, 'command_execution');
      });

      test('ignores item.started for non-tool items', () {
        final events = parseAgentOutputLine(
          AgentKind.codex,
          '{"type":"item.started","item":{"id":"item_1","type":"agent_message"}}',
        );
        expect(events, isEmpty);
      });

      test('parses item.completed agent_message into TextDelta', () {
        final events = parseAgentOutputLine(
          AgentKind.codex,
          '{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"Repo contains docs."}}',
        );
        expect(events, hasLength(1));
        expect((events[0] as TextDelta).text, 'Repo contains docs.');
      });

      test('parses item.completed reasoning into ThinkingDelta', () {
        final events = parseAgentOutputLine(
          AgentKind.codex,
          '{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"thinking hard"}}',
        );
        expect(events, hasLength(1));
        expect((events[0] as ThinkingDelta).text, 'thinking hard');
      });

      test('accepts reasoning text as a list of strings', () {
        final events = parseAgentOutputLine(
          AgentKind.codex,
          '{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":["part a","part b"]}}',
        );
        expect(events, hasLength(1));
        expect((events[0] as ThinkingDelta).text, 'part a\npart b');
      });

      test('parses turn.completed into UsageUpdated + RunCompleted', () {
        final events = parseAgentOutputLine(
          AgentKind.codex,
          '{"type":"turn.completed","usage":{"input_tokens":24763,"cached_input_tokens":24448,"output_tokens":122}}',
        );
        expect(events, hasLength(2));
        final usage = events[0] as UsageUpdated;
        expect(usage.inputTokens, 24763);
        expect(usage.outputTokens, 122);
        expect(events[1], isA<RunCompleted>());
      });

      test('parses turn.failed into RunFailed', () {
        final events = parseAgentOutputLine(
          AgentKind.codex,
          '{"type":"turn.failed","error":{"message":"model overloaded"}}',
        );
        expect(events, hasLength(1));
        expect((events[0] as RunFailed).message, 'model overloaded');
      });

      test('parses error event into RunFailed', () {
        final events = parseAgentOutputLine(
          AgentKind.codex,
          '{"type":"error","message":"stream disconnected"}',
        );
        expect(events, hasLength(1));
        expect((events[0] as RunFailed).message, 'stream disconnected');
      });

      test('ignores turn.started', () {
        expect(
          parseAgentOutputLine(AgentKind.codex, '{"type":"turn.started"}'),
          isEmpty,
        );
      });
    });

    group('droid', () {
      test('parses documented result shape into SessionStarted + RunCompleted',
          () {
        final events = parseAgentOutputLine(
          AgentKind.droid,
          '{"type":"result","subtype":"success","is_error":false,'
          '"duration_ms":5657,"num_turns":1,"result":"summary text",'
          '"session_id":"8af22e0a-d222-42c6-8c7e-7a059e391b0b"}',
        );
        expect(events, hasLength(2));
        expect(
          (events[0] as SessionStarted).sessionId,
          '8af22e0a-d222-42c6-8c7e-7a059e391b0b',
        );
        expect(events[1], isA<RunCompleted>());
      });

      test('parses error result into RunFailed', () {
        final events = parseAgentOutputLine(
          AgentKind.droid,
          '{"type":"result","subtype":"error","is_error":true,"result":"permission denied","session_id":"s-1"}',
        );
        expect(events, hasLength(2));
        expect(events[0], isA<SessionStarted>());
        expect((events[1] as RunFailed).message, 'permission denied');
      });

      test('parses Claude-compatible assistant message best-effort', () {
        final events = parseAgentOutputLine(
          AgentKind.droid,
          '{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}',
        );
        expect(events, hasLength(1));
        expect((events[0] as TextDelta).text, 'hi');
      });

      test('parses generic text event best-effort', () {
        final events = parseAgentOutputLine(
          AgentKind.droid,
          '{"type":"text","text":"streaming"}',
        );
        expect(events, hasLength(1));
        expect((events[0] as TextDelta).text, 'streaming');
      });

      test('parses generic tool event best-effort', () {
        final events = parseAgentOutputLine(
          AgentKind.droid,
          '{"type":"tool_call","name":"ApplyPatch"}',
        );
        expect(events, hasLength(1));
        expect((events[0] as ToolCallStarted).name, 'ApplyPatch');
      });
    });
  });

  group('parseAgentEventStream', () {
    test('reassembles a JSON line split across chunks', () async {
      const line =
          '{"type":"assistant","message":{"content":[{"type":"text","text":"split me"}]}}';
      final chunks = [
        line.substring(0, 10),
        line.substring(10, 40),
        '${line.substring(40)}\n',
      ];
      final events = await parseAgentEventStream(
        AgentKind.claudeCode,
        Stream.fromIterable(chunks),
      ).toList();
      expect(events, hasLength(1));
      expect((events[0] as TextDelta).text, 'split me');
    });

    test('parses multiple lines arriving in one chunk', () async {
      const chunk =
          '{"type":"system","subtype":"init","session_id":"s-1"}\n'
          '{"type":"assistant","message":{"content":[{"type":"text","text":"a"}]}}\n'
          '{"type":"assistant","message":{"content":[{"type":"text","text":"b"}]}}\n';
      final events = await parseAgentEventStream(
        AgentKind.claudeCode,
        Stream.value(chunk),
      ).toList();
      expect(events, hasLength(3));
      expect(events[0], isA<SessionStarted>());
      expect((events[1] as TextDelta).text, 'a');
      expect((events[2] as TextDelta).text, 'b');
    });

    test('flushes a trailing unterminated line when the stream closes',
        () async {
      final events = await parseAgentEventStream(
        AgentKind.codex,
        Stream.value('{"type":"turn.started"}\n{"type":"error","message":"x"}'),
      ).toList();
      expect(events, hasLength(1));
      expect(events[0], isA<RunFailed>());
    });

    test('skips noise lines interleaved with JSON', () async {
      const chunk = 'Compiling...\n'
          '{"type":"thread.started","thread_id":"t-1"}\n'
          'some warning\n';
      final events = await parseAgentEventStream(
        AgentKind.codex,
        Stream.value(chunk),
      ).toList();
      expect(events, hasLength(1));
      expect(events[0], isA<SessionStarted>());
    });

    test('propagates source stream errors', () async {
      final stream = parseAgentEventStream(
        AgentKind.claudeCode,
        Stream.error(StateError('ssh gone')),
      );
      await expectLater(stream.toList(), throwsA(isA<StateError>()));
    });
  });
}
