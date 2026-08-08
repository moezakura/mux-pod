import 'agent_adapter.dart';
import 'claude_code_adapter.dart';
import 'codex_adapter.dart';
import 'factory_droid_adapter.dart';

/// Registry of all known agent adapters.
///
/// Used by the Remote UI to detect which agent (if any) runs in a tmux
/// pane from the pane's `pane_current_command` value.
class AgentRegistry {
  AgentRegistry._();

  /// All supported adapters, in detection priority order.
  ///
  /// Not const: the pinned [AgentAdapter] base class has no const
  /// constructor, so adapter instances cannot be compile-time constants.
  static final List<AgentAdapter> adapters = [
    ClaudeCodeAdapter(),
    CodexAdapter(),
    FactoryDroidAdapter(),
  ];

  /// Returns the adapter whose [AgentAdapter.processNames] match
  /// [paneCurrentCommand] (case-insensitive, basename-aware), or null
  /// when the pane runs no known agent.
  static AgentAdapter? detect(String? paneCurrentCommand) {
    for (final adapter in adapters) {
      if (adapter.matchesCommand(paneCurrentCommand)) return adapter;
    }
    return null;
  }
}
