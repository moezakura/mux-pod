import '../tmux/tmux_commands.dart';
import 'agent_adapter.dart';
import 'agent_config_service.dart';
import 'agent_types.dart';

/// Adapter for OpenAI Codex CLI (`codex`).
///
/// Mechanisms (verified against the 2026 config reference at
/// developers.openai.com/codex/config-reference):
///
/// Codex is configured through `~/.codex/config.toml`, which is read at
/// process start, so every change requires restarting the agent in its
/// pane ([AgentCapabilities.requiresRestartToApply] is true):
///
/// - Model: top-level `model = "<id>"`.
/// - Reasoning effort: top-level `model_reasoning_effort`, one of
///   `minimal | low | medium | high | xhigh` (`xhigh` is model-dependent).
///   The unified scale has no `minimal` rung and Codex has no `max`/
///   `ultra`, so the offered levels are low/medium/high/extraHigh.
/// - Permissions: `sandbox_mode` (`read-only | workspace-write |
///   danger-full-access`) combined with `approval_policy` (`untrusted |
///   on-request | never`). Note: current docs mark `on-failure` as
///   deprecated in favor of `on-request` (plus
///   `approvals_reviewer = "auto_review"`); it is still accepted and is
///   kept here per the pinned mapping.
/// - Plan mode: Codex has a TUI plan mode (`/plan` or Shift+Tab, since
///   v0.93), but it is a session-local toggle with no config-file
///   equivalent and no deterministic on/off command, so this adapter
///   reports [AgentCapabilities.supportsPlanMode] as false rather than
///   risk toggling the wrong direction.
class CodexAdapter extends AgentAdapter {
  // Non-const: the pinned AgentAdapter base class has no const constructor.
  CodexAdapter();

  /// User-level config file.
  static const String configPath = r'$HOME/.codex/config.toml';

  @override
  AgentKind get kind => AgentKind.codex;

