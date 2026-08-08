/// Builds the remote shell command that runs an AI CLI agent in headless
/// (non-interactive, machine-readable) mode.
///
/// Flag references (verified 2026-08):
///
/// * Claude Code — https://code.claude.com/docs/en/cli-reference
///   `claude -p "<prompt>" --output-format stream-json --verbose`
///   (`--verbose` is required for `-p` + `stream-json`), `--model`,
///   `--effort low|medium|high|xhigh|max|ultracode`,
///   `--permission-mode default|acceptEdits|plan|auto|dontAsk|bypassPermissions`,
///   `--resume <session-id>`.
///
/// * Codex CLI — https://developers.openai.com/codex/noninteractive and
///   https://learn.chatgpt.com/docs/developer-commands?surface=cli
///   `codex exec --json "<prompt>"` (JSONL events on stdout),
///   `-m/--model`, `-s/--sandbox read-only|workspace-write|danger-full-access`,
///   `-c key=value` config overrides, `codex exec resume` with a session id
///   and follow-up prompt. Note: the `resume` subcommand rejects `-m`, `-s` and `-C`
///   (codex-cli 0.125, https://github.com/garrytan/gstack/issues/1258), so
///   resumed runs pass model/sandbox/effort via `-c` overrides instead.
///
/// * Factory Droid — https://docs.factory.ai/droid-exec/overview and
///   https://docs.factory.ai/docs/droid-cli/cli-reference
///   `droid exec -o stream-json "<prompt>"` (NDJSON event stream),
///   `-m/--model`, `-r/--reasoning-effort` (in `droid exec`, `-r` means
///   reasoning-effort, NOT resume), `--auto low|medium|high`,
///   `--use-spec`, `--session-id <id>` to continue a session.
library;

import '../agent_types.dart';

/// Builds the full shell command for [kind], running [prompt] headlessly.
///
/// The prompt is single-quote shell-escaped. When [workingDirectory] is
/// provided the command is prefixed with `cd <dir> &&` so the agent starts
/// in the pane's directory (uniform across agents; Codex `exec resume` has
/// no working-directory flag, so a shell `cd` is the only portable option).
///
/// [resumeSessionId] continues a previous agent session; pass null for a
/// fresh conversation. [permission] == [UnifiedPermission.custom] (or null)
/// omits all permission flags so the agent's own config file applies.
String buildHeadlessCommand({
  required AgentKind kind,
  required String prompt,
  String? model,
  UnifiedIntelligence? intelligence,
  UnifiedPermission? permission,
  bool planMode = false,
  String? resumeSessionId,
  String? workingDirectory,
}) {
  final command = switch (kind) {
    AgentKind.claudeCode => _buildClaudeCommand(
        prompt,
        model: model,
        intelligence: intelligence,
        permission: permission,
        planMode: planMode,
        resumeSessionId: resumeSessionId,
      ),
    AgentKind.codex => _buildCodexCommand(
        prompt,
        model: model,
        intelligence: intelligence,
        permission: permission,
        resumeSessionId: resumeSessionId,
      ),
    AgentKind.droid => _buildDroidCommand(
        prompt,
        model: model,
        intelligence: intelligence,
        permission: permission,
        planMode: planMode,
        resumeSessionId: resumeSessionId,
      ),
  };

  final dir = workingDirectory;
  if (dir != null && dir.isNotEmpty) {
    return 'cd ${_shSingleQuote(dir)} && $command';
  }
  return command;
}

/// Shell-escapes [value] by wrapping it in single quotes.
///
/// Mirrors `SshClient._shSingleQuote`; duplicated here (2nd occurrence, per
/// the DRY rule of three) so this builder stays a pure string function with
/// no dependency on the SSH layer.
String _shSingleQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

