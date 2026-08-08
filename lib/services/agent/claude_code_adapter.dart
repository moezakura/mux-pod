import '../tmux/tmux_commands.dart';
import 'agent_adapter.dart';
import 'agent_config_service.dart';
import 'agent_types.dart';

/// Adapter for Claude Code (`claude`).
///
/// Mechanisms (verified against the 2026 docs at code.claude.com/docs):
///
/// - Model: `/model <alias|name>` switches the running session
///   immediately and saves it as the default for new sessions
///   (docs/en/model-config, "Setting your model"). The persisted form is
///   the `model` key in `~/.claude/settings.json`, which is read once at
///   session start.
/// - Reasoning effort: `/effort <level>` sets the level directly on the
///   running session (docs/en/model-config, "Set the effort level").
///   Levels are `low`, `medium`, `high`, `xhigh`, `max` (model-dependent)
///   plus `ultracode`, a session-only Claude Code setting that pairs
///   `xhigh` with dynamic workflow orchestration. The persisted
///   `effortLevel` settings key accepts only `low`/`medium`/`high`/
///   `xhigh`; `max` and `ultracode` are session-only. The older
///   `MAX_THINKING_TOKENS` env var now applies only to fixed thinking
///   budgets on pre-4.7 models, so `/effort` is the correct control.
/// - Permissions: `permissions.defaultMode` in `~/.claude/settings.json`
///   (docs/en/permission-modes). Modes: `default` (reads only without
///   asking; prompts for edits/commands), `acceptEdits` (auto-approves
///   file edits and common filesystem commands), `plan`, `auto` (a
///   classifier reviews elevated requests automatically), `dontAsk`, and
///   `bypassPermissions`. Settings files are watched and reloaded live,
///   but `defaultMode` is the *starting* mode: the running session keeps
///   its current mode until the user cycles it with Shift+Tab.
/// - Plan mode: a first-class permission mode (`plan`), so it is applied
///   through the same `permissions.defaultMode` key.
class ClaudeCodeAdapter extends AgentAdapter {
  // Non-const: the pinned AgentAdapter base class has no const constructor.
  ClaudeCodeAdapter();

  /// User-scope settings file (docs/en/settings).
  static const String settingsPath = r'$HOME/.claude/settings.json';

  @override
  AgentKind get kind => AgentKind.claudeCode;

