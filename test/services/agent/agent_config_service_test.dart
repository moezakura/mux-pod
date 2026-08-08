import 'package:flutter_muxpod/services/agent/agent_config_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ssh_client.dart';

void main() {
  group('AgentConfigService.tomlGetString', () {
    test('returns the unquoted value of a top-level key', () {
      const content = 'model = "gpt-5.5"\nmodel_reasoning_effort = "high"\n';
      expect(AgentConfigService.tomlGetString(content, 'model'), 'gpt-5.5');
      expect(
        AgentConfigService.tomlGetString(content, 'model_reasoning_effort'),
        'high',
      );
    });

    test('returns null when the key is absent', () {
      const content = 'model = "gpt-5.5"\n';
      expect(AgentConfigService.tomlGetString(content, 'sandbox_mode'), isNull);
    });

    test('ignores keys inside tables (top-level only)', () {
      const content = '[profiles.work]\nmodel = "gpt-5.5"\n';
      expect(AgentConfigService.tomlGetString(content, 'model'), isNull);
    });

    test('ignores commented-out keys', () {
      const content = '# model = "gpt-5.5"\n';
      expect(AgentConfigService.tomlGetString(content, 'model'), isNull);
    });

    test('strips trailing comments on bare values', () {
      const content = 'approval_policy = on-request # ask each time\n';
      expect(
        AgentConfigService.tomlGetString(content, 'approval_policy'),
        'on-request',
      );
    });

    test('handles single-quoted literal strings', () {
      const content = "model = 'gpt-5.5'\n";
      expect(AgentConfigService.tomlGetString(content, 'model'), 'gpt-5.5');
    });
  });

  group('AgentConfigService.tomlSetString', () {
    test('replaces an existing key and preserves unrelated lines', () {
      const content = '# Codex config\n'
          'model = "gpt-5"\n'
          'approval_policy = "on-request"\n'
          '\n'
          '[mcp_servers.fs]\n'
          'command = "npx"\n';
      final updated = AgentConfigService.tomlSetString(
        content,
        'model',
        'gpt-5.5',
      );
      expect(
        updated,
        '# Codex config\n'
        'model = "gpt-5.5"\n'
        'approval_policy = "on-request"\n'
        '\n'
        '[mcp_servers.fs]\n'
        'command = "npx"\n',
      );
    });

    test('appends the key when missing and no table exists', () {
      const content = 'model = "gpt-5"\n';
      final updated = AgentConfigService.tomlSetString(
        content,
        'sandbox_mode',
        'read-only',
      );
      expect(updated, 'model = "gpt-5"\nsandbox_mode = "read-only"\n');
    });

    test('inserts before the first table so the key stays top-level', () {
      const content = 'model = "gpt-5"\n'
          '\n'
          '[mcp_servers.fs]\n'
          'command = "npx"\n';
      final updated = AgentConfigService.tomlSetString(
        content,
        'sandbox_mode',
        'read-only',
      );
      expect(
        updated,
        'model = "gpt-5"\n'
        '\n'
        'sandbox_mode = "read-only"\n'
        '[mcp_servers.fs]\n'
        'command = "npx"\n',
      );
    });

    test('does not replace a key that only exists inside a table', () {
      const content = '[profiles.work]\nmodel = "gpt-5"\n';
      final updated = AgentConfigService.tomlSetString(
        content,
        'model',
        'gpt-5.5',
      );
      expect(
        updated,
        'model = "gpt-5.5"\n[profiles.work]\nmodel = "gpt-5"\n',
      );
    });

    test('creates content from an empty file', () {
      expect(
        AgentConfigService.tomlSetString('', 'model', 'gpt-5.5'),
        'model = "gpt-5.5"\n',
      );
    });

    test('escapes double quotes and backslashes in values', () {
      final updated = AgentConfigService.tomlSetString(
        '',
        'model',
        'a"b\\c',
      );
      expect(updated, 'model = "a\\"b\\\\c"\n');
      // Round-trip: escaped quotes and backslashes parse back.
      expect(AgentConfigService.tomlGetString(updated, 'model'), 'a"b\\c');
    });
  });

  group('AgentConfigService.jsonSetDotted', () {
    test('sets a top-level key in an empty document', () {
      expect(
        AgentConfigService.jsonSetDotted('', 'model', 'opus'),
        '{\n  "model": "opus"\n}\n',
      );
    });

    test('creates intermediate objects for dotted keys', () {
      final updated = AgentConfigService.jsonSetDotted(
        '{}',
        'permissions.defaultMode',
        'plan',
      );
      expect(
        updated,
        '{\n  "permissions": {\n    "defaultMode": "plan"\n  }\n}\n',
      );
    });

    test('preserves existing keys and uses 2-space indent', () {
      const content = '{\n'
          '  "model": "sonnet",\n'
          '  "permissions": {\n'
          '    "allow": [\n'
          '      "Bash(npm run test *)"\n'
          '    ]\n'
          '  }\n'
          '}\n';
      final updated = AgentConfigService.jsonSetDotted(
        content,
        'permissions.defaultMode',
        'acceptEdits',
      );
      expect(
        updated,
        '{\n'
        '  "model": "sonnet",\n'
        '  "permissions": {\n'
        '    "allow": [\n'
        '      "Bash(npm run test *)"\n'
        '    ],\n'
        '    "defaultMode": "acceptEdits"\n'
        '  }\n'
        '}\n',
      );
    });

    test('throws when the top level is not an object', () {
      expect(
        () => AgentConfigService.jsonSetDotted('[1, 2]', 'model', 'opus'),
        throwsFormatException,
      );
    });

    test('throws when a path segment collides with a scalar', () {
      expect(
        () => AgentConfigService.jsonSetDotted(
          '{"permissions": true}',
          'permissions.defaultMode',
          'plan',
        ),
        throwsFormatException,
      );
    });
  });

  group('AgentConfigService.jsonGetDotted', () {
    test('reads a nested value', () {
      const content = '{"permissions": {"defaultMode": "plan"}}';
      expect(
        AgentConfigService.jsonGetDotted(content, 'permissions.defaultMode'),
        'plan',
      );
    });

    test('returns null for missing segments', () {
      const content = '{"permissions": {}}';
      expect(
        AgentConfigService.jsonGetDotted(content, 'permissions.defaultMode'),
        isNull,
      );
      expect(
        AgentConfigService.jsonGetDotted(content, 'other.key'),
        isNull,
      );
    });

    test('returns null for empty content', () {
      expect(AgentConfigService.jsonGetDotted('', 'model'), isNull);
    });
  });

  group('AgentConfigService remote file operations', () {
    test('readRemoteFile returns null for a missing file', () async {
      final ssh = FakeSshClient();
      expect(
        await AgentConfigService.readRemoteFile(ssh, r'$HOME/x.json'),
        isNull,
      );
    });

    test('readRemoteFile returns file content', () async {
      final ssh = FakeSshClient(files: {r'$HOME/x.json': '{"a": 1}'});
      expect(
        await AgentConfigService.readRemoteFile(ssh, r'$HOME/x.json'),
        '{"a": 1}',
      );
    });

    test('writeRemoteFileAtomic writes content and keeps a one-time backup',
        () async {
      const path = r'$HOME/.codex/config.toml';
      final ssh = FakeSshClient(files: {path: 'model = "gpt-5"\n'});

      await AgentConfigService.writeRemoteFileAtomic(
        ssh,
        path,
        'model = "gpt-5.5"\n',
      );
      expect(ssh.files[path], 'model = "gpt-5.5"\n');
      expect(
        ssh.files['$path${AgentConfigService.backupSuffix}'],
        'model = "gpt-5"\n',
      );
      // The write went through a temp file + mv (atomic rename).
      expect(
        ssh.execCommands.last,
        allOf(contains('base64 -d'), contains('mv -f --')),
      );

      // A second write must not overwrite the original backup.
      await AgentConfigService.writeRemoteFileAtomic(
        ssh,
        path,
        'model = "gpt-6"\n',
      );
      expect(ssh.files[path], 'model = "gpt-6"\n');
      expect(
        ssh.files['$path${AgentConfigService.backupSuffix}'],
        'model = "gpt-5"\n',
      );
    });

    test('writeRemoteFileAtomic creates the file when it does not exist',
        () async {
      const path = r'$HOME/.claude/settings.json';
      final ssh = FakeSshClient();
      await AgentConfigService.writeRemoteFileAtomic(ssh, path, '{}\n');
      expect(ssh.files[path], '{}\n');
      expect(
        ssh.files.containsKey('$path${AgentConfigService.backupSuffix}'),
        isFalse,
      );
    });
  });
}
