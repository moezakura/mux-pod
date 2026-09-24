// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/commands/session_commands.dart';

void main() {
  group('TmuxCommands', () {
    group('killSession', () {
      test('generates correct kill-session command', () {
        expect(
          TmuxSessionCommands.kill('my-session'),
          'tmux kill-session -t my-session',
        );
      });

      test('escapes session name with spaces', () {
        expect(
          TmuxSessionCommands.kill('my session'),
          'tmux kill-session -t "my session"',
        );
      });
    });
  });

  group('hasSession', () {
    test('generates has-session check command', () {
      expect(
        TmuxSessionCommands.has('main'),
        'tmux has-session -t main 2>/dev/null && echo "1" || echo "0"',
      );
    });

    test('escapes session name with spaces', () {
      expect(
        TmuxSessionCommands.has('my session'),
        'tmux has-session -t "my session" 2>/dev/null && echo "1" || echo "0"',
      );
    });
  });

  group('newSession', () {
    test('generates new-session command detached by default', () {
      expect(
        TmuxSessionCommands.create(name: 'main'),
        'tmux new-session -d -s main',
      );
    });

    test('generates new-session command without detached flag', () {
      expect(
        TmuxSessionCommands.create(name: 'main', detached: false),
        'tmux new-session -s main',
      );
    });

    test('includes window name and start directory', () {
      expect(
        TmuxSessionCommands.create(
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
        TmuxSessionCommands.rename('old', 'new'),
        'tmux rename-session -t old new',
      );
    });

    test('escapes names with spaces', () {
      expect(
        TmuxSessionCommands.rename('old sess', 'new sess'),
        'tmux rename-session -t "old sess" "new sess"',
      );
    });
  });

  group('version / server commands', () {
    test('version', () {
      expect(TmuxSessionCommands.version(), 'tmux -V');
    });

    test('serverInfo', () {
      expect(TmuxSessionCommands.serverInfo(), 'tmux server-info 2>&1');
    });

    test('startServer', () {
      expect(TmuxSessionCommands.startServer(), 'tmux start-server');
    });

    test('killServer', () {
      expect(TmuxSessionCommands.killServer(), 'tmux kill-server');
    });
  });

  group('attach / detach', () {
    test('attachSession', () {
      expect(TmuxSessionCommands.attach('main'), 'tmux attach-session -t main');
    });

    test('detachClient without session', () {
      expect(TmuxSessionCommands.detach(), 'tmux detach-client');
    });

    test('detachClient with session', () {
      expect(
        TmuxSessionCommands.detach(sessionName: 'main'),
        'tmux detach-client -s main',
      );
    });
  });
}