  @override
  List<String> get processNames => const ['codex'];

  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        // Model IDs vary by provider/config; free-text entry.
        intelligenceLevels: [
          UnifiedIntelligence.low,
          UnifiedIntelligence.medium,
          UnifiedIntelligence.high,
          UnifiedIntelligence.extraHigh,
        ],
        permissionLevels: [
          UnifiedPermission.readOnly,
          UnifiedPermission.defaultPermissions,
          UnifiedPermission.autoReview,
          UnifiedPermission.fullAccess,
          UnifiedPermission.custom,
        ],
        requiresRestartToApply: true,
      );

  // ===== Pure mappings (unit-tested directly) =====

  /// Maps a unified intelligence level to a `model_reasoning_effort`
  /// value. Throws [ArgumentError] for levels Codex does not support
  /// (they are excluded from [capabilities], so the UI never offers
  /// them).
  static String reasoningEffortForIntelligence(UnifiedIntelligence level) {
    return switch (level) {
      UnifiedIntelligence.low => 'low',
      UnifiedIntelligence.medium => 'medium',
      UnifiedIntelligence.high => 'high',
      UnifiedIntelligence.extraHigh => 'xhigh',
      _ => throw ArgumentError(
          'Codex does not support reasoning effort "${level.name}"',
        ),
    };
  }

  /// Maps a persisted `model_reasoning_effort` value back to a unified
  /// level. `minimal` has no unified rung and maps to null.
  static UnifiedIntelligence? intelligenceForReasoningEffort(String effort) {
    return switch (effort) {
      'low' => UnifiedIntelligence.low,
      'medium' => UnifiedIntelligence.medium,
      'high' => UnifiedIntelligence.high,
      'xhigh' => UnifiedIntelligence.extraHigh,
      _ => null,
    };
  }

  /// Maps a unified permission level to the `sandbox_mode` /
  /// `approval_policy` pair to write. A null approval policy means the
  /// existing `approval_policy` line is left as-is. Returns null for
  /// [UnifiedPermission.custom] ("leave the config file untouched").
  static ({String sandboxMode, String? approvalPolicy})? configForPermission(
    UnifiedPermission level,
  ) {
    return switch (level) {
      UnifiedPermission.readOnly => (
          sandboxMode: 'read-only',
          approvalPolicy: null,
        ),
      UnifiedPermission.defaultPermissions => (
          sandboxMode: 'workspace-write',
          approvalPolicy: 'on-request',
        ),
      UnifiedPermission.autoReview => (
          sandboxMode: 'workspace-write',
          approvalPolicy: 'on-failure',
        ),
      UnifiedPermission.fullAccess => (
          sandboxMode: 'danger-full-access',
          approvalPolicy: 'never',
        ),
      UnifiedPermission.custom => null,
    };
  }

  /// Maps a persisted `sandbox_mode` / `approval_policy` pair back to a
  /// unified level. Combinations this adapter would never write map to
  /// [UnifiedPermission.custom]; a missing `sandbox_mode` maps to null
  /// (the effective value cannot be determined from the file).
  static UnifiedPermission? permissionForConfig(
    String? sandboxMode,
    String? approvalPolicy,
  ) {
    if (sandboxMode == null) return null;
    return switch ((sandboxMode, approvalPolicy)) {
      ('read-only', _) => UnifiedPermission.readOnly,
      ('workspace-write', 'on-request') =>
        UnifiedPermission.defaultPermissions,
      ('workspace-write', 'on-failure') => UnifiedPermission.autoReview,
      ('danger-full-access', 'never') => UnifiedPermission.fullAccess,
      _ => UnifiedPermission.custom,
    };
  }

  /// Builds the shell command typed into the pane to relaunch Codex in
  /// its original working directory (falling back to `$HOME`).
  static String buildRelaunchCommand(String? workingDirectory) {
    if (workingDirectory == null || workingDirectory.trim().isEmpty) {
      // `$HOME` must reach the pane shell unescaped so it expands there.
      return r'cd -- "$HOME" && codex';
    }
    return 'cd -- "${_escapeDoubleQuoted(workingDirectory)}" && codex';
  }

  /// Escapes a string for use inside double quotes in a shell command
  /// typed into the pane.
  static String _escapeDoubleQuoted(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll(r'$', r'\$')
        .replaceAll('`', r'\`');
  }

  // ===== AgentAdapter implementation =====

  @override
  Future<AgentConfig> readConfig(AgentContext context) async {
    final content = await AgentConfigService.readRemoteFile(
      context.ssh,
      configPath,
    );
    if (content == null) return const AgentConfig();
    final model = AgentConfigService.tomlGetString(content, 'model');
    final effort =
        AgentConfigService.tomlGetString(content, 'model_reasoning_effort');
    final sandboxMode = AgentConfigService.tomlGetString(content, 'sandbox_mode');
    final approvalPolicy =
        AgentConfigService.tomlGetString(content, 'approval_policy');
    return AgentConfig(
      model: model,
      intelligence:
          effort == null ? null : intelligenceForReasoningEffort(effort),
      permission: permissionForConfig(sandboxMode, approvalPolicy),
    );
  }

  @override
  Future<String> applyModel(AgentContext context, String model) async {
    await _updateConfig(
      context,
      (content) => AgentConfigService.tomlSetString(content, 'model', model),
    );
    await _restartAgent(context);
    return 'Model set to "$model" in $configPath; Codex was restarted to '
        'apply it';
  }

  @override
  Future<String> applyIntelligence(
    AgentContext context,
    UnifiedIntelligence level,
  ) async {
    final effort = reasoningEffortForIntelligence(level);
    await _updateConfig(
      context,
      (content) => AgentConfigService.tomlSetString(
        content,
        'model_reasoning_effort',
        effort,
      ),
    );
    await _restartAgent(context);
    return 'Reasoning effort set to "$effort" in $configPath; Codex was '
        'restarted to apply it';
  }

  @override
  Future<String> applyPermission(
    AgentContext context,
    UnifiedPermission level,
  ) async {
    final config = configForPermission(level);
    if (config == null) {
      return 'Custom permissions: $configPath left untouched';
    }
    await _updateConfig(context, (content) {
      var updated = AgentConfigService.tomlSetString(
        content,
        'sandbox_mode',
        config.sandboxMode,
      );
      final approvalPolicy = config.approvalPolicy;
      if (approvalPolicy != null) {
        updated = AgentConfigService.tomlSetString(
          updated,
          'approval_policy',
          approvalPolicy,
        );
      }
      return updated;
    });
    await _restartAgent(context);
    return 'Permissions set to sandbox_mode="${config.sandboxMode}"'
        '${config.approvalPolicy != null ? ', approval_policy="${config.approvalPolicy}"' : ''} '
        'in $configPath; Codex was restarted to apply them';
  }

  @override
  Future<String> setPlanMode(AgentContext context, bool enabled) async {
    // Not reachable through the UI (supportsPlanMode is false). Codex
    // plan mode is a session-local TUI toggle (/plan or Shift+Tab) with
    // no deterministic external control.
    return 'Codex plan mode can only be toggled in its TUI (/plan or '
        'Shift+Tab); no change was made';
  }

  /// Reads `~/.codex/config.toml`, applies [transform], and writes it
  /// back atomically (keeping a one-time `.muxpod-bak` backup).
  Future<void> _updateConfig(
    AgentContext context,
    String Function(String content) transform,
  ) async {
    final current =
        await AgentConfigService.readRemoteFile(context.ssh, configPath) ?? '';
    await AgentConfigService.writeRemoteFileAtomic(
      context.ssh,
      configPath,
      transform(current),
    );
  }

  /// Restarts the Codex process in its pane so config changes apply.
  ///
  /// Codex exits its TUI on a double Ctrl+C; the relaunch command is then
  /// typed into the pane's shell. A fixed delay here races slow TUIs (the
  /// relaunch line would be typed into the still-running agent), so the
  /// pane's `pane_current_command` is polled until Codex actually exits.
  Future<void> _restartAgent(AgentContext context) async {
    await context.ssh.sendKeysCommand(
      TmuxCommands.sendInterrupt(context.paneId),
    );
    await context.ssh.sendKeysCommand(
      TmuxCommands.sendInterrupt(context.paneId),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      String? current;
      try {
        current = await context.ssh.execPersistent(
          TmuxCommands.getPaneCurrentCommand(context.paneId),
        );
      } on Object {
        break; // Cannot verify; proceed rather than strand the user.
      }
      if (!matchesCommand(current)) break;
    }

    await context.ssh.sendKeysCommand(
      TmuxCommands.sendKeys(
        context.paneId,
        buildRelaunchCommand(context.paneWorkingDirectory),
        literal: true,
      ),
    );
    await context.ssh.sendKeysCommand(TmuxCommands.sendEnter(context.paneId));
  }
}
