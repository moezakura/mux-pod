// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/commands/list_commands.dart';
import 'package:flutter_muxpod/services/tmux/tmux_delimiters.dart';

void main() {
  group('TmuxCommands', () {
    test(
      'TMUX-CMD-001: every -F command carries the delimiters it was handed',
      () {
        final delimiters = TmuxDelimiters.random();
        final commands = [
          TmuxListCommands.sessions(delimiters),
          TmuxListCommands.windows('main', delimiters),
          TmuxListCommands.panes('main', 0, delimiters),
          TmuxListCommands.allPanes(delimiters),
        ];

        for (final command in commands) {
          expect(command, contains(delimiters.field));
          expect(command, contains(delimiters.record));
          // A control character never survives the round trip: tmux rewrites
          // it to '_' for a non-UTF-8 client and the parser then sees a single
          // field per record.
          expect(
            command.codeUnits.every((c) => c >= 0x20 && c != 0x7f),
            isTrue,
            reason: 'command must stay free of control characters: $command',
          );
        }
      },
    );
  });

  group('listSessions', () {
    test('generates detailed list-sessions command', () {
      final d = TmuxDelimiters.random();
      final fs = d.field;
      final rs = d.record;
      expect(
        TmuxListCommands.sessions(d),
        'tmux list-sessions -F "'
        '#{session_name}$fs'
        '#{session_created}$fs'
        '#{session_attached}$fs'
        '#{session_windows}$fs'
        '#{session_id}$rs'
        '"',
      );
    });
  });

  group('listSessionsSimple', () {
    test('generates simple list-sessions command', () {
      expect(
        TmuxListCommands.sessionsSimple(),
        'tmux list-sessions -F "#{session_name}:#{session_windows}:#{session_attached}"',
      );
    });
  });

  group('listWindows', () {
    test('generates detailed list-windows command', () {
      final d = TmuxDelimiters.random();
      final fs = d.field;
      final rs = d.record;
      expect(
        TmuxListCommands.windows('main', d),
        'tmux list-windows -t main -F "'
        '#{window_index}$fs'
        '#{window_id}$fs'
        '#{window_name}$fs'
        '#{window_active}$fs'
        '#{window_panes}$fs'
        '#{window_flags}$rs'
        '"',
      );
    });

    test('escapes session name', () {
      final d = TmuxDelimiters.random();
      final fs = d.field;
      final rs = d.record;
      expect(
        TmuxListCommands.windows('my session', d),
        'tmux list-windows -t "my session" -F "'
        '#{window_index}$fs'
        '#{window_id}$fs'
        '#{window_name}$fs'
        '#{window_active}$fs'
        '#{window_panes}$fs'
        '#{window_flags}$rs'
        '"',
      );
    });
  });

  group('listWindowsSimple', () {
    test('generates simple list-windows command', () {
      expect(
        TmuxListCommands.windowsSimple('main'),
        'tmux list-windows -t main -F "#{window_index}:#{window_name}:#{window_active}:#{window_panes}"',
      );
    });
  });

  group('listPanes', () {
    test('generates detailed list-panes command', () {
      final d = TmuxDelimiters.random();
      final fs = d.field;
      final rs = d.record;
      expect(
        TmuxListCommands.panes('main', 0, d),
        'tmux list-panes -t main:0 -F "'
        '#{pane_index}$fs'
        '#{pane_id}$fs'
        '#{pane_active}$fs'
        '#{pane_current_command}$fs'
        '#{pane_title}$fs'
        '#{pane_width}$fs'
        '#{pane_height}$fs'
        '#{cursor_x}$fs'
        '#{cursor_y}$rs'
        '"',
      );
    });
  });

  group('listPanesSimple', () {
    test('generates simple list-panes command', () {
      expect(
        TmuxListCommands.panesSimple('main', 0),
        'tmux list-panes -t main:0 -F "#{pane_index}:#{pane_id}:#{pane_active}:#{pane_width}x#{pane_height}"',
      );
    });
  });

  group('listAllPanes', () {
    test('generates list-panes -a command for full tree', () {
      final d = TmuxDelimiters.random();
      final fs = d.field;
      final rs = d.record;
      expect(
        TmuxListCommands.allPanes(d),
        'tmux list-panes -a -F "'
        '#{session_name}$fs'
        '#{session_id}$fs'
        '#{window_index}$fs'
        '#{window_id}$fs'
        '#{window_name}$fs'
        '#{window_active}$fs'
        '#{pane_index}$fs'
        '#{pane_id}$fs'
        '#{pane_active}$fs'
        '#{pane_width}$fs'
        '#{pane_height}$fs'
        '#{pane_left}$fs'
        '#{pane_top}$fs'
        '#{pane_title}$fs'
        '#{pane_current_command}$fs'
        '#{cursor_x}$fs'
        '#{cursor_y}$fs'
        '#{pane_current_path}$fs'
        '#{window_flags}$rs'
        '"',
      );
    });
  });
}
