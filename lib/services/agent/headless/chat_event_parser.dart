/// Parses the newline-delimited JSON (NDJSON) output of headless AI CLI
/// agents into the unified [ChatEvent] hierarchy.
///
/// Output dialects (verified 2026-08):
///
/// * Claude Code (`claude -p --output-format stream-json --verbose`):
///   `system/init` (session_id), `assistant` (message.content blocks of
///   type `text` / `thinking` / `tool_use`), `result` (subtype, is_error,
///   usage, total_cost_usd, session_id).
///   https://code.claude.com/docs/en/cli-reference
///
/// * Codex CLI (`codex exec --json`): `thread.started` (thread_id),
///   `item.started` / `item.completed` (items of type `agent_message`,
///   `reasoning`, `command_execution`, `file_change`, `mcp_tool_call`,
///   `web_search`), `turn.completed` (usage), `turn.failed`, `error`.
///   https://developers.openai.com/codex/noninteractive
///
/// * Factory Droid (`droid exec -o stream-json`): the stream-json event
///   schema is not publicly documented; only the `result` object shape is
///   documented (`{"type":"result","subtype":"success","is_error":false,
///   "result":"...","session_id":"..."}`). The Droid parser therefore
///   handles the documented `result` shape strictly and interprets
///   Claude-like shapes (`system/init`, `assistant`, text/tool events)
///   best-effort. https://docs.factory.ai/droid-exec/overview
library;

import 'dart:async';
import 'dart:convert';

import '../agent_types.dart';
import 'chat_event.dart';

/// Transforms a stream of raw stdout chunks from a headless agent into
/// parsed [ChatEvent]s.
///
/// Chunks are arbitrary byte boundaries: lines may be split across chunks
/// or multiple lines may arrive in one chunk. A line buffer reassembles
/// them; a trailing unterminated line is flushed when the source closes.
/// Source stream errors propagate to the returned stream.
///
/// Implemented with a plain [StreamController] (not `async*`) so that
/// cancelling a subscription immediately cancels the source subscription —
/// an `async*` generator suspended in `await for` on a silent source does
/// not process cancellation until the source emits, which would hang
/// [HeadlessAgentSession.cancel].
Stream<ChatEvent> parseAgentEventStream(
  AgentKind kind,
  Stream<String> chunks,
) {
  late StreamController<ChatEvent> controller;
  StreamSubscription<String>? sourceSubscription;
  final pending = StringBuffer();

  void emitLines({required bool includeRemainder}) {
    final text = pending.toString();
    var start = 0;
    while (true) {
      final newline = text.indexOf('\n', start);
      if (newline == -1) break;
      for (final event
          in parseAgentOutputLine(kind, text.substring(start, newline))) {
        controller.add(event);
      }
      start = newline + 1;
    }
    pending
      ..clear()
      ..write(text.substring(start));
    if (includeRemainder) {
      final rest = pending.toString().trim();
      pending.clear();
      if (rest.isNotEmpty) {
        for (final event in parseAgentOutputLine(kind, rest)) {
          controller.add(event);
        }
      }
    }
  }

  controller = StreamController<ChatEvent>(
    onListen: () {
      sourceSubscription = chunks.listen(
        (chunk) {
          pending.write(chunk);
          emitLines(includeRemainder: false);
        },
        onError: (Object error, StackTrace stackTrace) =>
            controller.addError(error, stackTrace),
        onDone: () {
          emitLines(includeRemainder: true);
          controller.close();
        },
      );
    },
    onCancel: () => sourceSubscription?.cancel(),
  );
  return controller.stream;
}

/// Parses a single NDJSON line into zero or more [ChatEvent]s.
///
/// Returns an empty list for blank lines, non-JSON noise (progress
/// banners, warnings) and JSON values that are not objects — headless
/// tools occasionally print non-JSON lines to stdout.
List<ChatEvent> parseAgentOutputLine(AgentKind kind, String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return const [];

  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map<String, dynamic>) return const [];

  return switch (kind) {
    AgentKind.claudeCode => _parseClaudeEvent(decoded),
    AgentKind.codex => _parseCodexEvent(decoded),
    AgentKind.droid => _parseDroidEvent(decoded),
  };
}

/// Safe dynamic → int conversion (no casts on untrusted JSON).
int? _asInt(Object? value) => value is num ? value.toInt() : null;

/// Safe dynamic → double conversion.
double? _asDouble(Object? value) => value is num ? value.toDouble() : null;

List<ChatEvent> _parseClaudeEvent(Map<String, dynamic> json) {
  final type = json['type'];

  if (type == 'system') {
    if (json['subtype'] == 'init') {
      final sessionId = json['session_id'];
      if (sessionId is String && sessionId.isNotEmpty) {
        return [SessionStarted(sessionId)];
      }
    }
    return const [];
  }

  if (type == 'assistant') {
    return _parseClaudeAssistantContent(json['message']);
  }

  if (type == 'result') {
    final events = <ChatEvent>[];
    final usage = json['usage'];
    int? inputTokens;
    int? outputTokens;
    if (usage is Map<String, dynamic>) {
      inputTokens = _asInt(usage['input_tokens']);
      outputTokens = _asInt(usage['output_tokens']);
    }
    final costUsd = _asDouble(json['total_cost_usd']);
    if (inputTokens != null || outputTokens != null || costUsd != null) {
      events.add(UsageUpdated(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        costUsd: costUsd,
      ));
    }
    final subtype = json['subtype'];
    final failed =
        json['is_error'] == true || (subtype is String && subtype != 'success');
    if (failed) {
      final result = json['result'];
      events.add(RunFailed(
        result is String && result.isNotEmpty
            ? result
            : 'Claude run failed${subtype is String ? ' ($subtype)' : ''}',
      ));
    } else {
      events.add(const RunCompleted());
    }
    return events;
  }

  // user (tool_result), rate_limit_event, etc. carry no chat content.
  return const [];
}

