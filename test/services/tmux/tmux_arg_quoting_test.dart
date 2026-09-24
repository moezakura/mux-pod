// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/commands/arg_quoting.dart';

void main() {
  group('TmuxCommands', () {
    group('chain', () {
      test('chains multiple commands with &&', () {
        expect(
          ShellCommandComposer.join([
            'tmux kill-pane -t %0',
            'tmux list-panes',
          ]),
          'tmux kill-pane -t %0 && tmux list-panes',
        );
      });
    });
  });

  group('pipe', () {
    test('pipes multiple commands', () {
      expect(
        ShellCommandComposer.pipeline(['cmd1', 'cmd2', 'cmd3']),
        'cmd1 | cmd2 | cmd3',
      );
    });
  });
}
