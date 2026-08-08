import '../tmux/tmux_commands.dart';
import 'agent_adapter.dart';
import 'agent_config_service.dart';
import 'agent_types.dart';

/// Adapter for Factory Droid (`droid`).
///
/// Mechanisms (verified against the 2026 docs at docs.factory.ai,
/// droid-cli/cli-reference and droid-cli/settings):
///
/// - Model: `/model` switches the model mid-session (it applies between
///   turns). The persisted form is the `model` key in
///   `~/.factory/settings.json`.
/// - Reasoning effort: the `reasoningEffort` settings key. Valid values
///   are model-dependent: `none`, `dynamic`, `off`, `minimal`, `low`,
///   `medium`, `high`, `xhigh`, `max`. The unified low/medium/high/
///   extraHigh/max levels map onto low/medium/high/xhigh/max; `ultra`
///   has no Droid equivalent and is not offered. Settings apply to new
///   sessions (the running session can cycle effort with Tab, a
///   stateful toggle this adapter deliberately does not drive).
/// - Permissions: `sessionDefaultSettings.autonomyLevel`, one of
///   `off | low | medium | high`. `off` keeps manual approvals
///   (read-focused default), `low` pre-authorizes safe edits, `medium`
///   typical development work, `high` broad operations such as
///   deployment. Applies to new sessions (Ctrl+L cycles the running
///   session's level, again a stateful toggle).
/// - Plan mode: Droid's Spec Mode, controlled by
///   `sessionDefaultSettings.interactionMode` (`auto | spec`). Applies
///   to new sessions (Shift+Tab toggles the running session).
class FactoryDroidAdapter extends AgentAdapter {
  // Non-const: the pinned AgentAdapter base class has no const constructor.
  FactoryDroidAdapter();

  /// User settings file (docs.factory.ai/droid-cli/settings).
  static const String settingsPath = r'$HOME/.factory/settings.json';

  @override
  AgentKind get kind => AgentKind.droid;

  @override
  List<String> get processNames => const ['droid'];

  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        // Model IDs are user/org-specific (BYOK, Factory-Managed
        // Inference); free-text entry.
        intelligenceLevels: [
          UnifiedIntelligence.low,
          UnifiedIntelligence.medium,
          UnifiedIntelligence.high,
          UnifiedIntelligence.extraHigh,
          UnifiedIntelligence.max,
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

  /// Maps a unified intelligence level to a `reasoningEffort` value.
  /// Throws [ArgumentError] for [UnifiedIntelligence.ultra], which Droid
  /// does not support (it is excluded from [capabilities], so the UI
  /// never offers it).
  static String reasoningEffortForIntelligence(UnifiedIntelligence level) {
    return switch (level) {
      UnifiedIntelligence.low => 'low',
      UnifiedIntelligence.medium => 'medium',
      UnifiedIntelligence.high => 'high',
      UnifiedIntelligence.extraHigh => 'xhigh',
      UnifiedIntelligence.max => 'max',
      UnifiedIntelligence.ultra => throw ArgumentError(
          'Droid does not support reasoning effort "${level.name}"',
        ),
    };
  }

  /// Maps a persisted `reasoningEffort` value back to a unified level.
  /// `off`/`none`/`minimal`/`dynamic` have no unified rung and map to
  /// null.
  static UnifiedIntelligence? intelligenceForReasoningEffort(String effort) {
    return switch (effort) {
      'low' => UnifiedIntelligence.low,
      'medium' => UnifiedIntelligence.medium,
      'high' => UnifiedIntelligence.high,
      'xhigh' => UnifiedIntelligence.extraHigh,
      'max' => UnifiedIntelligence.max,
      _ => null,
    };
  }

  /// Maps a unified permission level to a
  /// `sessionDefaultSettings.autonomyLevel` value. Returns null for
  /// [UnifiedPermission.custom] ("leave the config file untouched").
  static String? autonomyLevelForPermission(UnifiedPermission level) {
    return switch (level) {
      // `off`: manual approvals; the default level is read-focused.
      UnifiedPermission.readOnly => 'off',
      // `low`: pre-authorizes safe edits and non-destructive commands.
      UnifiedPermission.defaultPermissions => 'low',
      // `medium`: pre-authorizes typical development work (install
      // dependencies, build/test, local commits).
      UnifiedPermission.autoReview => 'medium',
      // `high`: pre-authorizes broad operations such as git push and
      // deploy scripts.
      UnifiedPermission.fullAccess => 'high',
      UnifiedPermission.custom => null,
    };
  }

  /// Maps a persisted `sessionDefaultSettings.autonomyLevel` value back
  /// to a unified level. Unknown values map to null.
  static UnifiedPermission? permissionForAutonomyLevel(String level) {
    return switch (level) {
      'off' => UnifiedPermission.readOnly,
      'low' => UnifiedPermission.defaultPermissions,
      'medium' => UnifiedPermission.autoReview,
      'high' => UnifiedPermission.fullAccess,
      _ => null,
    };
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
    final effort = AgentConfigService.jsonGetDotted(content, 'reasoningEffort');
    final autonomy = AgentConfigService.jsonGetDotted(
      content,
      'sessionDefaultSettings.autonomyLevel',
    );
    final interactionMode = AgentConfigService.jsonGetDotted(
      content,
      'sessionDefaultSettings.interactionMode',
    );
    return AgentConfig(
      model: model is String ? model : null,
      intelligence:
          effort is String ? intelligenceForReasoningEffort(effort) : null,
      permission:
          autonomy is String ? permissionForAutonomyLevel(autonomy) : null,
      planModeActive: interactionMode == 'spec',
    );
  }

  @override
  Future<String> applyModel(AgentContext context, String model) async {
    await context.ssh.sendKeysCommand(
      TmuxCommands.sendKeys(context.paneId, '/model $model', literal: true),
    );
    await context.ssh.sendKeysCommand(TmuxCommands.sendEnter(context.paneId));
    return 'Sent /model $model to the pane (applies between turns)';
  }

  @override
  Future<String> applyIntelligence(
    AgentContext context,
    UnifiedIntelligence level,
  ) async {
    final effort = reasoningEffortForIntelligence(level);
    await _writeSettingsKey(context, 'reasoningEffort', effort);
    return 'Reasoning effort "$effort" saved to $settingsPath (applies '
        'to new sessions)';
  }

  @override
  Future<String> applyPermission(
    AgentContext context,
    UnifiedPermission level,
  ) async {
    final autonomy = autonomyLevelForPermission(level);
    if (autonomy == null) {
      return 'Custom permissions: $settingsPath left untouched';
    }
    await _writeSettingsKey(
      context,
      'sessionDefaultSettings.autonomyLevel',
      autonomy,
    );
    return 'Autonomy level "$autonomy" saved to $settingsPath (applies '
        'to new sessions)';
  }

  @override
  Future<String> setPlanMode(AgentContext context, bool enabled) async {
    // Droid's Spec Mode is the plan-first interaction mode.
    final mode = enabled ? 'spec' : 'auto';
    await _writeSettingsKey(
      context,
      'sessionDefaultSettings.interactionMode',
      mode,
    );
    return 'Spec mode ${enabled ? 'enabled' : 'disabled'} '
        '(sessionDefaultSettings.interactionMode="$mode" in '
        '$settingsPath; applies to new sessions)';
  }

  /// Sets a dotted key in `~/.factory/settings.json`, preserving all
  /// other content.
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
