import 'package:flutter_muxpod/services/agent/agent_adapter.dart';
import 'package:flutter_muxpod/services/agent/agent_types.dart';
import 'package:flutter_muxpod/services/agent/claude_code_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ssh_client.dart';

void main() {
  final adapter = ClaudeCodeAdapter();

  AgentContext contextFor(FakeSshClient ssh) {
    return AgentContext(ssh: ssh, paneId: '%7');
  }

  group('capabilities', () {
    test('offers model aliases, all effort levels, and plan mode', () {
      expect(adapter.kind, AgentKind.claudeCode);
      expect(adapter.processNames, ['claude']);
      expect(adapter.capabilities.availableModels, contains('opus'));
      expect(
        adapter.capabilities.intelligenceLevels,
        containsAll(UnifiedIntelligence.values),
      );
      expect(
        adapter.capabilities.permissionLevels,
        containsAll(UnifiedPermission.values),
      );
      expect(adapter.capabilities.supportsPlanMode, isTrue);
      expect(adapter.capabilities.requiresRestartToApply, isFalse);
    });
  });

  group('pure mappings', () {
    test('effortForIntelligence maps every unified level', () {
      expect(
        ClaudeCodeAdapter.effortForIntelligence(UnifiedIntelligence.low),
        'low',
      );
      expect(
        ClaudeCodeAdapter.effortForIntelligence(UnifiedIntelligence.medium),
        'medium',
      );
      expect(
        ClaudeCodeAdapter.effortForIntelligence(UnifiedIntelligence.high),
        'high',
      );
      expect(
        ClaudeCodeAdapter.effortForIntelligence(UnifiedIntelligence.extraHigh),
        'xhigh',
      );
      expect(
        ClaudeCodeAdapter.effortForIntelligence(UnifiedIntelligence.max),
        'max',
      );
      expect(
        ClaudeCodeAdapter.effortForIntelligence(UnifiedIntelligence.ultra),
        'ultracode',
      );
    });

    test('intelligenceForEffort maps persisted levels only', () {
      expect(
        ClaudeCodeAdapter.intelligenceForEffort('xhigh'),
        UnifiedIntelligence.extraHigh,
      );
      // Session-only levels are never persisted.
      expect(ClaudeCodeAdapter.intelligenceForEffort('max'), isNull);
      expect(ClaudeCodeAdapter.intelligenceForEffort('ultracode'), isNull);
    });

    test('modeForPermission maps to Claude permission modes', () {
      expect(
        ClaudeCodeAdapter.modeForPermission(UnifiedPermission.readOnly),
        'default',
      );
      expect(
        ClaudeCodeAdapter.modeForPermission(
          UnifiedPermission.defaultPermissions,
        ),
        'acceptEdits',
      );
      expect(
        ClaudeCodeAdapter.modeForPermission(UnifiedPermission.autoReview),
        'auto',
      );
      expect(
        ClaudeCodeAdapter.modeForPermission(UnifiedPermission.fullAccess),
        'bypassPermissions',
      );
      expect(
        ClaudeCodeAdapter.modeForPermission(UnifiedPermission.custom),
        isNull,
      );
    });

    test('permissionForMode maps modes back, plan/dontAsk excluded', () {
      expect(
        ClaudeCodeAdapter.permissionForMode('default'),
        UnifiedPermission.readOnly,
      );
      expect(
        ClaudeCodeAdapter.permissionForMode('manual'),
        UnifiedPermission.readOnly,
      );
      expect(
        ClaudeCodeAdapter.permissionForMode('acceptEdits'),
        UnifiedPermission.defaultPermissions,
      );
      expect(
        ClaudeCodeAdapter.permissionForMode('auto'),
        UnifiedPermission.autoReview,
      );
      expect(
        ClaudeCodeAdapter.permissionForMode('bypassPermissions'),
        UnifiedPermission.fullAccess,
      );
      // Reported via AgentConfig.planModeActive instead.
      expect(ClaudeCodeAdapter.permissionForMode('plan'), isNull);
      // No unified equivalent.
      expect(ClaudeCodeAdapter.permissionForMode('dontAsk'), isNull);
    });
  });

  group('applyModel', () {
    test('types /model into the pane and submits it', () async {
      final ssh = FakeSshClient();
      final message = await adapter.applyModel(contextFor(ssh), 'opus');
      expect(ssh.sentKeyCommands, [
        'tmux send-keys -t %7 -l -- "/model opus"',
        'tmux send-keys -t %7 Enter',
      ]);
      expect(message, contains('/model opus'));
    });
  });

  group('applyIntelligence', () {
    test('types /effort into the pane and submits it', () async {
      final ssh = FakeSshClient();
      final message = await adapter.applyIntelligence(
        contextFor(ssh),
        UnifiedIntelligence.extraHigh,
      );
      expect(ssh.sentKeyCommands, [
        'tmux send-keys -t %7 -l -- "/effort xhigh"',
        'tmux send-keys -t %7 Enter',
      ]);
      expect(message, contains('xhigh'));
    });
  });

  group('applyPermission', () {
    test('writes permissions.defaultMode to settings.json', () async {
      final ssh = FakeSshClient(files: {
        ClaudeCodeAdapter.settingsPath: '{\n  "model": "sonnet"\n}\n',
      });
      final message = await adapter.applyPermission(
        contextFor(ssh),
        UnifiedPermission.autoReview,
      );
      expect(
        ssh.files[ClaudeCodeAdapter.settingsPath],
        '{\n'
        '  "model": "sonnet",\n'
        '  "permissions": {\n'
        '    "defaultMode": "auto"\n'
        '  }\n'
        '}\n',
      );
      expect(message, contains('"auto"'));
    });

    test('custom leaves the config file untouched', () async {
      final ssh = FakeSshClient(files: {
        ClaudeCodeAdapter.settingsPath: '{}\n',
      });
      final message = await adapter.applyPermission(
        contextFor(ssh),
        UnifiedPermission.custom,
      );
      expect(ssh.files[ClaudeCodeAdapter.settingsPath], '{}\n');
      // No read and no write command was issued.
      expect(ssh.execCommands, isEmpty);
      expect(message, contains('untouched'));
    });
  });

  group('setPlanMode', () {
    test('enable writes defaultMode "plan", disable restores "default"',
        () async {
      final ssh = FakeSshClient();
      await adapter.setPlanMode(contextFor(ssh), true);
      expect(
        ssh.files[ClaudeCodeAdapter.settingsPath],
        '{\n  "permissions": {\n    "defaultMode": "plan"\n  }\n}\n',
      );
      await adapter.setPlanMode(contextFor(ssh), false);
      expect(
        ssh.files[ClaudeCodeAdapter.settingsPath],
        '{\n  "permissions": {\n    "defaultMode": "default"\n  }\n}\n',
      );
    });
  });

  group('readConfig', () {
    test('parses model, effortLevel, and defaultMode', () async {
      final ssh = FakeSshClient(files: {
        ClaudeCodeAdapter.settingsPath: '{\n'
            '  "model": "opus",\n'
            '  "effortLevel": "xhigh",\n'
            '  "permissions": {\n'
            '    "defaultMode": "acceptEdits"\n'
            '  }\n'
            '}\n',
      });
      final config = await adapter.readConfig(contextFor(ssh));
      expect(config.model, 'opus');
      expect(config.intelligence, UnifiedIntelligence.extraHigh);
      expect(config.permission, UnifiedPermission.defaultPermissions);
      expect(config.planModeActive, isFalse);
    });

    test('reports plan mode via planModeActive', () async {
      final ssh = FakeSshClient(files: {
        ClaudeCodeAdapter.settingsPath:
            '{"permissions": {"defaultMode": "plan"}}',
      });
      final config = await adapter.readConfig(contextFor(ssh));
      expect(config.planModeActive, isTrue);
      expect(config.permission, isNull);
    });

    test('returns an empty config when the file is missing', () async {
      final ssh = FakeSshClient();
      final config = await adapter.readConfig(contextFor(ssh));
      expect(config.model, isNull);
      expect(config.intelligence, isNull);
      expect(config.permission, isNull);
      expect(config.planModeActive, isFalse);
    });
  });
}
