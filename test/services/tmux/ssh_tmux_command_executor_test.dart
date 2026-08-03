import 'package:flutter_muxpod/services/connection_error.dart';
import 'package:flutter_muxpod/services/ssh/ssh_connection_state.dart';
import 'package:flutter_muxpod/services/tmux/ssh_tmux_command_executor.dart';
import 'package:flutter_muxpod/services/tmux/tmux_backend.dart';
import 'package:flutter_muxpod/services/tmux/tmux_command_builder.dart';
import 'package:flutter_muxpod/services/tmux/tmux_version.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ssh_client.dart';

class _FailingInputTransport implements TmuxInputTransport {
  @override
  bool get isStarted => true;

  @override
  void sendNoWait(String data) {
    throw TmuxTransportException('injected failure');
  }
}

void main() {
  group('SshTmuxCommandExecutor', () {
    late FakeSshClient sshClient;
    late SshTmuxCommandExecutor executor;

    setUp(() {
      sshClient = FakeSshClient(tmuxPath: '/usr/bin/tmux');
      sshClient.setConnected(SshConnectionState.connected);
      sshClient.execOutputs = {
        r"$SHELL -lc 'command -v tmux'": '/usr/bin/tmux',
        '/usr/bin/tmux -V': 'tmux 3.2a',
      };
      executor = SshTmuxCommandExecutor(sshClient);
    });

    test('detects tmux path and resolves commands with it', () async {
      final output = await executor.exec(TmuxCommands.version());

      expect(output, 'tmux 3.2a');
      expect(TmuxVersionInfo.parse(output), isNotNull);
      expect(executor.tmuxPath, '/usr/bin/tmux');
      expect(sshClient.execCommands, contains("'/usr/bin/tmux' -V"));
    });

    test('sendKeysCommand falls back to exec when input shell is not started', () async {
      await executor.sendKeysCommand(TmuxCommands.sendKeys('target', 'C-c'));

      expect(sshClient.execCommands, isNotEmpty);
      final cmd = sshClient.execCommands.last;
      expect(cmd, contains("'/usr/bin/tmux'"));
      expect(cmd, contains('send-keys -t target -- C-c'));
    });

    test('restoreWindowsNoWait resolves resize-auto with detected tmux path', () async {
      await executor.restoreWindowsNoWait(['@1']);

      expect(sshClient.execCommands, isNotEmpty);
      final cmd = sshClient.execCommands.last;
      expect(cmd, contains("'/usr/bin/tmux'"));
      expect(cmd, contains('resize-window -t @1 -A'));
    });

    test('setWindowRestoreTrap stores command even when input shell is not started', () async {
      await executor.setWindowRestoreTrap(['@1']);

      expect(executor.lifecycle.currentRestoreTrapCommand, isNotNull);
      expect(
        executor.lifecycle.currentRestoreTrapCommand,
        contains('trap'),
      );
      final cmd = executor.lifecycle.currentRestoreTrapCommand!;
      expect(cmd, contains("'/usr/bin/tmux'"));
      expect(cmd, contains('resize-window -t @1 -A'));
    });

    test('reapplies last restore trap on input shell reboot', () async {
      await executor.setWindowRestoreTrap(['@1']);
      expect(sshClient.onInputShellRebooted, isNotNull);
      expect(() => sshClient.onInputShellRebooted!.call(), returnsNormally);
    });

    test('retries detection after first detection fails', () async {
      final client = FakeSshClient()
        ..setConnected(SshConnectionState.connected)
        ..tmuxPath = '/custom/tmux'
        ..userTmuxPath = '/custom/tmux';
      client.execExceptions = {
        "test -x '/custom/tmux'": SshConnectionError('detection failed'),
      };

      final retryExecutor = SshTmuxCommandExecutor(client);

      await expectLater(
        retryExecutor.exec(TmuxCommands.version()),
        throwsA(isA<SshConnectionError>()),
      );

      client.execExceptions = {};
      client.execExitCodes = {
        "test -x '/custom/tmux'": 0,
      };
      client.execOutputs = {
        '/custom/tmux -V': 'tmux 3.2a',
      };

      final output = await retryExecutor.exec(TmuxCommands.version());
      expect(output, 'tmux 3.2a');
      expect(retryExecutor.tmuxPath, '/custom/tmux');
    });

    test('sendKeysCommand falls back to exec and restarts input transport on TmuxTransportException', () async {
      sshClient.fakeInputTransport = _FailingInputTransport();

      await executor.sendKeysCommand(TmuxCommands.sendKeys('target', 'C-c'));

      expect(sshClient.restartInputTransportCount, 1);
      expect(sshClient.execCommands, isNotEmpty);
      final cmd = sshClient.execCommands.last;
      expect(cmd, contains("'/usr/bin/tmux'"));
      expect(cmd, contains('send-keys -t target -- C-c'));
    });
  });
}
