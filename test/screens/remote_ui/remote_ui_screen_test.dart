import 'package:flutter/material.dart';
import 'package:flutter_muxpod/providers/remote_ui_chat_provider.dart';
import 'package:flutter_muxpod/providers/remote_ui_provider.dart';
import 'package:flutter_muxpod/screens/remote_ui/remote_ui_screen.dart';
import 'package:flutter_muxpod/services/agent/agent_types.dart';
import 'package:flutter_muxpod/services/agent/claude_code_adapter.dart';
import 'package:flutter_muxpod/services/agent/headless/chat_session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remote UI provider with a fixed state; apply calls are recorded
/// instead of touching SSH/tmux.
class _FixedRemoteUiNotifier extends RemoteUiNotifier {
  _FixedRemoteUiNotifier(this._initialState);

  final RemoteUiState _initialState;

  final List<String> appliedModels = [];
  final List<UnifiedIntelligence> appliedIntelligence = [];
  final List<UnifiedPermission> appliedPermissions = [];
  final List<bool> planModeCalls = [];

  @override
  RemoteUiState build() => _initialState;

  @override
  Future<void> applyModel(String model) async {
    appliedModels.add(model);
  }

  @override
  Future<void> applyIntelligence(UnifiedIntelligence level) async {
    appliedIntelligence.add(level);
  }

  @override
  Future<void> applyPermission(UnifiedPermission level) async {
    appliedPermissions.add(level);
  }

  @override
  Future<void> setPlanMode(bool enabled) async {
    planModeCalls.add(enabled);
  }
}

/// Chat provider with a fixed initial state. Network/store operations
/// are recorded; the pure state setters are inherited from the base
/// notifier.
class _FakeRemoteUiChatNotifier extends RemoteUiChatNotifier {
  _FakeRemoteUiChatNotifier(this._initialState);

  final RemoteUiChatState _initialState;

  final List<String> sentTexts = [];
  int cancelCalls = 0;
  int newSessionCalls = 0;
  int clearHistoryCalls = 0;
  AgentKind? selectedAgent;
  String? openedSessionId;

  @override
  RemoteUiChatState build() => _initialState;

  @override
  Future<void> selectAgent(AgentKind kind) async {
    selectedAgent = kind;
    state = state.copyWith(
      agentKind: kind,
      pendingConfig: const AgentConfig(),
    );
  }

  @override
  Future<void> loadSessions() async {}

  @override
  Future<void> newSession() async {
    newSessionCalls++;
    state = state.copyWith(
      activeSessionId: null,
      messages: const [],
      streamingText: '',
      isStreaming: false,
    );
  }

  @override
  Future<void> openSession(String sessionId) async {
    openedSessionId = sessionId;
    final session =
        state.sessions.where((s) => s.id == sessionId).firstOrNull;
    if (session == null) return;
    state = state.copyWith(
      activeSessionId: sessionId,
      messages: session.messages,
      streamingText: '',
      isStreaming: false,
    );
  }

  @override
  Future<void> send(String text) async {
    sentTexts.add(text);
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    state = state.copyWith(isStreaming: false, streamingText: '');
  }

  @override
  Future<void> clearHistory() async {
    clearHistoryCalls++;
    state = state.copyWith(
      sessions: const [],
      activeSessionId: null,
      messages: const [],
    );
  }
}

Widget _buildApp(
  _FakeRemoteUiChatNotifier chat, {
  _FixedRemoteUiNotifier? remote,
}) {
  return ProviderScope(
    overrides: [
      remoteUiProvider.overrideWith(
        () => remote ?? _FixedRemoteUiNotifier(const RemoteUiState()),
      ),
      remoteUiChatProvider.overrideWith(() => chat),
    ],
    child: const MaterialApp(home: RemoteUiScreen()),
  );
}

ChatMessageRecord _userMessage(String text) => ChatMessageRecord(
      role: ChatRole.user,
      text: text,
      timestamp: DateTime(2026, 8, 8, 12),
    );

