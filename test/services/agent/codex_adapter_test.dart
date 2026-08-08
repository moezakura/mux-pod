import 'package:flutter_muxpod/services/agent/agent_adapter.dart';
import 'package:flutter_muxpod/services/agent/agent_types.dart';
import 'package:flutter_muxpod/services/agent/codex_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ssh_client.dart';

void main() {
  final adapter = CodexAdapter();

  AgentContext contextFor(FakeSshClient ssh, {String? workingDirectory}) {
    return AgentContext(
      ssh: ssh,
      paneId: '%3',
      paneWorkingDirectory: workingDirectory,
    );
  }

  group('capabilities', () {
    test('is config-file based and requires a restart to apply', () {
      expect(adapter.kind, AgentKind.codex);
      expect(adapter.processNames, ['codex']);
      expect(adapter.capabilities.requiresRestartToApply, isTrue);
      // Codex has no max/ultra reasoning rungs.
      expect(
        adapter.capabilities.intelligenceLevels,
        [
          UnifiedIntelligence.low,
          UnifiedIntelligence.medium,
          UnifiedIntelligence.high,
          UnifiedIntelligence.extraHigh,
        ],
      );
      // TUI plan mode has no deterministic external control.
      expect(adapter.capabilities.supportsPlanMode, isFalse);
      // Model IDs vary by provider: free-text entry.
      expect(adapter.capabilities.availableModels, isEmpty);
    });
  });

  group('pure mappings', () {
    test('reasoningEffortForIntelligence maps supported levels', () {
      expect(
        CodexAdapter.reasoningEffortForIntelligence(UnifiedIntelligence.low),
        'low',
      );
      expect(
        CodexAdapter.reasoningEffortForIntelligence(
          UnifiedIntelligence.medium,
        ),
        'medium',
      );
      expect(
        CodexAdapter.reasoningEffortForIntelligence(UnifiedIntelligence.high),
        'high',
      );
      expect(
        CodexAdapter.reasoningEffortForIntelligence(
          UnifiedIntelligence.extraHigh,
        ),
        'xhigh',
      );
    });

    test('reasoningEffortForIntelligence rejects unsupported levels', () {
      expect(
        () => CodexAdapter.reasoningEffortForIntelligence(
          UnifiedIntelligence.max,
        ),
        throwsArgumentError,
      );
      expect(
        () => CodexAdapter.reasoningEffortForIntelligence(
          UnifiedIntelligence.ultra,
        ),
        throwsArgumentError,
      );
    });

    test('intelligenceForReasoningEffort maps back, minimal excluded', () {
      expect(
        CodexAdapter.intelligenceForReasoningEffort('xhigh'),
        UnifiedIntelligence.extraHigh,
      );
      expect(CodexAdapter.intelligenceForReasoningEffort('minimal'), isNull);
    });

    test('configForPermission maps to sandbox_mode/approval_policy pairs',
        () {
      expect(
        CodexAdapter.configForPermission(UnifiedPermission.readOnly),
        (sandboxMode: 'read-only', approvalPolicy: null),
      );
      expect(
        CodexAdapter.configForPermission(UnifiedPermission.defaultPermissions),
        (sandboxMode: 'workspace-write', approvalPolicy: 'on-request'),
      );
      expect(
        CodexAdapter.configForPermission(UnifiedPermission.autoReview),
        (sandboxMode: 'workspace-write', approvalPolicy: 'on-failure'),
      );
      expect(
        CodexAdapter.configForPermission(UnifiedPermission.fullAccess),
        (sandboxMode: 'danger-full-access', approvalPolicy: 'never'),
      );
      expect(
        CodexAdapter.configForPermission(UnifiedPermission.custom),
        isNull,
      );
    });

    test('permissionForConfig maps written combos back', () {
      expect(
        CodexAdapter.permissionForConfig('read-only', null),
        UnifiedPermission.readOnly,
      );
      expect(
        CodexAdapter.permissionForConfig('workspace-write', 'on-request'),
        UnifiedPermission.defaultPermissions,
      );
      expect(
        CodexAdapter.permissionForConfig('workspace-write', 'on-failure'),
        UnifiedPermission.autoReview,
      );
      expect(
        CodexAdapter.permissionForConfig('danger-full-access', 'never'),
        UnifiedPermission.fullAccess,
      );
      // Combinations this adapter never writes are custom.
      expect(
        CodexAdapter.permissionForConfig('workspace-write', 'never'),
        UnifiedPermission.custom,
      );
      // Not determinable from the file.
      expect(CodexAdapter.permissionForConfig(null, null), isNull);
    });

    test('buildRelaunchCommand uses the pane working directory', () {
      expect(
        CodexAdapter.buildRelaunchCommand('/home/user/proj'),
        'cd -- "/home/user/proj" && codex',
      );
    });

    test('buildRelaunchCommand falls back to \$HOME', () {
      expect(
        CodexAdapter.buildRelaunchCommand(null),
        r'cd -- "$HOME" && codex',
      );
      expect(
        CodexAdapter.buildRelaunchCommand('  '),
        r'cd -- "$HOME" && codex',
      );
    });

    test('buildRelaunchCommand escapes shell-special characters', () {
      expect(
        CodexAdapter.buildRelaunchCommand('/home/a"b\$`x`/c'),
        r'cd -- "/home/a\"b\$\`x\`/c" && codex',
      );
    });
  });

  group('applyModel', () {
    test('writes the model key, preserves other lines, and restarts',
        () async {
      final ssh = FakeSshClient(files: {
        CodexAdapter.configPath: '# my config\n'
            'model = "gpt-5"\n'
            'approval_policy = "on-request"\n',
      });
      final message = await adapter.applyModel(
        contextFor(ssh, workingDirectory: '/home/user/proj'),
        'gpt-5.5',
      );
      expect(ssh.files[CodexAdapter.configPath], '# my config\n'
          'model = "gpt-5.5"\n'
          'approval_policy = "on-request"\n');
      // Restart: double Ctrl+C, then relaunch in the pane's directory.
      expect(ssh.sentKeyCommands, [
        'tmux send-keys -t %3 C-c',
        'tmux send-keys -t %3 C-c',
        'tmux send-keys -t %3 -l -- "cd -- \\"/home/user/proj\\" && codex"',
        'tmux send-keys -t %3 Enter',
      ]);
      expect(message, contains('gpt-5.5'));
      expect(message, contains('restarted'));
    });
  });

  group('applyIntelligence', () {
    test('writes model_reasoning_effort and restarts with \$HOME fallback',
        () async {
      final ssh = FakeSshClient();
      await adapter.applyIntelligence(
        contextFor(ssh),
        UnifiedIntelligence.high,
      );
      expect(
        ssh.files[CodexAdapter.configPath],
        'model_reasoning_effort = "high"\n',
      );
      expect(ssh.sentKeyCommands.last, 'tmux send-keys -t %3 Enter');
      expect(
        ssh.sentKeyCommands[ssh.sentKeyCommands.length - 2],
        r'tmux send-keys -t %3 -l -- "cd -- \"\$HOME\" && codex"',
      );
    });

    test('rejects unsupported levels without touching the file', () async {
      final ssh = FakeSshClient();
      await expectLater(
        adapter.applyIntelligence(contextFor(ssh), UnifiedIntelligence.max),
        throwsArgumentError,
      );
      expect(ssh.files, isEmpty);
      expect(ssh.sentKeyCommands, isEmpty);
    });
  });

  group('applyPermission', () {
    test('readOnly writes only sandbox_mode', () async {
      final ssh = FakeSshClient();
      await adapter.applyPermission(contextFor(ssh), UnifiedPermission.readOnly);
      expect(
        ssh.files[CodexAdapter.configPath],
        'sandbox_mode = "read-only"\n',
      );
    });

    test('defaultPermissions writes sandbox_mode and approval_policy',
        () async {
      final ssh = FakeSshClient();
      await adapter.applyPermission(
        contextFor(ssh),
        UnifiedPermission.defaultPermissions,
      );
      expect(
        ssh.files[CodexAdapter.configPath],
        'sandbox_mode = "workspace-write"\napproval_policy = "on-request"\n',
      );
    });

    test('fullAccess writes danger-full-access and never', () async {
      final ssh = FakeSshClient();
      await adapter.applyPermission(
        contextFor(ssh),
        UnifiedPermission.fullAccess,
      );
      expect(
        ssh.files[CodexAdapter.configPath],
        'sandbox_mode = "danger-full-access"\napproval_policy = "never"\n',
      );
    });

    test('custom leaves the file untouched and does not restart', () async {
      final ssh = FakeSshClient(files: {CodexAdapter.configPath: ''});
      final message = await adapter.applyPermission(
        contextFor(ssh),
        UnifiedPermission.custom,
      );
      expect(ssh.files[CodexAdapter.configPath], '');
      expect(ssh.sentKeyCommands, isEmpty);
      expect(message, contains('untouched'));
    });
  });

  group('setPlanMode', () {
    test('explains that plan mode is a TUI-only toggle', () async {
      final ssh = FakeSshClient();
      final message = await adapter.setPlanMode(contextFor(ssh), true);
      expect(message, contains('/plan'));
      expect(ssh.files, isEmpty);
      expect(ssh.sentKeyCommands, isEmpty);
    });
  });

  group('readConfig', () {
    test('parses model, effort, and permission from config.toml', () async {
      final ssh = FakeSshClient(files: {
        CodexAdapter.configPath: 'model = "gpt-5.5"\n'
            'model_reasoning_effort = "xhigh"\n'
            'sandbox_mode = "workspace-write"\n'
            'approval_policy = "on-failure"\n',
      });
      final config = await adapter.readConfig(contextFor(ssh));
      expect(config.model, 'gpt-5.5');
      expect(config.intelligence, UnifiedIntelligence.extraHigh);
      expect(config.permission, UnifiedPermission.autoReview);
      expect(config.planModeActive, isFalse);
    });

    test('returns an empty config when the file is missing', () async {
      final ssh = FakeSshClient();
      final config = await adapter.readConfig(contextFor(ssh));
      expect(config.model, isNull);
      expect(config.intelligence, isNull);
      expect(config.permission, isNull);
    });
  });
}
