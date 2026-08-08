/// Structured chat events parsed from the streaming output of headless
/// AI CLI agents (Claude Code, Codex CLI, Factory Droid).
///
/// The headless runners emit newline-delimited JSON (NDJSON) on stdout.
/// Each agent's dialect is translated into this unified, sealed hierarchy
/// by `chat_event_parser.dart`, so the UI layer never touches raw JSON.
library;

/// Base type for all parsed chat events.
sealed class ChatEvent {
  const ChatEvent();
}

/// A chunk of assistant reply text.
///
/// Emitted by all three agents. Without partial-message streaming this is
/// one event per completed assistant message rather than per token.
final class TextDelta extends ChatEvent {
  /// The text fragment.
  final String text;

  const TextDelta(this.text);
}

/// A chunk of agent reasoning ("thinking") text.
///
/// Emitted by Claude Code (`thinking` content blocks) and Codex CLI
/// (`reasoning` items). Factory Droid's stream-json reasoning shape is not
/// publicly documented; it is mapped best-effort when recognized.
final class ThinkingDelta extends ChatEvent {
  /// The reasoning text fragment.
  final String text;

  const ThinkingDelta(this.text);
}

/// The agent started invoking a tool.
///
/// For Claude Code this carries the tool name (e.g. `Bash`, `Edit`).
/// For Codex CLI it carries the item type (e.g. `command_execution`,
/// `file_change`, `mcp_tool_call`, `web_search`).
final class ToolCallStarted extends ChatEvent {
  /// Tool name (Claude) or item type (Codex).
  final String name;

  const ToolCallStarted(this.name);
}

/// The agent asks the user to approve a privileged action.
///
/// Reserved for future use: none of the three headless modes currently
/// emits interactive approval requests. Claude Code headless auto-denies
/// tools that need approval unless `--permission-prompt-tool` is set,
/// Codex `exec` runs with pre-set sandbox/approval flags, and `droid exec`
/// fails fast on permission violations instead of asking.
final class ApprovalRequested extends ChatEvent {
  /// Identifier used to correlate the approval response.
  final String id;

  /// Human-readable description of the action awaiting approval.
  final String description;

  const ApprovalRequested({required this.id, required this.description});
}

/// The agent reported its session id.
///
/// Emitted once per run when the agent announces the session (Claude
/// `system/init`, Codex `thread.started`, Droid `result.session_id`).
/// The id is required to resume the conversation with a follow-up prompt.
final class SessionStarted extends ChatEvent {
  /// Agent-specific session/thread id.
  final String sessionId;

  const SessionStarted(this.sessionId);
}

/// Token usage and/or cost update for the run.
///
/// Fields are null when the agent does not report them. Claude Code
/// reports all three on its `result` event; Codex reports token counts on
/// `turn.completed`; Factory Droid does not report usage in its documented
/// output.
final class UsageUpdated extends ChatEvent {
  /// Input (prompt) tokens consumed.
  final int? inputTokens;

  /// Output (completion) tokens produced.
  final int? outputTokens;

  /// Total run cost in USD, when reported.
  final double? costUsd;

  const UsageUpdated({this.inputTokens, this.outputTokens, this.costUsd});
}

/// The run finished successfully.
final class RunCompleted extends ChatEvent {
  const RunCompleted();
}

/// The run failed (agent error, non-zero exit, or SSH disconnect).
final class RunFailed extends ChatEvent {
  /// Human-readable failure description.
  final String message;

  const RunFailed(this.message);
}
