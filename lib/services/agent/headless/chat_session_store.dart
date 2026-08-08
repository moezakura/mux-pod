/// Persists Remote UI chat history per (SSH connection, agent kind) in
/// SharedPreferences as JSON.
///
/// Layout: one SharedPreferences string key per pair,
/// `remote_ui_chat_sessions_<connectionId>_<agentKind>`, holding a JSON
/// list of session objects:
/// ```json
/// [{
///   "id": "…",
///   "agentKind": "claudeCode",
///   "title": "…",
///   "createdAt": "2026-08-08T01:23:45.000",
///   "messages": [{"role": "user", "text": "…", "timestamp": "…"}]
/// }]
/// ```
/// At most [ChatSessionStore.maxSessions] sessions are kept per key; the
/// oldest are dropped first. Sessions are stored newest-first.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../agent_types.dart';

/// Who authored a stored chat message.
enum ChatRole {
  user('user'),
  assistant('assistant');

  const ChatRole(this.wireName);

  /// Serialized form used in the JSON payload.
  final String wireName;

  /// Parses [wireName]; unknown values default to [ChatRole.assistant]
  /// so old payloads never crash the load path.
  static ChatRole parse(String? wireName) => switch (wireName) {
        'user' => ChatRole.user,
        _ => ChatRole.assistant,
      };
}

/// One stored chat message.
class ChatMessageRecord {
  /// Author of the message.
  final ChatRole role;

  /// Message text.
  final String text;

  /// When the message was recorded.
  final DateTime timestamp;

  const ChatMessageRecord({
    required this.role,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'role': role.wireName,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Strictly parses one message entry; returns null on malformed input.
  static ChatMessageRecord? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final text = json['text'];
    final timestampRaw = json['timestamp'];
    if (text is! String || timestampRaw is! String) return null;
    final timestamp = DateTime.tryParse(timestampRaw);
    if (timestamp == null) return null;
    final roleRaw = json['role'];
    return ChatMessageRecord(
      role: ChatRole.parse(roleRaw is String ? roleRaw : null),
      text: text,
      timestamp: timestamp,
    );
  }
}

/// One stored chat session with its message history.
class ChatSessionRecord {
  /// Unique session id (UUID v4).
  final String id;

  /// Which agent this conversation ran on.
  final AgentKind agentKind;

  /// Title shown in the session list. Empty until the first user message,
  /// from which [ChatSessionStore.addMessage] derives it.
  final String title;

  /// When the session was created.
  final DateTime createdAt;

  /// Messages in chronological order.
  final List<ChatMessageRecord> messages;

  /// The agent-side session id captured from its output, used to resume
  /// the conversation after an app restart. Null until the agent
  /// announces it (or forever, when the agent reports none).
  final String? remoteSessionId;

  const ChatSessionRecord({
    required this.id,
    required this.agentKind,
    required this.title,
    required this.createdAt,
    required this.messages,
    this.remoteSessionId,
  });

  ChatSessionRecord copyWith({
    String? title,
    List<ChatMessageRecord>? messages,
    String? remoteSessionId,
  }) {
    return ChatSessionRecord(
      id: id,
      agentKind: agentKind,
      title: title ?? this.title,
      createdAt: createdAt,
      messages: messages ?? this.messages,
      remoteSessionId: remoteSessionId ?? this.remoteSessionId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'agentKind': agentKind.name,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        if (remoteSessionId != null) 'remoteSessionId': remoteSessionId,
      };

  /// Strictly parses one session entry; returns null on malformed input.
  static ChatSessionRecord? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final agentKindRaw = json['agentKind'];
    final createdAtRaw = json['createdAt'];
    if (id is! String || agentKindRaw is! String || createdAtRaw is! String) {
      return null;
    }
    final agentKind = AgentKind.values.asNameMap()[agentKindRaw];
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (agentKind == null || createdAt == null) return null;
    final title = json['title'];
    final messagesRaw = json['messages'];
    final messages = <ChatMessageRecord>[
      if (messagesRaw is List)
        for (final m in messagesRaw)
          if (ChatMessageRecord.fromJson(m) case final message?) message,
    ];
    final remoteSessionId = json['remoteSessionId'];
    return ChatSessionRecord(
      id: id,
      agentKind: agentKind,
      title: title is String ? title : '',
      createdAt: createdAt,
      messages: messages,
      remoteSessionId:
          remoteSessionId is String ? remoteSessionId : null,
    );
  }
}

/// SharedPreferences-backed store for Remote UI chat histories.
class ChatSessionStore {
  /// Maximum sessions kept per (connection, agent) pair.
  static const int maxSessions = 50;

