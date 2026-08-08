import 'package:flutter_muxpod/services/agent/agent_adapter.dart';
import 'package:flutter_muxpod/services/agent/agent_types.dart';
import 'package:flutter_muxpod/services/agent/factory_droid_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ssh_client.dart';

void main() {
  final adapter = FactoryDroidAdapter();

  AgentContext contextFor(FakeSshClient ssh) {
    return AgentContext(ssh: ssh, paneId: '%9');
  }

  group('capabilities', () {
    test('offers reasoning, autonomy, and spec mode', () {
      expect(adapter.kind, AgentKind.droid);
      expect(adapter.processNames, ['droid']);
      // Droid reasoningEffort has no "ultra" rung.
      expect(
        adapter.capabilities.intelligenceLevels,
        [
          UnifiedIntelligence.low,
          UnifiedIntelligence.medium,
          UnifiedIntelligence.high,
          UnifiedIntelligence.extraHigh,
          UnifiedIntelligence.max,
        ],
      );
      expect(
        adapter.capabilities.permissionLevels,
        containsAll(UnifiedPermission.values),
      );
      expect(adapter.capabilities.supportsPlanMode, isTrue);
      expect(adapter.capabilities.requiresRestartToApply, isFalse);
      // Model IDs are user/org-specific: free-text entry.
      expect(adapter.capabilities.availableModels, isEmpty);
    });
  });

  group('pure mappings', () {
    test('reasoningEffortForIntelligence maps supported levels', () {
      expect(
        FactoryDroidAdapter.reasoningEffortForIntelligence(
          UnifiedIntelligence.low,
        ),
        'low',
      );
      expect(
        FactoryDroidAdapter.reasoningEffortForIntelligence(
          UnifiedIntelligence.medium,
        ),
        'medium',
      );
      expect(
        FactoryDroidAdapter.reasoningEffortForIntelligence(
          UnifiedIntelligence.high,
        ),
        'high',
      );
      expect(
        FactoryDroidAdapter.reasoningEffortForIntelligence(
          UnifiedIntelligence.extraHigh,
        ),
        'xhigh',
      );
      expect(
        FactoryDroidAdapter.reasoningEffortForIntelligence(
          UnifiedIntelligence.max,
        ),
        'max',
      );
    });

    test('reasoningEffortForIntelligence rejects ultra', () {
      expect(
        () => FactoryDroidAdapter.reasoningEffortForIntelligence(
          UnifiedIntelligence.ultra,
        ),
        throwsArgumentError,
      );
    });

    test('intelligenceForReasoningEffort maps back, off/none excluded', () {
      expect(
        FactoryDroidAdapter.intelligenceForReasoningEffort('max'),
        UnifiedIntelligence.max,
      );
      expect(
        FactoryDroidAdapter.intelligenceForReasoningEffort('xhigh'),
        UnifiedIntelligence.extraHigh,
      );
      expect(
        FactoryDroidAdapter.intelligenceForReasoningEffort('off'),
        isNull,
      );
      expect(
        FactoryDroidAdapter.intelligenceForReasoningEffort('dynamic'),
        isNull,
      );
    });

    test('autonomyLevelForPermission maps to Droid autonomy levels', () {
      expect(
        FactoryDroidAdapter.autonomyLevelForPermission(
          UnifiedPermission.readOnly,
        ),
        'off',
      );
      expect(
        FactoryDroidAdapter.autonomyLevelForPermission(
          UnifiedPermission.defaultPermissions,
        ),
        'low',
      );
      expect(
        FactoryDroidAdapter.autonomyLevelForPermission(
          UnifiedPermission.autoReview,
        ),
        'medium',
      );
      expect(
        FactoryDroidAdapter.autonomyLevelForPermission(
          UnifiedPermission.fullAccess,
        ),
        'high',
      );
      expect(
        FactoryDroidAdapter.autonomyLevelForPermission(
          UnifiedPermission.custom,
        ),
        isNull,
      );
    });

    test('permissionForAutonomyLevel maps back', () {
      expect(
        FactoryDroidAdapter.permissionForAutonomyLevel('off'),
        UnifiedPermission.readOnly,
      );
      expect(
        FactoryDroidAdapter.permissionForAutonomyLevel('low'),
        UnifiedPermission.defaultPermissions,
      );
      expect(
        FactoryDroidAdapter.permissionForAutonomyLevel('medium'),
        UnifiedPermission.autoReview,
      );
      expect(
        FactoryDroidAdapter.permissionForAutonomyLevel('high'),
        UnifiedPermission.fullAccess,
      );
      expect(FactoryDroidAdapter.permissionForAutonomyLevel('inherit'), isNull);
    });
  });

  group('applyModel', () {
    test('types /model into the pane and submits it', () async {
      final ssh = FakeSshClient();
      final message = await adapter.applyModel(
        contextFor(ssh),
        'claude-opus-4-7',
      );
      expect(ssh.sentKeyCommands, [
        'tmux send-keys -t %9 -l -- "/model claude-opus-4-7"',
        'tmux send-keys -t %9 Enter',
      ]);
      expect(message, contains('/model claude-opus-4-7'));
    });
  });

  group('applyIntelligence', () {
    test('writes reasoningEffort to settings.json', () async {
      final ssh = FakeSshClient(files: {
        FactoryDroidAdapter.settingsPath: '{\n  "theme": "dark"\n}\n',
      });
      final message = await adapter.applyIntelligence(
        contextFor(ssh),
        UnifiedIntelligence.high,
      );
      expect(
        ssh.files[FactoryDroidAdapter.settingsPath],
        '{\n  "theme": "dark",\n  "reasoningEffort": "high"\n}\n',
      );
      expect(message, contains('"high"'));
    });
  });

  group('applyPermission', () {
    test('writes sessionDefaultSettings.autonomyLevel', () async {
      final ssh = FakeSshClient();
      final message = await adapter.applyPermission(
        contextFor(ssh),
        UnifiedPermission.defaultPermissions,
      );
      expect(
        ssh.files[FactoryDroidAdapter.settingsPath],
        '{\n'
        '  "sessionDefaultSettings": {\n'
        '    "autonomyLevel": "low"\n'
        '  }\n'
        '}\n',
      );
      expect(message, contains('"low"'));
    });

    test('custom leaves the config file untouched', () async {
      final ssh = FakeSshClient(files: {
        FactoryDroidAdapter.settingsPath: '{}\n',
      });
      final message = await adapter.applyPermission(
        contextFor(ssh),
        UnifiedPermission.custom,
      );
      expect(ssh.files[FactoryDroidAdapter.settingsPath], '{}\n');
      // No read and no write command was issued.
      expect(ssh.execCommands, isEmpty);
      expect(message, contains('untouched'));
    });
  });

  group('setPlanMode', () {
    test('toggles sessionDefaultSettings.interactionMode', () async {
      final ssh = FakeSshClient();
      await adapter.setPlanMode(contextFor(ssh), true);
      expect(
        ssh.files[FactoryDroidAdapter.settingsPath],
        '{\n'
        '  "sessionDefaultSettings": {\n'
        '    "interactionMode": "spec"\n'
        '  }\n'
        '}\n',
      );
      await adapter.setPlanMode(contextFor(ssh), false);
      expect(
        ssh.files[FactoryDroidAdapter.settingsPath],
        '{\n'
        '  "sessionDefaultSettings": {\n'
        '    "interactionMode": "auto"\n'
        '  }\n'
        '}\n',
      );
    });
  });

  group('readConfig', () {
    test('parses model, effort, autonomy, and interaction mode', () async {
      final ssh = FakeSshClient(files: {
        FactoryDroidAdapter.settingsPath: '{\n'
            '  "model": "claude-opus-4-7",\n'
            '  "reasoningEffort": "xhigh",\n'
            '  "sessionDefaultSettings": {\n'
            '    "autonomyLevel": "medium",\n'
            '    "interactionMode": "spec"\n'
            '  }\n'
            '}\n',
      });
      final config = await adapter.readConfig(contextFor(ssh));
      expect(config.model, 'claude-opus-4-7');
      expect(config.intelligence, UnifiedIntelligence.extraHigh);
      expect(config.permission, UnifiedPermission.autoReview);
      expect(config.planModeActive, isTrue);
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
