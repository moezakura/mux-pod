import '../ssh/ssh_client.dart';
import 'agent_types.dart';

/// Everything an adapter needs to talk to a running agent: a live SSH
/// connection plus the tmux pane the agent process runs in.
class AgentContext {
  /// Live SSH connection to the host running the agent.
  final SshClient ssh;

  /// tmux pane id (e.g. `%12`) where the agent process runs.
  final String paneId;

  /// Working directory of the pane, if known (`pane_current_path`).
  /// Used when the agent must be restarted in its original directory.
  final String? paneWorkingDirectory;

  const AgentContext({
    required this.ssh,
    required this.paneId,
    this.paneWorkingDirectory,
  });
}

/// Translates the unified Remote UI controls (model, reasoning effort,
/// autonomy) into the mechanisms of one specific AI CLI agent.
///
/// Implementations must be pure translators: they receive an [AgentContext]
/// and perform remote operations through it. They never hold UI state and
/// never create their own SSH connections.
abstract class AgentAdapter {
  /// Which agent this adapter controls.
  AgentKind get kind;

  /// Capabilities and selectable options for this agent.
  AgentCapabilities get capabilities;

  /// Process names matched (case-insensitively) against the tmux
  /// `pane_current_command` format value, e.g. `claude`, `codex`, `droid`.
  List<String> get processNames;

  /// Whether [paneCurrentCommand] looks like this agent's process.
  bool matchesCommand(String? paneCurrentCommand) {
    if (paneCurrentCommand == null) return false;
    final command = paneCurrentCommand.trim().toLowerCase();
    if (command.isEmpty) return false;
    return processNames.any(
      (name) => command == name || command.endsWith('/$name'),
    );
  }

  /// Reads the agent's current effective configuration.
  ///
  /// Implementations should prefer the agent's config files (reliable)
  /// and only fall back to parsing pane output when necessary.
  Future<AgentConfig> readConfig(AgentContext context);

  /// Switches the active model. Returns a short human-readable
  /// confirmation message for the UI.
  Future<String> applyModel(AgentContext context, String model);

  /// Switches the reasoning effort. Returns a confirmation message.
  Future<String> applyIntelligence(
    AgentContext context,
    UnifiedIntelligence level,
  );

  /// Switches the autonomy/permission level. Returns a confirmation
  /// message. When [AgentCapabilities.requiresRestartToApply] is true the
  /// adapter restarts the agent process in its pane.
  Future<String> applyPermission(
    AgentContext context,
    UnifiedPermission level,
  );

  /// Enables or disables plan/spec mode. Returns a confirmation message.
  Future<String> setPlanMode(AgentContext context, bool enabled);
}
