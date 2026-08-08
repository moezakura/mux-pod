import 'package:flutter_muxpod/services/agent/agent_types.dart';
import 'package:flutter_muxpod/services/agent/headless/chat_session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatSessionStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = ChatSessionStore();
  });

  ChatMessageRecord userMessage(String text) => ChatMessageRecord(
        role: ChatRole.user,
        text: text,
        timestamp: DateTime.utc(2026, 8, 8, 12),
      );

  ChatMessageRecord assistantMessage(String text) => ChatMessageRecord(
        role: ChatRole.assistant,
        text: text,
        timestamp: DateTime.utc(2026, 8, 8, 12, 1),
      );

  group('ChatSessionStore', () {
    test('returns an empty list when nothing is stored', () async {
      expect(await store.load('conn-1', AgentKind.claudeCode), isEmpty);
    });

    test('createSession + load round-trips', () async {
      final created = await store.createSession(
        'conn-1',
        AgentKind.claudeCode,
        title: 'My chat',
      );

      final sessions = await store.load('conn-1', AgentKind.claudeCode);
      expect(sessions, hasLength(1));
      final loaded = sessions[0];
      expect(loaded.id, created.id);
      expect(loaded.agentKind, AgentKind.claudeCode);
      expect(loaded.title, 'My chat');
      expect(loaded.createdAt, created.createdAt);
      expect(loaded.messages, isEmpty);
    });

    test('addMessage appends and derives the title from the first user '
        'message', () async {
      final session = await store.createSession('conn-1', AgentKind.codex);
      await store.addMessage(
        'conn-1',
        AgentKind.codex,
        session.id,
        userMessage('summarize the repo'),
      );
      await store.addMessage(
        'conn-1',
        AgentKind.codex,
        session.id,
        assistantMessage('It contains docs and src.'),
      );

      final sessions = await store.load('conn-1', AgentKind.codex);
      expect(sessions, hasLength(1));
      expect(sessions[0].title, 'summarize the repo');
      expect(sessions[0].messages, hasLength(2));
      expect(sessions[0].messages[0].role, ChatRole.user);
      expect(sessions[0].messages[0].text, 'summarize the repo');
      expect(sessions[0].messages[1].role, ChatRole.assistant);
      expect(
        sessions[0].messages[0].timestamp,
        DateTime.utc(2026, 8, 8, 12),
      );
    });

    test('truncates long derived titles', () async {
      final session = await store.createSession('conn-1', AgentKind.droid);
      await store.addMessage(
        'conn-1',
        AgentKind.droid,
        session.id,
        userMessage('x' * 100),
      );
      final sessions = await store.load('conn-1', AgentKind.droid);
      expect(sessions[0].title.length, 41); // 40 chars + ellipsis
    });

    test('addMessage ignores unknown session ids', () async {
      await store.createSession('conn-1', AgentKind.codex);
      await store.addMessage(
        'conn-1',
        AgentKind.codex,
        'no-such-session',
        userMessage('hi'),
      );
      final sessions = await store.load('conn-1', AgentKind.codex);
      expect(sessions[0].messages, isEmpty);
    });

    test('keeps at most 50 sessions, dropping the oldest', () async {
      for (var i = 0; i < 55; i++) {
        await store.createSession('conn-1', AgentKind.claudeCode,
            title: 'chat $i');
      }
      final sessions = await store.load('conn-1', AgentKind.claudeCode);
      expect(sessions, hasLength(50));
      // Newest-first: the latest session is at the front, the five oldest
      // (chat 0..4) were dropped.
      expect(sessions.first.title, 'chat 54');
      expect(sessions.last.title, 'chat 5');
    });

    test('save overwrites the list', () async {
      final a = await store.createSession('conn-1', AgentKind.codex);
      await store.createSession('conn-1', AgentKind.codex);
      await store.save('conn-1', AgentKind.codex, [a]);
      final sessions = await store.load('conn-1', AgentKind.codex);
      expect(sessions, hasLength(1));
      expect(sessions[0].id, a.id);
    });

    test('clear removes all sessions for the pair', () async {
      await store.createSession('conn-1', AgentKind.claudeCode);
      await store.clear('conn-1', AgentKind.claudeCode);
      expect(await store.load('conn-1', AgentKind.claudeCode), isEmpty);
    });

    test('histories are isolated per connection and agent kind', () async {
      await store.createSession('conn-1', AgentKind.claudeCode);
      await store.createSession('conn-2', AgentKind.claudeCode);
      await store.createSession('conn-1', AgentKind.droid);

      expect(await store.load('conn-1', AgentKind.claudeCode), hasLength(1));
      expect(await store.load('conn-2', AgentKind.claudeCode), hasLength(1));
      expect(await store.load('conn-1', AgentKind.droid), hasLength(1));
      expect(await store.load('conn-2', AgentKind.droid), isEmpty);
      expect(await store.load('conn-1', AgentKind.codex), isEmpty);
    });

    test('returns an empty list for corrupted JSON', () async {
      SharedPreferences.setMockInitialValues({
        'remote_ui_chat_sessions_conn-1_claudeCode': 'not json {{{',
      });
      expect(await store.load('conn-1', AgentKind.claudeCode), isEmpty);
    });

    test('skips malformed entries inside a valid list', () async {
      SharedPreferences.setMockInitialValues({
        'remote_ui_chat_sessions_conn-1_codex':
            '[{"broken": true}, {"id": "s-1", "agentKind": "codex", '
                '"title": "ok", "createdAt": "2026-08-08T12:00:00.000Z", '
                '"messages": []}]',
      });
      final sessions = await store.load('conn-1', AgentKind.codex);
      expect(sessions, hasLength(1));
      expect(sessions[0].id, 's-1');
    });
  });
}
