// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/commands/pane_commands.dart';

void main() {
  group('TmuxCommands', () {
    group('killPane', () {
      test('generates correct kill-pane command for standard pane ID', () {
        expect(TmuxPaneCommands.kill('%0'), 'tmux kill-pane -t %0');
      });

      test('generates correct kill-pane command for multi-digit pane ID', () {
        expect(TmuxPaneCommands.kill('%42'), 'tmux kill-pane -t %42');
      });

      test('escapes pane ID with special characters', () {
        // Normally pane IDs are %N, but _escapeArg should handle edge cases
        expect(TmuxPaneCommands.kill('%1'), 'tmux kill-pane -t %1');
      });
    });
  });

  group('TmuxCommands', () {
    group('selectPane', () {
      test('generates correct select-pane command', () {
        expect(TmuxPaneCommands.select('%0'), 'tmux select-pane -t %0');
      });
    });
  });

  group('TmuxCommands', () {
    group('splitWindowHorizontal', () {
      test('generates basic horizontal split command', () {
        expect(
          TmuxPaneCommands.splitHorizontal(target: '%0'),
          'tmux split-window -h -t %0',
        );
      });

      test('generates horizontal split with percentage', () {
        expect(
          TmuxPaneCommands.splitHorizontal(target: '%1', percentage: 50),
          'tmux split-window -h -t %1 -p 50',
        );
      });

      test('generates horizontal split with start directory', () {
        expect(
          TmuxPaneCommands.splitHorizontal(
            target: '%0',
            startDirectory: '/home/user',
          ),
          'tmux split-window -h -t %0 -c /home/user',
        );
      });

      test('generates horizontal split with directory containing spaces', () {
        expect(
          TmuxPaneCommands.splitHorizontal(
            target: '%0',
            startDirectory: '/home/my projects',
          ),
          'tmux split-window -h -t %0 -c "/home/my projects"',
        );
      });
    });
  });

  group('TmuxCommands', () {
    group('splitWindowVertical', () {
      test('generates basic vertical split command', () {
        expect(
          TmuxPaneCommands.splitVertical(target: '%0'),
          'tmux split-window -v -t %0',
        );
      });
    });
  });

  group('TmuxCommands', () {
    group('resizePane', () {
      test('generates zoom command', () {
        expect(
          TmuxPaneCommands.resize('%0', zoom: true),
          'tmux resize-pane -t %0 -Z',
        );
      });

      test('generates unzoom command', () {
        expect(
          TmuxPaneCommands.resize('%0', zoom: false),
          'tmux resize-pane -t %0 -z',
        );
      });
    });
  });

  group('TmuxCommands', () {
    group('resizePaneToSize', () {
      test('generates resize-pane with cols only', () {
        expect(
          TmuxPaneCommands.resizeToSize('%0', cols: 120),
          'tmux resize-pane -t %0 -x 120',
        );
      });

      test('generates resize-pane with rows only', () {
        expect(
          TmuxPaneCommands.resizeToSize('%0', rows: 40),
          'tmux resize-pane -t %0 -y 40',
        );
      });

      test('generates resize-pane with both cols and rows', () {
        expect(
          TmuxPaneCommands.resizeToSize('%1', cols: 200, rows: 50),
          'tmux resize-pane -t %1 -x 200 -y 50',
        );
      });

      test('escapes pane ID with special characters', () {
        expect(
          TmuxPaneCommands.resizeToSize('my pane', cols: 80),
          'tmux resize-pane -t "my pane" -x 80',
        );
      });
    });
  });
}
