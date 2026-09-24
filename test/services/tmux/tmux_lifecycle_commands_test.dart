// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/commands/lifecycle_commands.dart';

void main() {
  group('TmuxCommands', () {
    group('windowRestoreTrap', () {
      test('restores size and clears manual in one tmux call for a target', () {
        expect(
          TmuxLifecycleCommands.windowRestoreTrap([
            '@1',
          ], tmuxBin: '/usr/bin/tmux'),
          'trap "\'/usr/bin/tmux\' resize-window -t @1 -A \\; '
          'set -uw -t @1 window-size 2>/dev/null" EXIT HUP TERM',
        );
      });

      test('chains multiple targets in a single tmux invocation', () {
        expect(
          TmuxLifecycleCommands.windowRestoreTrap([
            '@1',
            '%3',
          ], tmuxBin: '/bin/tmux'),
          'trap "\'/bin/tmux\' resize-window -t @1 -A \\; set -uw -t @1 window-size \\; '
          'resize-window -t %3 -A \\; set -uw -t %3 window-size 2>/dev/null" EXIT HUP TERM',
        );
      });

      test('escapes targets with special characters', () {
        expect(
          TmuxLifecycleCommands.windowRestoreTrap([
            'my session:0',
          ], tmuxBin: '/usr/bin/tmux'),
          'trap "\'/usr/bin/tmux\' resize-window -t "my session:0" -A \\; '
          'set -uw -t "my session:0" window-size 2>/dev/null" EXIT HUP TERM',
        );
      });

      test('escapes glob, tilde and comment characters', () {
        expect(
          TmuxLifecycleCommands.windowRestoreTrap([
            '*',
            '~root',
            '#comment',
          ], tmuxBin: '/usr/bin/tmux'),
          'trap "\'/usr/bin/tmux\' resize-window -t "*" -A \\; set -uw -t "*" window-size \\; '
          'resize-window -t "~root" -A \\; set -uw -t "~root" window-size \\; '
          'resize-window -t "#comment" -A \\; set -uw -t "#comment" window-size 2>/dev/null" EXIT HUP TERM',
        );
      });

      test('empty targets clears the trap', () {
        expect(
          TmuxLifecycleCommands.windowRestoreTrap([], tmuxBin: '/usr/bin/tmux'),
          'trap - EXIT HUP TERM',
        );
        expect(
          TmuxLifecycleCommands.clearWindowRestoreTrap(),
          'trap - EXIT HUP TERM',
        );
      });
    });
  });
}
