import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/tmux_command_builder.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';
import 'package:flutter_muxpod/services/tmux/tmux_parser_adapter.dart';

import '../../fixtures/tmux/tmux_parser_fixtures.dart';

const _fs = TmuxParser.defaultFieldDelimiter;
const _rs = TmuxParser.defaultRecordDelimiter;

void main() {
  group('TmuxParser', () {
    group('parseSessions', () {
      test('parses detailed session output', () {
        final sessions = TmuxParser.parseSessions(kSessionOutput);
        expect(sessions, hasLength(2));
        expect(sessions[0].name, 'mysession');
        expect(sessions[0].attached, isTrue);
        expect(sessions[0].windowCount, 3);
        expect(sessions[0].id, r'$0');
        expect(sessions[1].name, 'other');
        expect(sessions[1].attached, isFalse);
      });

      test('ignores no server running output', () {
        final sessions = TmuxParser.parseSessions(kNoServerOutput);
        expect(sessions, isEmpty);
      });

      test('ignores empty output', () {
        final sessions = TmuxParser.parseSessions(kEmptyOutput);
        expect(sessions, isEmpty);
      });

      test('ignores malformed lines with too few fields', () {
        final sessions = TmuxParser.parseSessions(kMalformedTooFewFields);
        expect(sessions, isEmpty);
      });
    });

    group('parseSessionsSimple', () {
      test('parses simple session output', () {
        final sessions = TmuxParser.parseSessionsSimple(kSessionOutputSimple);
        expect(sessions, hasLength(2));
        expect(sessions[0].name, 'mysession');
        expect(sessions[0].windowCount, 3);
      });

      test('returns empty for no server running', () {
        expect(TmuxParser.parseSessionsSimple(kNoServerOutput), isEmpty);
      });
    });

    group('parseWindows', () {
      test('parses detailed window output', () {
        final windows = TmuxParser.parseWindows(kWindowOutput);
        expect(windows, hasLength(3));
        expect(windows[0].index, 0);
        expect(windows[0].name, 'shell');
        expect(windows[0].active, isTrue);
        expect(windows[0].isCurrent, isFalse);
        expect(windows[1].isCurrent, isTrue);
        expect(windows[2].isZoomed, isTrue);
      });

      test('ignores no server running', () {
        expect(TmuxParser.parseWindows(kNoServerOutput), isEmpty);
      });

      test('target formats session:index', () {
        final windows = TmuxParser.parseWindows(kWindowOutput);
        expect(windows[0].target('mysession'), 'mysession:0');
      });
    });

    group('parseWindowsSimple', () {
      test('parses simple window output', () {
        final windows = TmuxParser.parseWindowsSimple(kWindowOutputSimple);
        expect(windows, hasLength(2));
        expect(windows[0].index, 0);
        expect(windows[0].name, 'shell');
        expect(windows[0].active, isTrue);
        expect(windows[0].paneCount, 2);
      });
    });

    group('parsePanes', () {
      test('parses detailed pane output', () {
        final panes = TmuxParser.parsePanes(kPaneOutput);
        expect(panes, hasLength(2));
        expect(panes[0].index, 0);
        expect(panes[0].id, '%0');
        expect(panes[0].active, isTrue);
        expect(panes[0].currentCommand, 'bash');
        expect(panes[0].width, 80);
        expect(panes[0].height, 24);
        expect(panes[0].cursorX, 0);
        expect(panes[0].cursorY, 0);
      });

      test('second pane has cursor and currentCommand', () {
        final panes = TmuxParser.parsePanes(kPaneOutput);
        expect(panes[1].id, '%1');
        expect(panes[1].active, isFalse);
        expect(panes[1].currentCommand, 'vim');
        expect(panes[1].cursorX, 10);
        expect(panes[1].cursorY, 5);
      });
    });

    group('parsePanesSimple', () {
      test('parses simple pane output', () {
        final panes = TmuxParser.parsePanesSimple(kPaneOutputSimple);
        expect(panes, hasLength(2));
        expect(panes[0].id, '%0');
        expect(panes[0].width, 80);
        expect(panes[0].height, 24);
        expect(panes[0].sizeString, '80x24');
      });
    });

    group('parseFullTree', () {
      test('parses full multi-session tree', () {
        final sessions = TmuxParser.parseFullTree(kFullTreeOutput);
        expect(sessions, hasLength(2));

        final mysession = sessions.firstWhere((s) => s.name == 'mysession');
        expect(mysession.windows, hasLength(1));
        expect(mysession.windows[0].panes, hasLength(2));
        expect(mysession.windows[0].panes[0].currentCommand, 'bash');
        expect(mysession.windows[0].panes[1].currentPath, '/home/user/projects');

        final other = sessions.firstWhere((s) => s.name == 'other');
        expect(other.windows[0].name, 'logs');
        expect(other.windows[0].panes[0].currentCommand, 'tail');
      });

      test('returns empty when no server running', () {
        expect(TmuxParser.parseFullTree(kNoServerOutput), isEmpty);
      });

      test('skips malformed lines', () {
        expect(
          TmuxParser.parseFullTree('one${_fs}two$_rs${kFullTreeOutput.trim()}'),
          hasLength(2),
        );
      });

      test('paneCount is updated from parsed panes', () {
        final sessions = TmuxParser.parseFullTree(kFullTreeOutput);
        final mysession = sessions.firstWhere((s) => s.name == 'mysession');
        expect(mysession.windows[0].paneCount, 2);
      });
    });

    group('parsePaneContent', () {
      test('splits into lines and preserves ANSI', () {
        final content = TmuxParser.parsePaneContent(kPaneContentWithAnsi);
        expect(content.lines, hasLength(2));
        expect(content.lines[0], contains('\x1b[32m'));
        expect(content.hasAnsiColors, isTrue);
        expect(content.width, greaterThan(0));
      });

      test('strips trailing empty lines', () {
        final content = TmuxParser.parsePaneContent(kPaneContentWithTrailingBlank);
        expect(content.lines, hasLength(1));
        expect(content.lines[0], 'line1');
      });
    });

    group('stripAnsiCodes', () {
      test('removes ANSI color codes', () {
        final stripped = TmuxParser.stripAnsiCodes('\x1b[32mhello\x1b[0m');
        expect(stripped, 'hello');
      });

      test('leaves plain text unchanged', () {
        expect(TmuxParser.stripAnsiCodes('plain'), 'plain');
      });
    });

    group('isServerRunning', () {
      test('returns false for known error strings', () {
        expect(TmuxParser.isServerRunning(kNoServerOutput), isFalse);
        expect(TmuxParser.isServerRunning('error connecting'), isFalse);
        expect(TmuxParser.isServerRunning('command not found'), isFalse);
      });

      test('returns true for normal output', () {
        expect(TmuxParser.isServerRunning('session:1:0'), isTrue);
      });
    });

    group('extractError', () {
      test('extracts no server running', () {
        expect(
          TmuxParser.extractError(kNoServerOutput),
          'tmux server is not running',
        );
      });

      test('extracts session not found', () {
        expect(
          TmuxParser.extractError(kSessionNotFoundOutput),
          'Session not found',
        );
      });

      test('extracts pane not found', () {
        expect(
          TmuxParser.extractError("can't find pane %0"),
          'Pane not found',
        );
      });

      test('returns null for normal output', () {
        expect(TmuxParser.extractError('session:1:0'), isNull);
      });
    });

    group('DTO', () {
      test('TmuxSession copyWith', () {
        const session = TmuxSession(name: 'main');
        final updated = session.copyWith(windowCount: 5);
        expect(updated.windowCount, 5);
        expect(updated.name, 'main');
      });

      test('TmuxSession equality uses name', () {
        const s1 = TmuxSession(name: 'main');
        const s2 = TmuxSession(name: 'main');
        const s3 = TmuxSession(name: 'other');
        expect(s1 == s2, isTrue);
        expect(s1 == s3, isFalse);
      });

      test('TmuxWindow copyWith', () {
        final window = TmuxWindow(index: 0, name: 'shell');
        final updated = window.copyWith(name: 'build');
        expect(updated.name, 'build');
        expect(updated.index, 0);
      });

      test('TmuxWindow isCurrent and isZoomed', () {
        final w1 = TmuxWindow(
          index: 0,
          name: 'shell',
          flags: {TmuxWindowFlag.current, TmuxWindowFlag.zoomed},
        );
        expect(w1.isCurrent, isTrue);
        expect(w1.isZoomed, isTrue);
      });

      test('TmuxPane copyWith updates cursor', () {
        const pane = TmuxPane(index: 0, id: '%0');
        final updated = pane.copyWith(cursorX: 10, cursorY: 5);
        expect(updated.cursorX, 10);
        expect(updated.cursorY, 5);
      });

      test('TmuxPane sizeString', () {
        const pane = TmuxPane(index: 0, id: '%0', width: 120, height: 30);
        expect(pane.sizeString, '120x30');
      });

      test('TmuxPaneContent plainText strips ANSI', () {
        const content = TmuxPaneContent(
          lines: ['\x1b[32mhello\x1b[0m', 'world'],
          width: 80,
          height: 2,
          hasAnsiColors: true,
        );
        expect(content.plainText, 'hello\nworld');
        expect(content.rawText, '\x1b[32mhello\x1b[0m\nworld');
      });

      test('TmuxPaneContent isEmpty', () {
        const content = TmuxPaneContent(
          lines: ['', '  '],
          width: 80,
          height: 2,
        );
        expect(content.isEmpty, isTrue);
      });

      test('TmuxLayout.name', () {
        expect(TmuxLayout.evenHorizontal.name, 'even-horizontal');
        expect(TmuxLayout.evenVertical.name, 'even-vertical');
        expect(TmuxLayout.mainHorizontal.name, 'main-horizontal');
        expect(TmuxLayout.mainVertical.name, 'main-vertical');
        expect(TmuxLayout.tiled.name, 'tiled');
      });
    });
  });
}
