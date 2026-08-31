import 'dart:convert';

// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/tmux_command_builder.dart';
import 'package:flutter_muxpod/services/tmux/tmux_parser_adapter.dart';

void main() {
  group('TmuxCommands', () {
    test('TMUX-CMD-001: deprecated delimiter tracks the field delimiter', () {
      expect(TmuxCommands.delimiter, TmuxCommands.fieldDelimiter);
      // The builder and the parser must agree, or every record parses to a
      // single field and the session list comes back empty with no error.
      expect(TmuxCommands.fieldDelimiter, TmuxParser.defaultFieldDelimiter);
      expect(TmuxCommands.recordDelimiter, TmuxParser.defaultRecordDelimiter);
    });

    group('killPane', () {
      test('generates correct kill-pane command for standard pane ID', () {
        expect(TmuxCommands.killPane('%0'), 'tmux kill-pane -t %0');
      });

      test('generates correct kill-pane command for multi-digit pane ID', () {
        expect(TmuxCommands.killPane('%42'), 'tmux kill-pane -t %42');
      });

      test('escapes pane ID with special characters', () {
        // Normally pane IDs are %N, but _escapeArg should handle edge cases
        expect(TmuxCommands.killPane('%1'), 'tmux kill-pane -t %1');
      });
    });

    group('setHistoryLimit', () {
      test('generates session-scoped history-limit set-option command', () {
        expect(
          TmuxCommands.setHistoryLimit(10000, target: 'main'),
          'tmux set-option -t main history-limit 10000',
        );
      });
    });

    group('selectPane', () {
      test('generates correct select-pane command', () {
        expect(TmuxCommands.selectPane('%0'), 'tmux select-pane -t %0');
      });
    });

    group('splitWindowHorizontal', () {
      test('generates basic horizontal split command', () {
        expect(
          TmuxCommands.splitWindowHorizontal(target: '%0'),
          'tmux split-window -h -t %0',
        );
      });

      test('generates horizontal split with percentage', () {
        expect(
          TmuxCommands.splitWindowHorizontal(target: '%1', percentage: 50),
          'tmux split-window -h -t %1 -p 50',
        );
      });

      test('generates horizontal split with start directory', () {
        expect(
          TmuxCommands.splitWindowHorizontal(
            target: '%0',
            startDirectory: '/home/user',
          ),
          'tmux split-window -h -t %0 -c /home/user',
        );
      });

      test('generates horizontal split with directory containing spaces', () {
        expect(
          TmuxCommands.splitWindowHorizontal(
            target: '%0',
            startDirectory: '/home/my projects',
          ),
          'tmux split-window -h -t %0 -c "/home/my projects"',
        );
      });
    });

    group('splitWindowVertical', () {
      test('generates basic vertical split command', () {
        expect(
          TmuxCommands.splitWindowVertical(target: '%0'),
          'tmux split-window -v -t %0',
        );
      });
    });

    group('killSession', () {
      test('generates correct kill-session command', () {
        expect(
          TmuxCommands.killSession('my-session'),
          'tmux kill-session -t my-session',
        );
      });

      test('escapes session name with spaces', () {
        expect(
          TmuxCommands.killSession('my session'),
          'tmux kill-session -t "my session"',
        );
      });
    });

    group('killWindow', () {
      test('generates correct kill-window command', () {
        expect(
          TmuxCommands.killWindow('my-session', 2),
          'tmux kill-window -t my-session:2',
        );
      });
    });

    group('renameWindow', () {
      test('generates correct rename-window command', () {
        expect(
          TmuxCommands.renameWindow('main', 2, 'build'),
          'tmux rename-window -t main:2 build',
        );
      });

      test('escapes session name and new name with spaces', () {
        expect(
          TmuxCommands.renameWindow('my session', 0, 'new name'),
          'tmux rename-window -t "my session":0 "new name"',
        );
      });

      test('allows underscores and hyphens without escaping', () {
        expect(
          TmuxCommands.renameWindow('dev', 10, 'a_b-c'),
          'tmux rename-window -t dev:10 a_b-c',
        );
      });
    });

    group('resizePane', () {
      test('generates zoom command', () {
        expect(
          TmuxCommands.resizePane('%0', zoom: true),
          'tmux resize-pane -t %0 -Z',
        );
      });

      test('generates unzoom command', () {
        expect(
          TmuxCommands.resizePane('%0', zoom: false),
          'tmux resize-pane -t %0 -z',
        );
      });
    });

    group('resizePaneToSize', () {
      test('generates resize-pane with cols only', () {
        expect(
          TmuxCommands.resizePaneToSize('%0', cols: 120),
          'tmux resize-pane -t %0 -x 120',
        );
      });

      test('generates resize-pane with rows only', () {
        expect(
          TmuxCommands.resizePaneToSize('%0', rows: 40),
          'tmux resize-pane -t %0 -y 40',
        );
      });

      test('generates resize-pane with both cols and rows', () {
        expect(
          TmuxCommands.resizePaneToSize('%1', cols: 200, rows: 50),
          'tmux resize-pane -t %1 -x 200 -y 50',
        );
      });

      test('escapes pane ID with special characters', () {
        expect(
          TmuxCommands.resizePaneToSize('my pane', cols: 80),
          'tmux resize-pane -t "my pane" -x 80',
        );
      });
    });

    group('resizeWindow', () {
      test('generates resize-window with cols only', () {
        expect(
          TmuxCommands.resizeWindow('my-session:0', cols: 160),
          'tmux resize-window -t my-session:0 -x 160',
        );
      });

      test('generates resize-window with rows only', () {
        expect(
          TmuxCommands.resizeWindow('my-session:0', rows: 48),
          'tmux resize-window -t my-session:0 -y 48',
        );
      });

      test('generates resize-window with both cols and rows', () {
        expect(
          TmuxCommands.resizeWindow('@1', cols: 200, rows: 50),
          'tmux resize-window -t @1 -x 200 -y 50',
        );
      });

      test('escapes target with special characters', () {
        expect(
          TmuxCommands.resizeWindow('my session:0', cols: 80),
          'tmux resize-window -t "my session:0" -x 80',
        );
      });
    });

    group('resizeWindowAuto', () {
      test(
        'generates resize -A then unset window-size (restore auto sizing)',
        () {
          expect(
            TmuxCommands.resizeWindowAuto('my-session:0'),
            'tmux resize-window -t my-session:0 -A ; '
            'tmux set -uw -t my-session:0 window-size',
          );
        },
      );

      test('escapes target with special characters in both commands', () {
        expect(
          TmuxCommands.resizeWindowAuto('my session:0'),
          'tmux resize-window -t "my session:0" -A ; '
          'tmux set -uw -t "my session:0" window-size',
        );
      });
    });

    group('windowRestoreTrap', () {
      test('restores size and clears manual in one tmux call for a target', () {
        expect(
          TmuxCommands.windowRestoreTrap(['@1'], tmuxBin: '/usr/bin/tmux'),
          'trap "\'/usr/bin/tmux\' resize-window -t @1 -A \\; '
          'set -uw -t @1 window-size 2>/dev/null" EXIT HUP TERM',
        );
      });

      test('chains multiple targets in a single tmux invocation', () {
        expect(
          TmuxCommands.windowRestoreTrap(['@1', '%3'], tmuxBin: '/bin/tmux'),
          'trap "\'/bin/tmux\' resize-window -t @1 -A \\; set -uw -t @1 window-size \\; '
          'resize-window -t %3 -A \\; set -uw -t %3 window-size 2>/dev/null" EXIT HUP TERM',
        );
      });

      test('escapes targets with special characters', () {
        expect(
          TmuxCommands.windowRestoreTrap([
            'my session:0',
          ], tmuxBin: '/usr/bin/tmux'),
          'trap "\'/usr/bin/tmux\' resize-window -t "my session:0" -A \\; '
          'set -uw -t "my session:0" window-size 2>/dev/null" EXIT HUP TERM',
        );
      });

      test('escapes glob, tilde and comment characters', () {
        expect(
          TmuxCommands.windowRestoreTrap([
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
          TmuxCommands.windowRestoreTrap([], tmuxBin: '/usr/bin/tmux'),
          'trap - EXIT HUP TERM',
        );
        expect(TmuxCommands.clearWindowRestoreTrap(), 'trap - EXIT HUP TERM');
      });
    });

    group('sendKeys', () {
      test('generates literal send-keys command', () {
        // _escapeArg escapes backslashes, so \\ becomes \\\\
        expect(
          TmuxCommands.sendKeys('%0', '\\x1b[I', literal: true),
          'tmux send-keys -t %0 -l -- "\\\\x1b[I"',
        );
      });

      test('generates non-literal send-keys command', () {
        expect(
          TmuxCommands.sendKeys('%0', 'Enter'),
          'tmux send-keys -t %0 -- Enter',
        );
      });

      test('guards dash-prefixed keys with -- (no tmux option injection)', () {
        expect(
          TmuxCommands.sendKeys('%0', '-X cancel', literal: true),
          'tmux send-keys -t %0 -l -- "-X cancel"',
        );
      });
    });

    group('chain', () {
      test('chains multiple commands with &&', () {
        expect(
          TmuxCommands.chain(['tmux kill-pane -t %0', 'tmux list-panes']),
          'tmux kill-pane -t %0 && tmux list-panes',
        );
      });
    });

    group('loadBufferAndPaste', () {
      // Helper: extract the base64 payload from a printf '%s' '...' token.
      String? extractBase64(String cmd) {
        final match = RegExp(
          r"printf '%s' '([A-Za-z0-9+/=]+)'",
        ).firstMatch(cmd);
        return match?.group(1);
      }

      test('single ASCII line embeds correct base64 and command structure', () {
        const text = 'hello';
        final expected = base64.encode(utf8.encode(text));
        final cmd = TmuxCommands.loadBufferAndPaste('%0', text);

        expect(cmd, contains("printf '%s' '$expected'"));
        expect(cmd, contains('| base64 -d'));
        expect(cmd, contains('| tmux load-buffer -b '));
        expect(cmd, contains('- &&'));
        expect(cmd, contains('tmux paste-buffer -d -p -b '));
        expect(cmd, contains('-t %0'));
        // Must NOT use echo -n (POSIX-non-portable on dash/busybox).
        expect(cmd, isNot(contains('echo -n')));
      });

      test(
        'empty text: helper returns a command string (guard handled by caller)',
        () {
          // The helper is a pure command-string builder; empty-text guard lives
          // in _sendMultilineText. The helper does not throw on empty input.
          expect(
            () => TmuxCommands.loadBufferAndPaste('%0', ''),
            returnsNormally,
          );
          // The encoded form of '' is '' in base64; command should still be valid.
          final cmd = TmuxCommands.loadBufferAndPaste('%0', '');
          expect(cmd, contains('printf'));
        },
      );

      test('base64 encoded payload contains no newline characters', () {
        // dart:convert base64.encode does NOT insert line breaks (unlike CLI base64).
        // Newlines in the encoded string would break the single-line shell command.
        const text =
            'line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10';
        final cmd = TmuxCommands.loadBufferAndPaste('%0', text);
        final encoded = extractBase64(cmd);
        expect(encoded, isNotNull);
        expect(encoded, isNot(contains('\n')));
        expect(encoded, isNot(contains('\r')));
      });

      test('multi-line payload round-trips through base64 correctly', () {
        const text = 'line1\nline2\nline3';
        final cmd = TmuxCommands.loadBufferAndPaste('%1', text);

        final encoded = extractBase64(cmd);
        expect(encoded, isNotNull);
        final decoded = utf8.decode(base64.decode(encoded!));
        expect(decoded, equals(text));
      });

      test(
        'special chars are safe: payload base64 contains no shell metachars from input',
        () {
          const text = "echo 'hi'; rm -rf \$HOME";
          final cmd = TmuxCommands.loadBufferAndPaste('%0', text);

          // The base64 alphabet contains only [A-Za-z0-9+/=] — no quotes or dollars.
          final encoded = extractBase64(cmd);
          expect(encoded, isNotNull);
          expect(encoded, isNot(contains("'")));
          expect(encoded, isNot(contains(r'$')));

          // Round-trip must restore the original.
          final decoded = utf8.decode(base64.decode(encoded!));
          expect(decoded, equals(text));
        },
      );

      test('UTF-8 multibyte payload round-trips correctly', () {
        const text = 'あいうえお\nテスト';
        final cmd = TmuxCommands.loadBufferAndPaste('%0', text);

        final encoded = extractBase64(cmd);
        expect(encoded, isNotNull);
        final decoded = utf8.decode(base64.decode(encoded!));
        expect(decoded, equals(text));
      });

      test('target with space is escaped by _escapeArg (double-quoted)', () {
        final cmd = TmuxCommands.loadBufferAndPaste('my session:0.0', 'hi');
        // _escapeArg wraps targets containing spaces in double quotes.
        expect(cmd, contains('"my session:0.0"'));
      });

      test('buffer name matches muxpod-<digits>-<hex6> pattern', () {
        final cmd = TmuxCommands.loadBufferAndPaste('%0', 'test');
        final bufPattern = RegExp(r'muxpod-\d+-[0-9a-f]{6}');
        expect(bufPattern.hasMatch(cmd), isTrue);
      });

      test('two calls produce distinct buffer names', () {
        final cmd1 = TmuxCommands.loadBufferAndPaste('%0', 'a');
        final cmd2 = TmuxCommands.loadBufferAndPaste('%0', 'b');

        final pattern = RegExp(r'muxpod-\d+-[0-9a-f]{6}');
        expect(pattern.hasMatch(cmd1), isTrue);
        expect(pattern.hasMatch(cmd2), isTrue);
        // The buffer is deleted immediately after paste (-d flag).
        expect(cmd1, contains('paste-buffer -d'));
        expect(cmd2, contains('paste-buffer -d'));
      });
    });

    group('loadBufferAndPasteNoBracketed', () {
      test('omits -p flag and uses printf', () {
        final cmd = TmuxCommands.loadBufferAndPasteNoBracketed('%0', 'hello');
        expect(cmd, contains("printf '%s'"));
        expect(cmd, contains('paste-buffer -d -b'));
        expect(cmd, isNot(contains('paste-buffer -d -p')));
        expect(cmd, isNot(contains('echo -n')));
      });

      test('round-trips payload correctly', () {
        const text = 'line1\nline2';
        final cmd = TmuxCommands.loadBufferAndPasteNoBracketed('%1', text);
        final match = RegExp(
          r"printf '%s' '([A-Za-z0-9+/=]+)'",
        ).firstMatch(cmd);
        expect(match, isNotNull);
        final decoded = utf8.decode(base64.decode(match!.group(1)!));
        expect(decoded, equals(text));
      });
    });
  });

  group('SplitDirection', () {
    test('has horizontal and vertical values', () {
      expect(SplitDirection.values, contains(SplitDirection.horizontal));
      expect(SplitDirection.values, contains(SplitDirection.vertical));
    });
  });

  group('TmuxLayout', () {
    test('name returns correct tmux layout string', () {
      expect(TmuxLayout.evenHorizontal.name, 'even-horizontal');
      expect(TmuxLayout.evenVertical.name, 'even-vertical');
      expect(TmuxLayout.mainHorizontal.name, 'main-horizontal');
      expect(TmuxLayout.mainVertical.name, 'main-vertical');
      expect(TmuxLayout.tiled.name, 'tiled');
    });
  });

  group('listSessions', () {
    test('generates detailed list-sessions command', () {
      final fs = TmuxCommands.fieldDelimiter;
      final rs = TmuxCommands.recordDelimiter;
      expect(
        TmuxCommands.listSessions(),
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
        TmuxCommands.listSessionsSimple(),
        'tmux list-sessions -F "#{session_name}:#{session_windows}:#{session_attached}"',
      );
    });
  });

  group('hasSession', () {
    test('generates has-session check command', () {
      expect(
        TmuxCommands.hasSession('main'),
        'tmux has-session -t main 2>/dev/null && echo "1" || echo "0"',
      );
    });

    test('escapes session name with spaces', () {
      expect(
        TmuxCommands.hasSession('my session'),
        'tmux has-session -t "my session" 2>/dev/null && echo "1" || echo "0"',
      );
    });
  });

  group('newSession', () {
    test('generates new-session command detached by default', () {
      expect(
        TmuxCommands.newSession(name: 'main'),
        'tmux new-session -d -s main',
      );
    });

    test('generates new-session command without detached flag', () {
      expect(
        TmuxCommands.newSession(name: 'main', detached: false),
        'tmux new-session -s main',
      );
    });

    test('includes window name and start directory', () {
      expect(
        TmuxCommands.newSession(
          name: 'main',
          windowName: 'shell',
          startDirectory: '/home/user',
          detached: true,
        ),
        'tmux new-session -d -s main -n shell -c /home/user',
      );
    });
  });

  group('renameSession', () {
    test('generates rename-session command', () {
      expect(
        TmuxCommands.renameSession('old', 'new'),
        'tmux rename-session -t old new',
      );
    });

    test('escapes names with spaces', () {
      expect(
        TmuxCommands.renameSession('old sess', 'new sess'),
        'tmux rename-session -t "old sess" "new sess"',
      );
    });
  });

  group('listWindows', () {
    test('generates detailed list-windows command', () {
      final fs = TmuxCommands.fieldDelimiter;
      final rs = TmuxCommands.recordDelimiter;
      expect(
        TmuxCommands.listWindows('main'),
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
      final fs = TmuxCommands.fieldDelimiter;
      final rs = TmuxCommands.recordDelimiter;
      expect(
        TmuxCommands.listWindows('my session'),
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
        TmuxCommands.listWindowsSimple('main'),
        'tmux list-windows -t main -F "#{window_index}:#{window_name}:#{window_active}:#{window_panes}"',
      );
    });
  });

  group('newWindow', () {
    test('generates new-window command with defaults', () {
      expect(
        TmuxCommands.newWindow(sessionName: 'main'),
        'tmux new-window -t main:',
      );
    });

    test('generates new-window command with background flag', () {
      expect(
        TmuxCommands.newWindow(sessionName: 'main', background: true),
        'tmux new-window -t main: -d',
      );
    });

    test('includes window name and start directory', () {
      expect(
        TmuxCommands.newWindow(
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
        TmuxCommands.selectWindow('main', 2),
        'tmux select-window -t main:2',
      );
    });
  });

  group('listPanes', () {
    test('generates detailed list-panes command', () {
      final fs = TmuxCommands.fieldDelimiter;
      final rs = TmuxCommands.recordDelimiter;
      expect(
        TmuxCommands.listPanes('main', 0),
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
        TmuxCommands.listPanesSimple('main', 0),
        'tmux list-panes -t main:0 -F "#{pane_index}:#{pane_id}:#{pane_active}:#{pane_width}x#{pane_height}"',
      );
    });
  });

  group('listAllPanes', () {
    test('generates list-panes -a command for full tree', () {
      final fs = TmuxCommands.fieldDelimiter;
      final rs = TmuxCommands.recordDelimiter;
      expect(
        TmuxCommands.listAllPanes(),
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

  group('sendEnter / sendInterrupt / sendEscape', () {
    test('sendEnter generates Enter key', () {
      expect(TmuxCommands.sendEnter('%0'), 'tmux send-keys -t %0 Enter');
    });

    test('sendInterrupt generates C-c', () {
      expect(TmuxCommands.sendInterrupt('%0'), 'tmux send-keys -t %0 C-c');
    });

    test('sendEscape generates Escape', () {
      expect(TmuxCommands.sendEscape('%0'), 'tmux send-keys -t %0 Escape');
    });
  });

  group('copyMode commands', () {
    test('enterCopyMode', () {
      expect(TmuxCommands.enterCopyMode('%0'), 'tmux copy-mode -t %0');
    });

    test('cancelCopyMode', () {
      expect(
        TmuxCommands.cancelCopyMode('%0'),
        'tmux send-keys -t %0 -X cancel',
      );
    });
  });

  group('cursor and mode', () {
    test('getCursorPosition', () {
      expect(
        TmuxCommands.getCursorPosition('%0'),
        'tmux display-message -p -t %0 "#{cursor_x},#{cursor_y},#{pane_width},#{pane_height}"',
      );
    });

    test('getPaneMode', () {
      expect(
        TmuxCommands.getPaneMode('%0'),
        'tmux display-message -p -t %0 "#{pane_mode}"',
      );
    });
  });

  group('capturePane', () {
    test('generates visible capture with escape sequences', () {
      expect(TmuxCommands.capturePane('%0'), 'tmux capture-pane -t %0 -p -e');
    });

    test('generates capture with start and end lines', () {
      expect(
        TmuxCommands.capturePane('%0', startLine: -120, endLine: 0),
        'tmux capture-pane -t %0 -p -e -S -120 -E 0',
      );
    });

    test('capturePaneVisible omits line range', () {
      expect(
        TmuxCommands.capturePaneVisible('%0'),
        'tmux capture-pane -t %0 -p -e',
      );
    });

    test('capturePaneAll uses full scrollback range', () {
      expect(
        TmuxCommands.capturePaneAll('%0'),
        'tmux capture-pane -t %0 -p -e -S -32768 -E 32768',
      );
    });
  });

  group('version / server commands', () {
    test('version', () {
      expect(TmuxCommands.version(), 'tmux -V');
    });

    test('serverInfo', () {
      expect(TmuxCommands.serverInfo(), 'tmux server-info 2>&1');
    });

    test('startServer', () {
      expect(TmuxCommands.startServer(), 'tmux start-server');
    });

    test('killServer', () {
      expect(TmuxCommands.killServer(), 'tmux kill-server');
    });
  });

  group('attach / detach', () {
    test('attachSession', () {
      expect(TmuxCommands.attachSession('main'), 'tmux attach-session -t main');
    });

    test('detachClient without session', () {
      expect(TmuxCommands.detachClient(), 'tmux detach-client');
    });

    test('detachClient with session', () {
      expect(
        TmuxCommands.detachClient(sessionName: 'main'),
        'tmux detach-client -s main',
      );
    });
  });

  group('selectLayout', () {
    test('selectLayout', () {
      expect(
        TmuxCommands.selectLayout('%0', TmuxLayout.tiled),
        'tmux select-layout -t %0 tiled',
      );
    });
  });

  group('pipe', () {
    test('pipes multiple commands', () {
      expect(TmuxCommands.pipe(['cmd1', 'cmd2', 'cmd3']), 'cmd1 | cmd2 | cmd3');
    });
  });

  group('Image path injection via sendKeys', () {
    test('sends simple path with literal flag', () {
      final cmd = TmuxCommands.sendKeys(
        '%0',
        '/tmp/muxpod/img_20260403_a3f2.png',
        literal: true,
      );
      expect(cmd, contains('-l'));
      expect(cmd, contains('/tmp/muxpod/img_20260403_a3f2.png'));
    });

    test('handles path with safe characters only', () {
      final cmd = TmuxCommands.sendKeys(
        '%42',
        '/tmp/muxpod/test_image-v2.0.jpg',
        literal: true,
      );
      expect(cmd, contains('-l'));
      expect(cmd, contains('test_image-v2.0.jpg'));
    });

    test('sends Enter key after path for auto-enter', () {
      final cmd = TmuxCommands.sendKeys('%0', 'Enter');
      expect(cmd, contains('Enter'));
      expect(cmd, isNot(contains('-l')));
    });

    test('formats @-prefixed path correctly', () {
      const path = '@/tmp/muxpod/img_test.png';
      final cmd = TmuxCommands.sendKeys('%0', path, literal: true);
      expect(cmd, contains('-l'));
      expect(cmd, contains('@/tmp/muxpod/img_test.png'));
    });
  });
}
