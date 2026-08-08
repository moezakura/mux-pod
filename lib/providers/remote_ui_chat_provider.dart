import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/agent/agent_registry.dart';
import '../services/agent/agent_types.dart';
import '../services/agent/headless/chat_event.dart';
import '../services/agent/headless/chat_session_store.dart';
import '../services/agent/headless/headless_agent_session.dart';
import '../services/ssh/connection_credentials.dart';
import '../services/ssh/ssh_client.dart';
import 'connection_provider.dart';
import 'remote_ui_provider.dart';

/// State for the Remote UI chat: the selected agent, the configuration
/// applied to the next headless run, session history, and the live
/// streaming response.
class RemoteUiChatState {
  /// Agent the chat runs on.
  final AgentKind agentKind;

  /// Configuration applied to the next headless run (the chips' state
  /// when no live pane agent is detected).
  final AgentConfig pendingConfig;

  /// Stored sessions for the current (connection, agent) pair.
  final List<ChatSessionRecord> sessions;

  /// Currently open session id, null on the empty "New chat" screen.
  final String? activeSessionId;

  /// Messages of the active session, chronological.
  final List<ChatMessageRecord> messages;

  /// Accumulating assistant text of the in-flight run.
  final String streamingText;

  /// True while a headless run is streaming.
  final bool isStreaming;

  /// Workspace/Worktree toggle: when true, prompts run in a dedicated
  /// git worktree instead of the base working directory.
  final bool worktreeMode;

  /// Last error message, if any.
  final String? error;

  const RemoteUiChatState({
    this.agentKind = AgentKind.claudeCode,
    this.pendingConfig = const AgentConfig(),
    this.sessions = const [],
    this.activeSessionId,
    this.messages = const [],
    this.streamingText = '',
    this.isStreaming = false,
    this.worktreeMode = false,
    this.error,
  });

  static const _unset = Object();

  RemoteUiChatState copyWith({
    AgentKind? agentKind,
    AgentConfig? pendingConfig,
    List<ChatSessionRecord>? sessions,
    Object? activeSessionId = _unset,
    List<ChatMessageRecord>? messages,
    String? streamingText,
    bool? isStreaming,
    bool? worktreeMode,
    Object? error = _unset,
  }) {
    return RemoteUiChatState(
      agentKind: agentKind ?? this.agentKind,
      pendingConfig: pendingConfig ?? this.pendingConfig,
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId == _unset
          ? this.activeSessionId
          : activeSessionId as String?,
      messages: messages ?? this.messages,
      streamingText: streamingText ?? this.streamingText,
      isStreaming: isStreaming ?? this.isStreaming,
      worktreeMode: worktreeMode ?? this.worktreeMode,
      error: error == _unset ? this.error : error as String?,
    );
  }
}

/// Drives the Remote UI chat: session history plus headless streaming
/// runs over a dedicated SSH connection.
///
/// This connection is separate from `remoteUiProvider`'s control
/// connection because `SshClient.execStream` holds the exec lock for the
/// whole stream lifetime.
class RemoteUiChatNotifier extends Notifier<RemoteUiChatState> {
  final ChatSessionStore _store = ChatSessionStore();
  SshClient? _chatClient;
  String? _chatClientConnectionId;
  HeadlessAgentSession? _session;
  StreamSubscription<ChatEvent>? _eventSub;

  /// Synchronous re-entrancy guard for [send]: `isStreaming` is only set
  /// after the first await, so a rapid double-tap could otherwise slip
  /// through the state check.
  bool _sendInProgress = false;

  @override
  RemoteUiChatState build() {
    ref.onDispose(() {
      unawaited(_eventSub?.cancel());
      unawaited(_session?.dispose());
      unawaited(_chatClient?.disconnect());
    });
    return const RemoteUiChatState();
  }

  /// Capabilities of the currently selected chat agent.
  AgentCapabilities get capabilities => AgentRegistry.adapters
      .firstWhere((a) => a.kind == state.agentKind)
      .capabilities;

  /// Selects the chat agent, resets the pending configuration to its
  /// supported defaults, and loads its session history.
  Future<void> selectAgent(AgentKind kind) async {
    if (kind == state.agentKind) return;
    await cancel();
    state = state.copyWith(
      agentKind: kind,
      pendingConfig: const AgentConfig(),
      activeSessionId: null,
      messages: const [],
      streamingText: '',
      error: null,
    );
    await loadSessions();
  }

  /// Loads the stored sessions for the current (connection, agent) pair.
  Future<void> loadSessions() async {
    final connectionId = ref.read(remoteUiProvider).connectionId;
    if (connectionId == null) return;
    final sessions = await _store.load(connectionId, state.agentKind);
    state = state.copyWith(sessions: sessions);
  }

  /// Starts a new empty chat (the "New chat" screen).
  ///
  /// Cancels any in-flight run first so its events cannot leak into the
  /// fresh conversation.
  Future<void> newSession() async {
    await cancel();
    state = state.copyWith(
      activeSessionId: null,
      messages: const [],
      streamingText: '',
      error: null,
    );
  }

