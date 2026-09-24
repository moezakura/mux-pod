// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/commands/layout.dart';
import 'package:flutter_muxpod/services/tmux/commands/window_commands.dart';

void main() {
  group('TmuxCommands', () {
    group('killWindow', () {
      test('generates correct kill-window command', () {
        expect(
          TmuxWindowCommands.kill('my-session', 2),
          'tmux kill-window -t my-session:2',
        );
      });
    });
  });

  group('TmuxCommands', () {
    group('renameWindow', () {
      test('generates correct rename-window command', () {
        expect(
          TmuxWindowCommands.rename('main', 2, 'build'),
          'tmux rename-window -t main:2 build',
        );
      });

      test('escapes session name and new name with spaces', () {
        expect(
          TmuxWindowCommands.rename('my session', 0, 'new name'),
          'tmux rename-window -t "my session":0 "new name"',
        );
      });

      test('allows underscores and hyphens without escaping', () {
        expect(
          TmuxWindowCommands.rename('dev', 10, 'a_b-c'),
          'tmux rename-window -t dev:10 a_b-c',
        );
      });
    });
  });

  group('TmuxCommands', () {
    group('resizeWindow', () {
      test('generates resize-window with cols only', () {
        expect(
          TmuxWindowCommands.resize('my-session:0', cols: 160),
          'tmux resize-window -t my-session:0 -x 160',
        );
      });

      test('generates resize-window with rows only', () {
        expect(
          TmuxWindowCommands.resize('my-session:0', rows: 48),
          'tmux resize-window -t my-session:0 -y 48',
        );
      });

      test('generates resize-window with both cols and rows', () {
        expect(
          TmuxWindowCommands.resize('@1', cols: 200, rows: 50),
          'tmux resize-window -t @1 -x 200 -y 50',
        );
      });

      test('escapes target with special characters', () {
        expect(
          TmuxWindowCommands.resize('my session:0', cols: 80),
          'tmux resize-window -t "my session:0" -x 80',
        );
      });
    });
  });

  group('TmuxCommands', () {
    group('resizeWindowAuto', () {
      test(
        'generates resize -A then unset window-size (restore auto sizing)',
        () {
          expect(
            TmuxWindowCommands.resizeAuto('my-session:0'),
            'tmux resize-window -t my-session:0 -A ; '
            'tmux set -uw -t my-session:0 window-size',
          );
        },
      );

      test('escapes target with special characters in both commands', () {
        expect(
          TmuxWindowCommands.resizeAuto('my session:0'),
          'tmux resize-window -t "my session:0" -A ; '
          'tmux set -uw -t "my session:0" window-size',
        );
      });
    });
  });

  group('newWindow', () {
    test('generates new-window command with defaults', () {
      expect(
        TmuxWindowCommands.create(sessionName: 'main'),
        'tmux new-window -t main:',
      );
    });

    test('generates new-window command with background flag', () {
      expect(
        TmuxWindowCommands.create(sessionName: 'main', background: true),
        'tmux new-window -t main: -d',
      );
    });

    test('includes window name and start directory', () {
      expect(
        TmuxWindowCommands.create(
          sessionName: 'main',
          windowName: 'build',
          startDirectory: '/home/user',
        ),
        'tmux new-window -t main: -n build -c /home/user',
      );
    });
  });

  group('selectWindow', () {
    test('generates select-window command', () {
      expect(
        TmuxWindowCommands.select('main', 2),
        'tmux select-window -t main:2',
      );
    });
  });

  group('selectLayout', () {
    test('selectLayout', () {
      expect(
        TmuxWindowCommands.selectLayout('%0', TmuxLayout.tiled),
        'tmux select-layout -t %0 tiled',
      );
    });
  });
}
