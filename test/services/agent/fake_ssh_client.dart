import 'dart:convert';

import 'package:flutter_muxpod/services/agent/agent_config_service.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

/// Hand-written fake of [SshClient] for agent adapter tests.
///
/// Records every command sent through [sendKeysCommand] and emulates a
/// tiny remote filesystem for the two command shapes
/// [AgentConfigService] issues through [execWithExitCode]:
///
/// - `cat -- "<path>"` reads a file (exit code 1 when missing).
/// - The atomic-write pipeline (`printf ... | base64 -d > tmp && mv -f`)
///   writes a file and keeps a one-time `.muxpod-bak` backup.
class FakeSshClient extends SshClient {
  /// Emulated remote filesystem: absolute path -> file content.
  final Map<String, String> files;

  /// Every command passed to [execWithExitCode], in order.
  final List<String> execCommands = [];

  /// Every command passed to [sendKeysCommand], in order.
  final List<String> sentKeyCommands = [];

  FakeSshClient({Map<String, String>? files}) : files = files ?? {};

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    execCommands.add(command);
    final catMatch = RegExp(r'^cat -- "([^"]+)"$').firstMatch(command);
    if (catMatch != null) {
      final path = catMatch.group(1)!;
      final content = files[path];
      if (content == null) {
        return (
          stdout: '',
          stderr: 'cat: $path: No such file or directory',
          exitCode: 1,
        );
      }
      return (stdout: content, stderr: '', exitCode: 0);
    }
    if (command.contains('base64 -d') && command.contains('mv -f --')) {
      _emulateAtomicWrite(command);
      return (stdout: '', stderr: '', exitCode: 0);
    }
    return (stdout: '', stderr: '', exitCode: 0);
  }

  /// Applies the shell semantics of
  /// [AgentConfigService.writeRemoteFileAtomic] to [files].
  void _emulateAtomicWrite(String command) {
    final encoded = RegExp(r"printf '%s' '([A-Za-z0-9+/=]*)'")
        .firstMatch(command)!
        .group(1)!;
    final content = utf8.decode(base64.decode(encoded));
    final mvMatch =
        RegExp(r'mv -f -- "([^"]+)" "([^"]+)"').firstMatch(command)!;
    final target = mvMatch.group(2)!;
    final backup = '$target${AgentConfigService.backupSuffix}';
    final existing = files[target];
    if (existing != null && !files.containsKey(backup)) {
      files[backup] = existing;
    }
    files[target] = content;
  }

  @override
  Future<void> sendKeysCommand(String command) async {
    sentKeyCommands.add(command);
  }
}