  /// Opens a stored session and shows its messages.
  ///
  /// Cancels any in-flight run first so its completion cannot append the
  /// previous conversation's reply to the newly opened session.
  Future<void> openSession(String sessionId) async {
    final session =
        state.sessions.where((s) => s.id == sessionId).firstOrNull;
    if (session == null) return;
    await cancel();
    state = state.copyWith(
      activeSessionId: sessionId,
      messages: session.messages,
      streamingText: '',
      error: null,
    );
  }

  /// Updates the model used by the next headless run.
  void setModel(String? model) {
    state = state.copyWith(
      pendingConfig: state.pendingConfig.copyWith(model: model),
    );
  }

  /// Updates the reasoning effort used by the next headless run.
  void setIntelligence(UnifiedIntelligence? level) {
    state = state.copyWith(
      pendingConfig: state.pendingConfig.copyWith(intelligence: level),
    );
  }

  /// Updates the autonomy level used by the next headless run.
  void setPermission(UnifiedPermission? level) {
    state = state.copyWith(
      pendingConfig: state.pendingConfig.copyWith(permission: level),
    );
  }

  /// Toggles plan/spec mode for the next headless run.
  void setPlanMode(bool enabled) {
    state = state.copyWith(
      pendingConfig: state.pendingConfig.copyWith(planModeActive: enabled),
    );
  }

  /// Switches between Workspace and Worktree mode.
  void setWorktreeMode(bool worktree) {
    state = state.copyWith(worktreeMode: worktree);
  }