String _buildClaudeCommand(
  String prompt, {
  String? model,
  UnifiedIntelligence? intelligence,
  UnifiedPermission? permission,
  required bool planMode,
  String? resumeSessionId,
}) {
  final args = <String>[
    'claude',
    '-p',
    _shSingleQuote(prompt),
    '--output-format',
    'stream-json',
    // stream-json with -p requires --verbose (CLI reference, see above).
    '--verbose',
  ];
  if (model != null && model.isNotEmpty) {
    args.addAll(['--model', _shSingleQuote(model)]);
  }
  final effort = _claudeEffort(intelligence);
  if (effort != null) {
    args.addAll(['--effort', effort]);
  }
  // Plan mode is expressed through the permission mode and wins over the
  // autonomy mapping when both are set.
  final mode = planMode ? 'plan' : _claudePermissionMode(permission);
  if (mode != null) {
    args.addAll(['--permission-mode', mode]);
  }
  if (resumeSessionId != null && resumeSessionId.isNotEmpty) {
    args.addAll(['--resume', _shSingleQuote(resumeSessionId)]);
  }
  return args.join(' ');
}

/// Maps unified reasoning levels to Claude `--effort` values.
/// https://code.claude.com/docs/en/cli-reference (`--effort`).
String? _claudeEffort(UnifiedIntelligence? level) => switch (level) {
      UnifiedIntelligence.low => 'low',
      UnifiedIntelligence.medium => 'medium',
      UnifiedIntelligence.high => 'high',
      UnifiedIntelligence.extraHigh => 'xhigh',
      UnifiedIntelligence.max => 'max',
      UnifiedIntelligence.ultra => 'ultracode',
      null => null,
    };

/// Maps unified autonomy to Claude `--permission-mode` values.
/// https://code.claude.com/docs/en/permission-modes
///
/// [UnifiedPermission.readOnly] maps to `default`: edits/commands require
/// approval, which headless runs cannot grant, so the run stays read-only
/// in practice. [UnifiedPermission.custom] (and null) defers to the user's
/// settings files.
String? _claudePermissionMode(UnifiedPermission? permission) =>
    switch (permission) {
      UnifiedPermission.readOnly => 'default',
      UnifiedPermission.defaultPermissions => 'acceptEdits',
      UnifiedPermission.autoReview => 'auto',
      UnifiedPermission.fullAccess => 'bypassPermissions',
      UnifiedPermission.custom => null,
      null => null,
    };

String _buildCodexCommand(
  String prompt, {
  String? model,
  UnifiedIntelligence? intelligence,
  UnifiedPermission? permission,
  String? resumeSessionId,
}) {
  // Codex has no headless plan-mode flag (`/plan` is TUI-only); planMode is
  // silently unsupported for codex exec.
  if (resumeSessionId != null && resumeSessionId.isNotEmpty) {
    // `codex exec resume` accepts only -c/--config, --enable/--disable,
    // --last, --all and the inherited --json (codex-cli 0.125). Model,
    // sandbox and effort therefore go through -c config overrides.
    final args = <String>[
      'codex',
      'exec',
      'resume',
      _shSingleQuote(resumeSessionId),
      '--json',
    ];
    if (model != null && model.isNotEmpty) {
      args.addAll(['-c', _shSingleQuote('model="$model"')]);
    }
    final sandbox = _codexSandbox(permission);
    if (sandbox != null) {
      args.addAll(['-c', _shSingleQuote('sandbox_mode="$sandbox"')]);
    }
    final effort = _codexEffort(intelligence);
    if (effort != null) {
      args.addAll(['-c', _shSingleQuote('model_reasoning_effort="$effort"')]);
    }
    args.add(_shSingleQuote(prompt));
    return args.join(' ');
  }

  final args = <String>['codex', 'exec', '--json'];
  if (model != null && model.isNotEmpty) {
    args.addAll(['-m', _shSingleQuote(model)]);
  }
  final sandbox = _codexSandbox(permission);
  if (sandbox != null) {
    args.addAll(['-s', sandbox]);
  }
  final effort = _codexEffort(intelligence);
  if (effort != null) {
    // No dedicated CLI flag; config key override is the documented path.
    args.addAll(['-c', _shSingleQuote('model_reasoning_effort="$effort"')]);
  }
  args.add(_shSingleQuote(prompt));
  return args.join(' ');
}