void main() {
  setUp(() {
    // ConnectionsNotifier loads from SharedPreferences at build time.
    SharedPreferences.setMockInitialValues({});
  });

  group('RemoteUiScreen', () {
    testWidgets('empty state renders server picker, toggle and agent picker',
        (tester) async {
      final chat = _FakeRemoteUiChatNotifier(const RemoteUiChatState());
      await tester.pumpWidget(_buildApp(chat));
      await tester.pumpAndSettle();

      expect(find.text("Let's work on"), findsOneWidget);
      expect(find.text('Select a server'), findsOneWidget);
      expect(find.text('Workspace'), findsOneWidget);
      expect(find.text('Worktree'), findsOneWidget);
      expect(find.byKey(const Key('remote_ui.agent_picker')), findsOneWidget);
      expect(find.text('New chat'), findsOneWidget);

      // No mockup placeholder model names; the default label is "Auto".
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('GPT-5.6-Sol'), findsNothing);

      // The mic button was removed (no backend exists).
      expect(find.byIcon(Icons.mic_none_outlined), findsNothing);
      expect(find.byKey(const Key('remote_ui.send_button')), findsOneWidget);
    });

    testWidgets('chips open sheets and reflect the pending config selection',
        (tester) async {
      final chat = _FakeRemoteUiChatNotifier(const RemoteUiChatState());
      await tester.pumpWidget(_buildApp(chat));
      await tester.pumpAndSettle();

      // Model + intelligence chip.
      await tester.tap(find.byKey(const Key('remote_ui.model_chip')));
      await tester.pumpAndSettle();
      expect(find.text('Intelligence'), findsOneWidget);
      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();
      expect(find.text('Auto High'), findsOneWidget);
      expect(chat.state.pendingConfig.intelligence, UnifiedIntelligence.high);

      // Permission chip.
      await tester.tap(find.byKey(const Key('remote_ui.permission_chip')));
      await tester.pumpAndSettle();
      expect(find.text('Permissions'), findsWidgets); // chip + sheet header
      await tester.tap(find.text('Read only'));
      await tester.pumpAndSettle();
      expect(find.text('Read only'), findsOneWidget);
      expect(chat.state.pendingConfig.permission, UnifiedPermission.readOnly);
    });

    testWidgets('agent picker appears in chat mode and switches the agent',
        (tester) async {
      final chat = _FakeRemoteUiChatNotifier(const RemoteUiChatState());
      await tester.pumpWidget(_buildApp(chat));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_ui.agent_picker')));
      await tester.pumpAndSettle();

      expect(find.text('Claude Code'), findsWidgets); // picker row + sheet
      expect(find.text('Codex CLI'), findsOneWidget);
      expect(find.text('Factory Droid'), findsOneWidget);

      await tester.tap(find.text('Codex CLI'));
      await tester.pumpAndSettle();

      expect(chat.selectedAgent, AgentKind.codex);
      expect(find.text('Codex CLI'), findsOneWidget); // picker row label
    });

    testWidgets('live mode hides the agent picker and shows the live config',
        (tester) async {
      final remote = _FixedRemoteUiNotifier(
        RemoteUiState(
          connectionId: 'c1',
          isConnected: true,
          agent: ClaudeCodeAdapter(),
          agentPaneId: '%3',
          config: const AgentConfig(
            model: 'sonnet',
            intelligence: UnifiedIntelligence.medium,
            permission: UnifiedPermission.defaultPermissions,
          ),
        ),
      );
      final chat = _FakeRemoteUiChatNotifier(const RemoteUiChatState());
      await tester.pumpWidget(_buildApp(chat, remote: remote));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_ui.agent_picker')), findsNothing);
      expect(find.text('sonnet Medium'), findsOneWidget);
      expect(find.text('Default permissions'), findsOneWidget);
      expect(find.text('Detected: Claude Code (pane %3)'), findsOneWidget);
      expect(remote.appliedModels, isEmpty);
    });

    testWidgets('live mode applies sheet changes through remoteUiProvider',
        (tester) async {
      final remote = _FixedRemoteUiNotifier(
        RemoteUiState(
          connectionId: 'c1',
          isConnected: true,
          agent: ClaudeCodeAdapter(),
          agentPaneId: '%3',
          config: const AgentConfig(
            model: 'sonnet',
            intelligence: UnifiedIntelligence.medium,
          ),
        ),
      );
      final chat = _FakeRemoteUiChatNotifier(const RemoteUiChatState());
      await tester.pumpWidget(_buildApp(chat, remote: remote));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_ui.model_chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();

      // Only the changed value is applied; the unchanged model is not
      // re-applied.
      expect(remote.appliedIntelligence, [UnifiedIntelligence.high]);
      expect(remote.appliedModels, isEmpty);
      // Chat pending config stays untouched in live mode.
      expect(chat.state.pendingConfig.intelligence, isNull);
    });

    testWidgets('sending a message calls the chat provider and clears field',
        (tester) async {
      final chat = _FakeRemoteUiChatNotifier(const RemoteUiChatState());
      await tester.pumpWidget(_buildApp(chat));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('remote_ui.composer')),
        'fix the flaky test',
      );
      await tester.tap(find.byKey(const Key('remote_ui.send_button')));
      await tester.pumpAndSettle();

      expect(chat.sentTexts, ['fix the flaky test']);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('remote_ui.composer')))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('shows a stop button while streaming; stop cancels the run',
        (tester) async {
      final chat = _FakeRemoteUiChatNotifier(
        RemoteUiChatState(
          activeSessionId: 's1',
          messages: [_userMessage('hello')],
          streamingText: 'Working on it',
          isStreaming: true,
        ),
      );
      await tester.pumpWidget(_buildApp(chat));
      // No pumpAndSettle here: the streaming cursor blinks on a timer.
      await tester.pump();

      expect(find.byKey(const Key('remote_ui.message_list')), findsOneWidget);
      // The user bubble inside the message list (the app-bar title is
      // derived from the first user message and also shows "hello").
      expect(
        find.descendant(
          of: find.byKey(const Key('remote_ui.message_list')),
          matching: find.text('hello'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Working on it'), findsOneWidget);
      expect(find.byKey(const Key('remote_ui.stop_button')), findsOneWidget);
      expect(find.byKey(const Key('remote_ui.send_button')), findsNothing);

      await tester.tap(find.byKey(const Key('remote_ui.stop_button')));
      await tester.pump();

      expect(chat.cancelCalls, 1);
      expect(find.byKey(const Key('remote_ui.send_button')), findsOneWidget);
      // The streaming bubble is gone, so no timers remain pending.
      await tester.pumpAndSettle();
    });

    testWidgets('history sheet lists sessions and opens one', (tester) async {
      final session = ChatSessionRecord(
        id: 's1',
        agentKind: AgentKind.claudeCode,
        title: 'Fix bug',
        createdAt: DateTime(2026, 8, 8, 12, 30),
        messages: [_userMessage('hi')],
      );
      final chat = _FakeRemoteUiChatNotifier(
        RemoteUiChatState(sessions: [session]),
      );
      await tester.pumpWidget(_buildApp(chat));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_ui.history_button')));
      await tester.pumpAndSettle();

      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Fix bug'), findsOneWidget);

      await tester.tap(find.text('Fix bug'));
      await tester.pumpAndSettle();

      expect(chat.openedSessionId, 's1');
      expect(find.text('hi'), findsOneWidget); // message list shown
    });

    testWidgets('clear history asks for confirmation', (tester) async {
      final session = ChatSessionRecord(
        id: 's1',
        agentKind: AgentKind.claudeCode,
        title: 'Fix bug',
        createdAt: DateTime(2026, 8, 8, 12, 30),
        messages: const [],
      );
      final chat = _FakeRemoteUiChatNotifier(
        RemoteUiChatState(sessions: [session]),
      );
      await tester.pumpWidget(_buildApp(chat));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_ui.history_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();

      expect(find.text('Clear history?'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(chat.clearHistoryCalls, 1);
    });

    testWidgets('new chat button resets the conversation', (tester) async {
      final chat = _FakeRemoteUiChatNotifier(
        RemoteUiChatState(
          activeSessionId: 's1',
          messages: [_userMessage('hello')],
        ),
      );
      await tester.pumpWidget(_buildApp(chat));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('remote_ui.message_list')),
          matching: find.text('hello'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('remote_ui.new_chat_button')));
      await tester.pumpAndSettle();

      expect(chat.newSessionCalls, 1);
      expect(find.text("Let's work on"), findsOneWidget);
    });

    testWidgets('workspace/worktree toggle updates the chat provider',
        (tester) async {
      final chat = _FakeRemoteUiChatNotifier(const RemoteUiChatState());
      await tester.pumpWidget(_buildApp(chat));
      await tester.pumpAndSettle();

      expect(chat.state.worktreeMode, isFalse);
      await tester.tap(find.text('Worktree'));
      await tester.pumpAndSettle();
      expect(chat.state.worktreeMode, isTrue);
    });

    testWidgets('plus menu toggles plan mode; upload without server hints',
        (tester) async {
      final chat = _FakeRemoteUiChatNotifier(const RemoteUiChatState());
      await tester.pumpWidget(_buildApp(chat));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_ui.plus_button')));
      await tester.pumpAndSettle();

      expect(find.text('Upload photo'), findsOneWidget);
      expect(find.text('Plan mode'), findsOneWidget);

      await tester.tap(find.text('Plan mode'));
      await tester.pumpAndSettle();
      expect(chat.state.pendingConfig.planModeActive, isTrue);

      // Upload photo without a connected server shows an explanation.
      await tester.tap(find.text('Upload photo'));
      await tester.pumpAndSettle();
      expect(
        find.text('Connect to a server first to upload a photo.'),
        findsOneWidget,
      );
      // Flush the snackbar's auto-dismiss timer.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}