/// Parses the content blocks of a Claude `assistant` message.
///
/// Shared with the Droid parser, whose stream-json assistant events are
/// expected to be Claude-compatible (best-effort, see library doc).
List<ChatEvent> _parseClaudeAssistantContent(Object? message) {
  if (message is! Map<String, dynamic>) return const [];
  final content = message['content'];
  if (content is! List) return const [];

  final events = <ChatEvent>[];
  for (final block in content) {
    if (block is! Map<String, dynamic>) continue;
    final blockType = block['type'];
    if (blockType == 'text') {
      final text = block['text'];
      if (text is String && text.isNotEmpty) events.add(TextDelta(text));
    } else if (blockType == 'thinking') {
      final thinking = block['thinking'];
      if (thinking is String && thinking.isNotEmpty) {
        events.add(ThinkingDelta(thinking));
      }
    } else if (blockType == 'tool_use') {
      final name = block['name'];
      if (name is String && name.isNotEmpty) events.add(ToolCallStarted(name));
    }
  }
  return events;
}

/// Codex item types that represent tool invocations.
/// https://developers.openai.com/codex/noninteractive
const _codexToolItemTypes = {
  'command_execution',
  'file_change',
  'mcp_tool_call',
  'web_search',
};

List<ChatEvent> _parseCodexEvent(Map<String, dynamic> json) {
  final type = json['type'];

  if (type == 'thread.started') {
    final threadId = json['thread_id'];
    if (threadId is String && threadId.isNotEmpty) {
      return [SessionStarted(threadId)];
    }
    return const [];
  }

  if (type == 'item.started') {
    final item = json['item'];
    if (item is! Map<String, dynamic>) return const [];
    final itemType = item['type'];
    if (itemType is String && _codexToolItemTypes.contains(itemType)) {
      return [ToolCallStarted(itemType)];
    }
    return const [];
  }

  if (type == 'item.completed') {
    final item = json['item'];
    if (item is! Map<String, dynamic>) return const [];
    final itemType = item['type'];
    if (itemType == 'agent_message') {
      final text = item['text'];
      if (text is String && text.isNotEmpty) return [TextDelta(text)];
    } else if (itemType == 'reasoning') {
      // `text` is a plain string in current releases; older builds emitted
      // a list of strings. Accept both.
      final raw = item['text'];
      final text = switch (raw) {
        String s => s,
        List l => l.whereType<String>().join('\n'),
        _ => '',
      };
      if (text.isNotEmpty) return [ThinkingDelta(text)];
    }
    return const [];
  }

  if (type == 'turn.completed') {
    final events = <ChatEvent>[];
    final usage = json['usage'];
    if (usage is Map<String, dynamic>) {
      events.add(UsageUpdated(
        inputTokens: _asInt(usage['input_tokens']),
        outputTokens: _asInt(usage['output_tokens']),
      ));
    }
    events.add(const RunCompleted());
    return events;
  }

  if (type == 'turn.failed') {
    final error = json['error'];
    String? message;
    if (error is Map<String, dynamic>) {
      final m = error['message'];
      if (m is String && m.isNotEmpty) message = m;
    } else if (error is String && error.isNotEmpty) {
      message = error;
    }
    return [RunFailed(message ?? 'Codex turn failed')];
  }

  if (type == 'error') {
    final message = json['message'];
    return [
      RunFailed(message is String && message.isNotEmpty ? message : 'Codex error'),
    ];
  }

  // turn.started and friends carry no chat content.
  return const [];
}

List<ChatEvent> _parseDroidEvent(Map<String, dynamic> json) {
  final type = json['type'];

  // Documented shape (also the whole payload of `-o json`):
  // {"type":"result","subtype":"success","is_error":false,"duration_ms":N,
  //  "num_turns":N,"result":"...","session_id":"..."}
  if (type == 'result') {
    final events = <ChatEvent>[];
    final sessionId = json['session_id'];
    if (sessionId is String && sessionId.isNotEmpty) {
      events.add(SessionStarted(sessionId));
    }
    final subtype = json['subtype'];
    final failed =
        json['is_error'] == true || (subtype is String && subtype != 'success');
    final result = json['result'];
    if (failed) {
      events.add(RunFailed(
        result is String && result.isNotEmpty ? result : 'Droid run failed',
      ));
    } else {
      events.add(const RunCompleted());
    }
    return events;
  }

  // Best-effort Claude-compatible shapes (stream-json schema undocumented).
  if (type == 'system' && json['subtype'] == 'init') {
    final sessionId = json['session_id'];
    if (sessionId is String && sessionId.isNotEmpty) {
      return [SessionStarted(sessionId)];
    }
    return const [];
  }
  if (type == 'assistant') {
    return _parseClaudeAssistantContent(json['message']);
  }
  if (type == 'text' || type == 'text_delta' || type == 'message') {
    final text = json['text'] ?? json['delta'];
    if (text is String && text.isNotEmpty) return [TextDelta(text)];
    return const [];
  }
  if (type == 'tool_call' || type == 'tool_use' || type == 'tool.started') {
    final name = json['name'] ?? json['tool'];
    if (name is String && name.isNotEmpty) return [ToolCallStarted(name)];
    return const [];
  }

  return const [];
}