  /// SharedPreferences key prefix, per the repo's `remote_ui_` convention.
  static const String _keyPrefix = 'remote_ui_chat_sessions_';

  /// Length of a derived session title.
  static const int _titleMaxLength = 40;

  static const _uuid = Uuid();

  String _key(String connectionId, AgentKind kind) =>
      '$_keyPrefix${connectionId}_${kind.name}';

  /// Loads all sessions for the pair, newest first. Returns an empty list
  /// when nothing is stored or the payload is corrupted.
  Future<List<ChatSessionRecord>> load(
    String connectionId,
    AgentKind kind,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(connectionId, kind));
    if (raw == null || raw.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (ChatSessionRecord.fromJson(entry) case final session?) session,
    ];
  }

  /// Overwrites the stored session list for the pair, keeping at most
  /// [maxSessions] entries (oldest dropped).
  Future<void> save(
    String connectionId,
    AgentKind kind,
    List<ChatSessionRecord> sessions,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = sessions.length > maxSessions
        ? sessions.sublist(0, maxSessions)
        : sessions;
    await prefs.setString(
      _key(connectionId, kind),
      jsonEncode(trimmed.map((s) => s.toJson()).toList()),
    );
  }

  /// Creates an empty session, prepends it (trimming to [maxSessions]) and
  /// returns it. [title] may be empty; it is then derived from the first
  /// user message by [addMessage].
  Future<ChatSessionRecord> createSession(
    String connectionId,
    AgentKind kind, {
    String title = '',
  }) async {
    final session = ChatSessionRecord(
      id: _uuid.v4(),
      agentKind: kind,
      title: title,
      createdAt: DateTime.now(),
      messages: const [],
    );
    final sessions = await load(connectionId, kind);
    await save(connectionId, kind, [session, ...sessions]);
    return session;
  }

  /// Appends [message] to the session [sessionId]. Unknown session ids are
  /// ignored. Derives the session title from the first user message when
  /// no title is set yet.
  Future<void> addMessage(
    String connectionId,
    AgentKind kind,
    String sessionId,
    ChatMessageRecord message,
  ) async {
    final sessions = await load(connectionId, kind);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;

    final session = sessions[index];
    var title = session.title;
    if (title.isEmpty && message.role == ChatRole.user) {
      final firstLine = message.text.trim().split('\n').first;
      title = firstLine.length <= _titleMaxLength
          ? firstLine
          : '${firstLine.substring(0, _titleMaxLength)}…';
    }
    sessions[index] = session.copyWith(
      title: title,
      messages: [...session.messages, message],
    );
    await save(connectionId, kind, sessions);
  }

  /// Records the agent-side session id for [sessionId] so the
  /// conversation can be resumed in a later app session. Unknown session
  /// ids are ignored.
  Future<void> setRemoteSessionId(
    String connectionId,
    AgentKind kind,
    String sessionId,
    String remoteSessionId,
  ) async {
    final sessions = await load(connectionId, kind);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;
    sessions[index] = sessions[index].copyWith(
      remoteSessionId: remoteSessionId,
    );
    await save(connectionId, kind, sessions);
  }

  /// Deletes all sessions for the pair.
  Future<void> clear(String connectionId, AgentKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(connectionId, kind));
  }
}
