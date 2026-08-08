/// Unified, agent-agnostic model for AI CLI agent control.
///
/// These types describe the concepts shown in the Remote UI (model,
/// reasoning effort, autonomy). Each `AgentAdapter` translates them into
/// tool-specific mechanisms (slash commands, config files, process flags).
library;

/// Supported AI CLI agents.
enum AgentKind {
  claudeCode('Claude Code'),
  codex('Codex CLI'),
  droid('Factory Droid');

  const AgentKind(this.displayName);

  /// Human-readable name shown in the UI.
  final String displayName;
}

/// Unified reasoning-effort scale shown in the Remote UI.
///
/// Not every agent supports every level; the levels a given agent accepts
/// are listed in [AgentCapabilities.intelligenceLevels].
enum UnifiedIntelligence {
  low('Low'),
  medium('Medium'),
  high('High'),
  extraHigh('Extra High'),
  max('Max'),
  ultra('Ultra');

  const UnifiedIntelligence(this.label);

  /// Label shown in the intelligence bottom sheet.
  final String label;
}

/// Unified autonomy/permission levels shown in the Remote UI.
enum UnifiedPermission {
  readOnly('Read only', 'Requires approval to edit files or run commands'),
  defaultPermissions('Default permissions', 'Runs commands in a sandbox'),
  autoReview('Auto-review', 'Reviews elevated requests automatically'),
  fullAccess('Full access', 'Full computer access (elevated risk)'),
  custom('Custom', 'Uses the permissions defined in the config file');

  const UnifiedPermission(this.label, this.description);

  /// Label shown in the permissions bottom sheet.
  final String label;

  /// Subtitle shown under the label in the permissions bottom sheet.
  final String description;
}

/// Which capabilities an agent supports and which concrete options the UI
/// may offer for it.
///
/// Empty lists mean the feature is unsupported for that agent and the UI
/// must hide the corresponding control.
class AgentCapabilities {
  /// Selectable model ids/names. Empty means free-text model entry.
  final List<String> availableModels;

  /// Supported reasoning levels. Empty means the agent has no
  /// reasoning-effort control.
  final List<UnifiedIntelligence> intelligenceLevels;

  /// Supported permission levels. Empty means the agent has no
  /// autonomy control.
  final List<UnifiedPermission> permissionLevels;

  /// Whether the agent has a plan/spec mode that can be toggled.
  final bool supportsPlanMode;

  /// Whether applying configuration changes requires restarting the agent
  /// process in its pane (config-file based agents such as Codex).
  final bool requiresRestartToApply;

  const AgentCapabilities({
    this.availableModels = const [],
    this.intelligenceLevels = const [],
    this.permissionLevels = const [],
    this.supportsPlanMode = false,
    this.requiresRestartToApply = false,
  });
}

/// Snapshot of an agent's current effective configuration.
///
/// Fields are null when the value cannot be determined (e.g. the agent
/// does not expose it and it is absent from its config file).
class AgentConfig {
  final String? model;
  final UnifiedIntelligence? intelligence;
  final UnifiedPermission? permission;
  final bool planModeActive;

  const AgentConfig({
    this.model,
    this.intelligence,
    this.permission,
    this.planModeActive = false,
  });

  AgentConfig copyWith({
    String? model,
    UnifiedIntelligence? intelligence,
    UnifiedPermission? permission,
    bool? planModeActive,
  }) {
    return AgentConfig(
      model: model ?? this.model,
      intelligence: intelligence ?? this.intelligence,
      permission: permission ?? this.permission,
      planModeActive: planModeActive ?? this.planModeActive,
    );
  }
}
