import 'dart:convert';

import 'package:flutter_muxpod/providers/remote_ui_chat_provider.dart';
import 'package:flutter_muxpod/providers/remote_ui_provider.dart';
import 'package:flutter_muxpod/services/agent/agent_types.dart';
import 'package:flutter_muxpod/services/agent/headless/chat_session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RemoteUiNotifier with a fixed connected state (no real SSH).
class _FixedRemoteUiNotifier extends RemoteUiNotifier {
  _FixedRemoteUiNotifier(this._state);

  final RemoteUiState _state;

  @override
  RemoteUiState build() => _state;
}

/// Chat notifier seeded into a mid-streaming state, as if a headless run
/// were in flight (the run itself is not reproducible without SSH; the
/// streaming state is what cancel()/openSession() must handle).
class _StreamingChatNotifier extends RemoteUiChatNotifier {
  @override
  RemoteUiChatState build() {
    super.build();
    return const RemoteUiChatState(
      activeSessionId: 's1',
      isStreaming: true,
      streamingText: 'partial answer',
      messages: [],
    );
  }
}

String _sessionsPayload() {
  return jsonEncode([
    {
      'id': 's1',
      'agentKind': 'claudeCode',
      'title': 'first',
      'createdAt': '2026-08-08T12:00:00.000',
      'messages': [
        {'role': 'user', 'text': 'hi', 'timestamp': '2026-08-08T12:00:01.000'},
      ],
    },
    {
      'id': 's2',
      'agentKind': 'claudeCode',
      'title': 'second',
      'createdAt': '2026-08-08T12:10:00.000',
      'messages': [
        {
          'role': 'user',
          'text': 'other',
          'timestamp': '2026-08-08T12:10:01.000',
        },
      ],
    },
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'remote_ui_chat_sessions_c1_claudeCode': _sessionsPayload(),
    });
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        remoteUiProvider.overrideWith(
          () => _FixedRemoteUiNotifier(
            const RemoteUiState(connectionId: 'c1', isConnected: true),
          ),
        ),
        remoteUiChatProvider.overrideWith(_StreamingChatNotifier.new),
      ],
    );
  }

  group('RemoteUiChatNotifier streaming lifecycle', () {
    test('cancel resets isStreaming and persists the partial response',
        () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(remoteUiChatProvider.notifier);
      await notifier.loadSessions();

      await notifier.cancel();

      final state = container.read(remoteUiChatProvider);
      expect(state.isStreaming, isFalse);
      expect(state.streamingText, isEmpty);
      // The partial response lands in the visible (still active) session.
      expect(state.messages.last.text, 'partial answer');
      expect(state.messages.last.role, ChatRole.assistant);

      // And it is persisted under the correct session id.
      final stored = await ChatSessionStore().load('c1', AgentKind.claudeCode);
      final s1 = stored.firstWhere((s) => s.id == 's1');
      expect(s1.messages.last.text, 'partial answer');
      expect(s1.messages.last.role, ChatRole.assistant);
    });

    test('openSession mid-stream finalizes the old run without corrupting '
        'the newly opened session', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(remoteUiChatProvider.notifier);
      await notifier.loadSessions();

      await notifier.openSession('s2');

      final state = container.read(remoteUiChatProvider);
      expect(state.activeSessionId, 's2');
      expect(state.isStreaming, isFalse);
      // The opened session shows only its own messages.
      expect(state.messages.map((m) => m.text), ['other']);

      // The old session kept the partial response; the new one did not.
      final stored = await ChatSessionStore().load('c1', AgentKind.claudeCode);
      final s1 = stored.firstWhere((s) => s.id == 's1');
      final s2 = stored.firstWhere((s) => s.id == 's2');
      expect(s1.messages.last.text, 'partial answer');
      expect(s2.messages.length, 1);
    });

    test('newSession mid-stream clears streaming state', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(remoteUiChatProvider.notifier);
      await notifier.loadSessions();

      await notifier.newSession();

      final state = container.read(remoteUiChatProvider);
      expect(state.activeSessionId, isNull);
      expect(state.isStreaming, isFalse);
      expect(state.messages, isEmpty);
    });
  });
}
