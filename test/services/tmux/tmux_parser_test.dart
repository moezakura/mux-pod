// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/tmux_command_builder.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';
import 'package:flutter_muxpod/services/tmux/tmux_parser_adapter.dart';

import '../../fixtures/tmux/tmux_parser_fixtures.dart';

const _fs = TmuxParser.defaultFieldDelimiter;
const _rs = TmuxParser.defaultRecordDelimiter;

void main() {
  group('TmuxParser', () {
    test(
      'TMUX-PARSER-001: deprecated defaultDelimiter remains the US delimiter',
      () {
        expect(TmuxParser.defaultDelimiter, String.fromCharCode(0x1f));
        expect(TmuxParser.defaultDelimiter, TmuxParser.defaultFieldDelimiter);
      },
    );

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

      test(
        'TMUX-DTO-004 and TMUX-PARSER-014: parses Unix seconds into created',
        () {
          final session = TmuxParser.parseSessions(kSessionOutput).first;

          expect(
            session.created,
            DateTime.fromMillisecondsSinceEpoch(1735689600000),
          );
        },
      );

      test(
        'TMUX-PARSER-014: invalid Unix seconds result in a null created value',
        () {
          final session = TmuxParser.parseSessionLine(
            'main$_fs'
            'not-a-timestamp$_fs'
            '0$_fs'
            '1$_fs\$0',
          );

          expect(session, isNotNull);
          expect(session!.created, isNull);
        },
      );
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

      test('TMUX-DTO-013 and TMUX-DTO-017: preserves id and parsed flags', () {
        final windows = TmuxParser.parseWindows(kWindowOutput);

        expect(windows[2].id, '@2');
        expect(windows[2].flags, {
          TmuxWindowFlag.current,
          TmuxWindowFlag.zoomed,
        });
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

      test('TMUX-DTO-028: preserves pane title', () {
        final pane = TmuxParser.parsePanes(kPaneOutput).first;

        expect(pane.title, 'shell-title');
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
        expect(
          mysession.windows[0].panes[1].currentPath,
          '/home/user/projects',
        );

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

      test(
        'preserves pane current working directories from full-tree output',
        () {
          final sessions = TmuxParser.parseFullTree(kFullTreeOutput);
          final shellPanes = sessions.first.windows.first.panes;

          expect(shellPanes[0].currentPath, '/home/user');
          expect(shellPanes[1].currentPath, '/home/user/projects');
        },
      );

      test('TMUX-GEOM-003 and TMUX-GEOM-004: preserves pane position', () {
        final panes = TmuxParser.parseFullTree(
          kFullTreeOutput,
        ).first.windows.first.panes;

        expect(panes[1].left, 80);
        expect(panes[1].top, 0);
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
        final content = TmuxParser.parsePaneContent(
          kPaneContentWithTrailingBlank,
        );
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
        expect(TmuxParser.extractError("can't find pane %0"), 'Pane not found');
      });

      test('returns null for normal output', () {
        expect(TmuxParser.extractError('session:1:0'), isNull);
      });
    });

    group('DTO', () {
      test('deprecated tmux aliases preserve their concrete DTO types', () {
        final TmuxSessionInfo session = TmuxSession(name: 'main');
        final TmuxWindowInfo window = TmuxWindow(index: 1, name: 'shell');
        final TmuxPaneInfo pane = TmuxPane(index: 2, id: '%2');

        expect(session, isA<TmuxSession>());
        expect(window, isA<TmuxWindow>());
        expect(pane, isA<TmuxPane>());
      });
      test('TmuxSession copyWith', () {
        const session = TmuxSession(name: 'main');
        final updated = session.copyWith(windowCount: 5);
        expect(updated.windowCount, 5);
        expect(updated.name, 'main');
      });

      test('TMUX-DTO-009: session target is its name', () {
        const session = TmuxSession(name: 'main');

        expect(session.target, 'main');
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

      test('TMUX-DTO-029: pane target is its id', () {
        const pane = TmuxPane(index: 0, id: '%42');

        expect(pane.target, '%42');
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

      test('TMUX-DTO-035: pane content retains its declared height', () {
        const content = TmuxPaneContent(
          lines: ['first', 'second'],
          width: 80,
          height: 2,
        );

        expect(content.height, 2);
      });

      test('TmuxLayout.name', () {
        expect(TmuxLayout.evenHorizontal.name, 'even-horizontal');
        expect(TmuxLayout.evenVertical.name, 'even-vertical');
        expect(TmuxLayout.mainHorizontal.name, 'main-horizontal');
        expect(TmuxLayout.mainVertical.name, 'main-vertical');
        expect(TmuxLayout.tiled.name, 'tiled');
      });
    });

    group('normalizeDelimiters', () {
      test('TMUX-PARSER-020: converts literal \\x1f/\\x1e to control chars', () {
        const literal =
            'sess\\x1f123\\x1f0\\x1f2\\x1f\$0\\x1eother\\x1f456\\x1f1\\x1f1\\x1f\$1\\x1e';
        final normalized = TmuxParser.normalizeDelimiters(literal);
        expect(normalized.contains(_fs), isTrue);
        expect(normalized.contains(_rs), isTrue);
        expect(normalized.contains(r'\x1f'), isFalse);
        expect(normalized.contains(r'\x1e'), isFalse);
      });

      test(
        'TMUX-PARSER-020: converts octal literal \\037/\\036 to control chars',
        () {
          const literal =
              'sess\\037123\\0370\\0372\\037\$0\\036other\\037456\\0371\\0371\\037\$1\\036';
          final normalized = TmuxParser.normalizeDelimiters(literal);
          expect(normalized.contains(_fs), isTrue);
          expect(normalized.contains(_rs), isTrue);
          expect(normalized.contains(r'\037'), isFalse);
          expect(normalized.contains(r'\036'), isFalse);
        },
      );

      test('TMUX-PARSER-020: leaves real control chars untouched', () {
        final literal = 'sess$_fs"123"$_fs"0"$_fs"2"$_fs"\$0"$_rs"other"';
        final normalized = TmuxParser.normalizeDelimiters(literal);
        expect(normalized, literal);
      });

      test(
        'TMUX-PARSER-002: parseSessions handles literal separator output',
        () {
          // SSH シェル経由で tmux -F の制御文字がリテラル表記に化けたケース。
          const literalOutput =
              'mysession\\x1f1735689600\\x1f1\\x1f3\\x1f\$0\\x1e'
              'other\\x1f1735690000\\x1f0\\x1f1\\x1f\$1\\x1e';
          final sessions = TmuxParser.parseSessions(literalOutput);
          expect(sessions, hasLength(2));
          expect(sessions[0].name, 'mysession');
          expect(sessions[0].attached, isTrue);
          expect(sessions[0].windowCount, 3);
          expect(sessions[0].id, r'$0');
          expect(sessions[1].name, 'other');
        },
      );

      test(
        'TMUX-PARSER-002: parseSessions handles octal literal separator output',
        () {
          const octalOutput =
              'mysession\\0371735689600\\0371\\0373\\037\$0\\036'
              'other\\0371735690000\\0370\\0371\\037\$1\\036';
          final sessions = TmuxParser.parseSessions(octalOutput);
          expect(sessions, hasLength(2));
          expect(sessions[0].name, 'mysession');
          expect(sessions[0].windowCount, 3);
        },
      );
    });
  });
}