/// Maps unified autonomy to Codex `--sandbox` values.
/// https://developers.openai.com/codex/noninteractive
///
/// [UnifiedPermission.autoReview] degrades to `workspace-write`: codex exec
/// is non-interactive and has no auto-review classifier, so approval
/// prompts can never be answered. [UnifiedPermission.custom] (and null)
/// defers to `config.toml`.
String? _codexSandbox(UnifiedPermission? permission) => switch (permission) {
      UnifiedPermission.readOnly => 'read-only',
      UnifiedPermission.defaultPermissions => 'workspace-write',
      UnifiedPermission.autoReview => 'workspace-write',
      UnifiedPermission.fullAccess => 'danger-full-access',
      UnifiedPermission.custom => null,
      null => null,
    };

/// Maps unified reasoning levels to Codex `model_reasoning_effort` values.
///
/// Codex supports at most `xhigh`; [UnifiedIntelligence.max] and
/// [UnifiedIntelligence.ultra] clamp to it.
String? _codexEffort(UnifiedIntelligence? level) => switch (level) {
      UnifiedIntelligence.low => 'low',
      UnifiedIntelligence.medium => 'medium',
      UnifiedIntelligence.high => 'high',
      UnifiedIntelligence.extraHigh => 'xhigh',
      UnifiedIntelligence.max => 'xhigh',
      UnifiedIntelligence.ultra => 'xhigh',
      null => null,
    };

String _buildDroidCommand(
  String prompt, {
  String? model,
  UnifiedIntelligence? intelligence,
  UnifiedPermission? permission,
  required bool planMode,
  String? resumeSessionId,
}) {
  final args = <String>['droid', 'exec', '-o', 'stream-json'];
  if (model != null && model.isNotEmpty) {
    args.addAll(['-m', _shSingleQuote(model)]);
  }
  final effort = _droidEffort(intelligence);
  if (effort != null) {
    // In `droid exec`, `-r` is --reasoning-effort (NOT --resume).
    args.addAll(['-r', effort]);
  }
  final auto = _droidAutoLevel(permission);
  if (auto != null) {
    args.addAll(['--auto', auto]);
  }
  if (planMode) {
    // Droid's plan-before-execute mode.
    args.add('--use-spec');
  }
  if (resumeSessionId != null && resumeSessionId.isNotEmpty) {
    args.addAll(['--session-id', _shSingleQuote(resumeSessionId)]);
  }
  args.add(_shSingleQuote(prompt));
  return args.join(' ');
}

/// Maps unified autonomy to Droid `--auto` levels.
/// https://docs.factory.ai/droid-exec/overview#autonomy-levels
///
/// [UnifiedPermission.readOnly] needs no flag: droid exec is read-only
/// (spec-mode) by default. [UnifiedPermission.fullAccess] deliberately maps
/// to `--auto high` rather than `--skip-permissions-unsafe`, which Factory
/// reserves for disposable containers.
String? _droidAutoLevel(UnifiedPermission? permission) => switch (permission) {
      UnifiedPermission.readOnly => null,
      UnifiedPermission.defaultPermissions => 'low',
      UnifiedPermission.autoReview => 'medium',
      UnifiedPermission.fullAccess => 'high',
      UnifiedPermission.custom => null,
      null => null,
    };

/// Maps unified reasoning levels to Droid `-r/--reasoning-effort` values.
///
/// Valid levels are model-dependent (https://docs.factory.ai/docs/models);
/// `low|medium|high` pass through and anything higher clamps to `high`,
/// the documented safe ceiling.
String? _droidEffort(UnifiedIntelligence? level) => switch (level) {
      UnifiedIntelligence.low => 'low',
      UnifiedIntelligence.medium => 'medium',
      UnifiedIntelligence.high => 'high',
      UnifiedIntelligence.extraHigh => 'high',
      UnifiedIntelligence.max => 'high',
      UnifiedIntelligence.ultra => 'high',
      null => null,
    };
