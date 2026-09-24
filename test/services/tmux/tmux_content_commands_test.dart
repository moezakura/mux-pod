// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/commands/content_commands.dart';

void main() {
  group('TmuxCommands', () {
    group('setHistoryLimit', () {
      test('generates session-scoped history-limit set-option command', () {
        expect(
          TmuxContentCommands.setHistoryLimit(10000, target: 'main'),
          'tmux set-option -t main history-limit 10000',
        );
      });
    });
  });

  group('cursor and mode', () {
    test('getCursorPosition', () {
      expect(
        TmuxContentCommands.cursorPosition('%0'),
        'tmux display-message -p -t %0 "#{cursor_x},#{cursor_y},#{pane_width},#{pane_height}"',
      );
    });

    test('getPaneMode', () {
      expect(
        TmuxContentCommands.getMode('%0'),
        'tmux display-message -p -t %0 "#{pane_mode}"',
      );
    });
  });

  group('capturePane', () {
    test('generates visible capture with escape sequences', () {
      expect(
        TmuxContentCommands.capture('%0'),
        'tmux capture-pane -t %0 -p -e',
      );
    });

    test('generates capture with start and end lines', () {
      expect(
        TmuxContentCommands.capture('%0', startLine: -120, endLine: 0),
        'tmux capture-pane -t %0 -p -e -S -120 -E 0',
      );
    });

    test('capturePaneVisible omits line range', () {
      expect(
        TmuxContentCommands.captureVisible('%0'),
        'tmux capture-pane -t %0 -p -e',
      );
    });

    test('capturePaneAll uses full scrollback range', () {
      expect(
        TmuxContentCommands.captureAll('%0'),
        'tmux capture-pane -t %0 -p -e -S -32768 -E 32768',
      );
    });
  });
}