  @override
  List<String> get processNames => const ['claude'];

  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        // Common model aliases from docs/en/model-config. The `/model`
        // command also accepts full model IDs, so this list is a
        // convenience, not an exhaustive allowlist.
        availableModels: [
          'default',
          'sonnet',
          'opus',
          'haiku',
          'fable',
          'opusplan',
        ],
        // `/effort` low|medium|high|xhigh|max|ultracode.
        intelligenceLevels: [
          UnifiedIntelligence.low,
          UnifiedIntelligence.medium,
          UnifiedIntelligence.high,
          UnifiedIntelligence.extraHigh,
          UnifiedIntelligence.max,
          UnifiedIntelligence.ultra,
        ],
        permissionLevels: [
          UnifiedPermission.readOnly,
          UnifiedPermission.defaultPermissions,
          UnifiedPermission.autoReview,
          UnifiedPermission.fullAccess,
          UnifiedPermission.custom,
        ],
        supportsPlanMode: true,
      );

  // ===== Pure mappings (unit-tested directly) =====

  /// Maps a unified intelligence level to a `/effort` argument.
  static String effortForIntelligence(UnifiedIntelligence level) {
    return switch (level) {
      UnifiedIntelligence.low => 'low',
      UnifiedIntelligence.medium => 'medium',
      UnifiedIntelligence.high => 'high',
      UnifiedIntelligence.extraHigh => 'xhigh',
      UnifiedIntelligence.max => 'max',
      UnifiedIntelligence.ultra => 'ultracode',
    };
  }

  /// Maps a persisted `effortLevel` value back to a unified level.
  ///
  /// `max`/`ultracode` are session-only and never appear in settings, so
  /// they (and unknown values) map to null.
  static UnifiedIntelligence? intelligenceForEffort(String effort) {
    return switch (effort) {
      'low' => UnifiedIntelligence.low,
      'medium' => UnifiedIntelligence.medium,
      'high' => UnifiedIntelligence.high,
      'xhigh' => UnifiedIntelligence.extraHigh,
      _ => null,
    };
  }

  /// Maps a unified permission level to a Claude permission mode.
  ///
  /// Returns null for [UnifiedPermission.custom], which means "leave the
  /// config file untouched".
  static String? modeForPermission(UnifiedPermission level) {
    return switch (level) {
      // `default` (Manual): reads run freely, edits and commands prompt.
      UnifiedPermission.readOnly => 'default',
      // `acceptEdits`: file edits and common filesystem commands are
      // auto-approved inside the working directory.
      UnifiedPermission.defaultPermissions => 'acceptEdits',
      // `auto`: a classifier model reviews elevated requests
      // automatically instead of prompting the user.
      UnifiedPermission.autoReview => 'auto',
      UnifiedPermission.fullAccess => 'bypassPermissions',
      UnifiedPermission.custom => null,
    };
  }

  /// Maps a persisted `permissions.defaultMode` value back to a unified
  /// level. `plan` is reported via [AgentConfig.planModeActive] instead;
  /// `dontAsk` and unknown values have no unified equivalent.
  static UnifiedPermission? permissionForMode(String mode) {
    return switch (mode) {
      'default' || 'manual' => UnifiedPermission.readOnly,
      'acceptEdits' => UnifiedPermission.defaultPermissions,
      'auto' => UnifiedPermission.autoReview,
      'bypassPermissions' => UnifiedPermission.fullAccess,
      _ => null,
    };
  }

  /// Builds the slash command text typed into the pane.
  static String buildSlashCommand(String name, String argument) {
    return '/$name $argument';
  }

  // ===== AgentAdapter implementation =====

  @override
  Future<AgentConfig> readConfig(AgentContext context) async {
    final content = await AgentConfigService.readRemoteFile(
      context.ssh,
      settingsPath,
    );
    if (content == null) return const AgentConfig();
    final model = AgentConfigService.jsonGetDotted(content, 'model');
    final effort = AgentConfigService.jsonGetDotted(content, 'effortLevel');
    final mode = AgentConfigService.jsonGetDotted(
      content,
      'permissions.defaultMode',
    );
    return AgentConfig(
      model: model is String ? model : null,
      intelligence:
          effort is String ? intelligenceForEffort(effort) : null,
      permission: mode is String ? permissionForMode(mode) : null,
      planModeActive: mode == 'plan',
    );
  }

  @override
  Future<String> applyModel(AgentContext context, String model) async {
    await _sendSlashCommand(context, buildSlashCommand('model', model));
    return 'Sent /model $model to the pane (applies immediately and is '
        'saved as the default for new sessions)';
  }

  @override
  Future<String> applyIntelligence(
    AgentContext context,
    UnifiedIntelligence level,
  ) async {
    final effort = effortForIntelligence(level);
    await _sendSlashCommand(context, buildSlashCommand('effort', effort));
    return 'Sent /effort $effort to the pane';
  }

  @override
  Future<String> applyPermission(
    AgentContext context,
    UnifiedPermission level,
  ) async {
    final mode = modeForPermission(level);
    if (mode == null) {
      return 'Custom permissions: $settingsPath left untouched';
    }
    await _writeSettingsKey(context, 'permissions.defaultMode', mode);
    return 'Permission mode "$mode" saved to $settingsPath. New sessions '
        'start in this mode; press Shift+Tab in the pane to cycle the '
        'running session.';
  }

  @override
  Future<String> setPlanMode(AgentContext context, bool enabled) async {
    // Plan mode is a permission mode in Claude Code, so it is applied
    // through the same settings key. Disabling restores `default`.
    final mode = enabled ? 'plan' : 'default';
    await _writeSettingsKey(context, 'permissions.defaultMode', mode);
    return 'Plan mode ${enabled ? 'enabled' : 'disabled'} '
        '(permissions.defaultMode="$mode" in $settingsPath). Press '
        'Shift+Tab in the pane to toggle the running session.';
  }

  /// Types a slash command into the agent pane and submits it.
  ///
  /// The command text is sent with `send-keys -l` (literal) via
  /// [TmuxCommands.sendKeys], which shell-escapes it; Enter is sent
  /// separately so the TUI receives distinct keystrokes.
  Future<void> _sendSlashCommand(AgentContext context, String text) async {
    await context.ssh.sendKeysCommand(
      TmuxCommands.sendKeys(context.paneId, text, literal: true),
    );
    await context.ssh.sendKeysCommand(TmuxCommands.sendEnter(context.paneId));
  }

  /// Sets a dotted key in `~/.claude/settings.json`, preserving all other
  /// content.
  Future<void> _writeSettingsKey(
    AgentContext context,
    String dottedKey,
    Object? value,
  ) async {
    final current =
        await AgentConfigService.readRemoteFile(context.ssh, settingsPath) ??
            '';
    final updated = AgentConfigService.jsonSetDotted(current, dottedKey, value);
    await AgentConfigService.writeRemoteFileAtomic(
      context.ssh,
      settingsPath,
      updated,
    );
  }
}