  /// Sends [text] to the agent, streaming the response into state.
  ///
  /// Creates a stored session on the first message. Follow-up messages
  /// resume the agent-side session when one was captured.
  Future<void> send(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty || state.isStreaming || _sendInProgress) return;
    _sendInProgress = true;
    try {
      await _send(prompt);
    } finally {
      _sendInProgress = false;
    }
  }

  Future<void> _send(String prompt) async {
    final connectionId = ref.read(remoteUiProvider).connectionId;
    if (connectionId == null) {
      state = state.copyWith(error: 'Select a server first');
      return;
    }

    final client = await _ensureChatClient(connectionId);
    if (client == null) return;

    // Ensure an active stored session.
    var activeId = state.activeSessionId;
    if (activeId == null) {
      final created = await _store.createSession(
        connectionId,
        state.agentKind,
      );
      activeId = created.id;
      state = state.copyWith(
        activeSessionId: activeId,
        sessions: [created, ...state.sessions],
      );
    }

    final userMessage = ChatMessageRecord(
      role: ChatRole.user,
      text: prompt,
      timestamp: DateTime.now(),
    );
    await _store.addMessage(
      connectionId,
      state.agentKind,
      activeId,
      userMessage,
    );
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      streamingText: '',
      isStreaming: true,
      error: null,
    );

    final activeSession =
        state.sessions.where((s) => s.id == activeId).firstOrNull;

    final workingDirectory = await _resolveWorkingDirectory(client);
    final config = state.pendingConfig;
    final session = HeadlessAgentSession(
      ssh: client,
      kind: state.agentKind,
      model: config.model,
      intelligence: config.intelligence,
      permission: config.permission,
      planMode: config.planModeActive,
      workingDirectory: workingDirectory,
      resumeSessionId: activeSession?.remoteSessionId,
    );
    // Release the previous run's listener/session before overwriting;
    // otherwise each completed run leaks a broadcast subscription.
    await _eventSub?.cancel();
    await _session?.dispose();
    _session = session;

    final buffer = StringBuffer();
    _eventSub = session.events.listen(
      (event) {
        switch (event) {
          case TextDelta(:final text):
            buffer.write(text);
            state = state.copyWith(streamingText: buffer.toString());
          case SessionStarted(:final sessionId):
            unawaited(
              _store.setRemoteSessionId(
                connectionId,
                state.agentKind,
                activeId!,
                sessionId,
              ),
            );
          case RunCompleted():
            unawaited(_finishRun(connectionId, activeId!, buffer.toString()));
          case RunFailed(:final message):
            unawaited(
              _finishRun(connectionId, activeId!, buffer.toString(),
                  error: message),
            );
          case ThinkingDelta():
          case ToolCallStarted():
          case ApprovalRequested():
          case UsageUpdated():
            // Surfaced in a later iteration; the run continues.
            break;
        }
      },
    );

    try {
      if (session.sessionId == null) {
        await session.start(prompt);
      } else {
        await session.send(prompt);
      }
    } on Object catch (e) {
      await _finishRun(connectionId, activeId, buffer.toString(),
          error: '$e');
    }
  }

  /// Cancels the in-flight run, keeping the partial response.
  ///
  /// Also finalizes the streaming state: `HeadlessAgentSession.cancel`
  /// suppresses the terminal event, so without this the UI would stay in
  /// the streaming state forever and the composer would dead-lock.
  Future<void> cancel() async {
    if (!state.isStreaming) return;
    await _session?.cancel();
    await _eventSub?.cancel();
    _eventSub = null;
    final connectionId = ref.read(remoteUiProvider).connectionId;
    final sessionId = state.activeSessionId;
    if (connectionId != null && sessionId != null) {
      await _finishRun(connectionId, sessionId, state.streamingText);
    } else {
      state = state.copyWith(isStreaming: false, streamingText: '');
    }
  }

  /// Clears the current error after the UI has shown it.
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Deletes the chat history for the current (connection, agent) pair.
  Future<void> clearHistory() async {
    await cancel();
    final connectionId = ref.read(remoteUiProvider).connectionId;
    if (connectionId == null) return;
    await _store.clear(connectionId, state.agentKind);
    state = state.copyWith(
      sessions: const [],
      activeSessionId: null,
      messages: const [],
      streamingText: '',
    );
  }

  Future<void> _finishRun(
    String connectionId,
    String sessionId,
    String assistantText, {
    String? error,
  }) async {
    if (!state.isStreaming) return;
    final trimmed = assistantText.trim();
    ChatMessageRecord? assistantMessage;
    if (trimmed.isNotEmpty) {
      assistantMessage = ChatMessageRecord(
        role: ChatRole.assistant,
        text: trimmed,
        timestamp: DateTime.now(),
      );
      await _store.addMessage(
        connectionId,
        state.agentKind,
        sessionId,
        assistantMessage,
      );
    }
    final sessions = await _store.load(connectionId, state.agentKind);
    // The user may have switched sessions while the run was in flight;
    // only append to the visible message list when the finished run still
    // belongs to the active session (the store write above already landed
    // under the correct session id).
    final stillActive = state.activeSessionId == sessionId;
    state = state.copyWith(
      messages: stillActive && assistantMessage != null
          ? [...state.messages, assistantMessage]
          : state.messages,
      sessions: sessions,
      streamingText: '',
      isStreaming: false,
      error: error,
    );
  }

  /// Connects (or reuses) the dedicated chat SSH connection.
  Future<SshClient?> _ensureChatClient(String connectionId) async {
    final existing = _chatClient;
    if (existing != null &&
        existing.isConnected &&
        _chatClientConnectionId == connectionId) {
      return existing;
    }

    if (existing != null) await existing.disconnect();
    _chatClient = null;
    _chatClientConnectionId = null;

    final connection =
        ref.read(connectionsProvider.notifier).getById(connectionId);
    if (connection == null) {
      state = state.copyWith(error: 'Unknown connection');
      return null;
    }

    final client = SshClient();
    try {
      final options = await ConnectionCredentials.resolve(
        connectionId: connection.id,
        authMethod: connection.authMethod,
        keyId: connection.keyId,
        tmuxPath: connection.tmuxPath,
      );
      await client.connect(
        host: connection.host,
        port: connection.port,
        username: connection.username,
        options: options,
        lightweight: true,
      );
      _chatClient = client;
      _chatClientConnectionId = connectionId;
      return client;
    } on Object catch (e) {
      await client.disconnect();
      state = state.copyWith(isStreaming: false, error: '$e');
      return null;
    }
  }

  /// Base directory for headless runs: the detected agent pane's
  /// directory when known, otherwise the remote home directory.
  ///
  /// In worktree mode a dedicated git worktree is created under
  /// `.muxpod-worktrees/` next to the repository root; returns null
  /// (remote default) when the base directory is not a git repository.
  Future<String?> _resolveWorkingDirectory(SshClient client) async {
    final base = ref.read(remoteUiProvider).agentPanePath;
    if (!state.worktreeMode) return base;

    final sessionSuffix = (state.activeSessionId ?? 'chat')
        .replaceAll(RegExp('[^a-zA-Z0-9-]'), '')
        .substring(0, 8);
    final script = base != null
        ? "cd '${base.replaceAll("'", r"'\''")}' && "
            'top=\$(git rev-parse --show-toplevel 2>/dev/null) && '
            'wt="\$top/.muxpod-worktrees/$sessionSuffix" && '
            '(git -C "\$top" worktree add --detach "\$wt" HEAD '
            '2>/dev/null || true) && '
            'test -d "\$wt" && printf %s "\$wt"'
        : '';
    if (script.isEmpty) return null;

    try {
      final result = await client.execWithExitCode(script);
      if (result.exitCode == 0 && result.stdout.trim().isNotEmpty) {
        return result.stdout.trim();
      }
    } on Object {
      // Fall through to the base directory.
    }
    return base;
  }
}

/// Provider for the Remote UI chat.
final remoteUiChatProvider =
    NotifierProvider<RemoteUiChatNotifier, RemoteUiChatState>(
  RemoteUiChatNotifier.new,
);
