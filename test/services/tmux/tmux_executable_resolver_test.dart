import 'package:flutter_muxpod/services/ssh/ssh_connection_state.dart';
import 'package:flutter_muxpod/services/tmux/tmux_executable_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ssh_client.dart';

void main() {
  group('TmuxExecutableResolver', () {
    late FakeSshClient client;
    late TmuxExecutableResolver resolver;

    setUp(() {
      client = FakeSshClient(tmuxPath: null);
      client.setConnected(SshConnectionState.connected);
      resolver = TmuxExecutableResolver();
    });

    test('auto-discovery succeeds via login shell', () async {
      client.execOutputs = {
        r"$SHELL -lc 'command -v tmux'": '/usr/bin/tmux',
      };

      await resolver.detect(client);

      expect(resolver.tmuxPath, '/usr/bin/tmux');
      expect(resolver.tmuxBin, '/usr/bin/tmux');
    });

    test('auto-discovery falls back to known paths when login shell fails', () async {
      client.execOutputs = {
        r"$SHELL -lc 'command -v tmux'": '',
      };
      client.execExitCodes = {
        'test -x /opt/homebrew/bin/tmux': 1,
        'test -x /usr/local/bin/tmux': 1,
        'test -x /usr/bin/tmux': 0,
      };

      await resolver.detect(client);

      expect(resolver.tmuxPath, '/usr/bin/tmux');
    });

    test('auto-discovery fails when no tmux is found', () async {
      client.execOutputs = {
        r"$SHELL -lc 'command -v tmux'": '',
      };
      client.execExitCodes = {
        'test -x /opt/homebrew/bin/tmux': 1,
        'test -x /usr/local/bin/tmux': 1,
        'test -x /usr/bin/tmux': 1,
      };

      await resolver.detect(client);

      expect(resolver.tmuxPath, isNull);
      expect(resolver.tmuxBin, 'tmux');
    });

    test('custom tmux path succeeds when executable', () async {
      client.execExitCodes = {
        "test -x '/custom/tmux'": 0,
      };

      await resolver.detect(client, userTmuxPath: '/custom/tmux');

      expect(resolver.tmuxPath, '/custom/tmux');
    });

    test('custom tmux path fails when not executable and preserves custom path', () async {
      client.execExitCodes = {
        "test -x '/custom/tmux'": 1,
      };
      client.execOutputs = {
        r"$SHELL -lc 'command -v tmux'": '/usr/bin/tmux',
      };

      await resolver.detect(client, userTmuxPath: '/custom/tmux');

      expect(resolver.tmuxPath, isNull);
      expect(resolver.customPath, '/custom/tmux');
      expect(resolver.tmuxBin, '/custom/tmux');
      expect(
        resolver.resolve('tmux -V'),
        "'/custom/tmux' -V",
      );
    });
  });
}
