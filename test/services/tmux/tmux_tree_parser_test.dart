// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/parsers/tree_parser.dart';
import '../../fixtures/tmux/tmux_parser_fixtures.dart';
import 'helpers/tmux_parser_shared.dart';

void main() {
  group('TmuxParser', () {
    group('parseFullTree', () {
      test('parses full multi-session tree', () {
        final sessions = TmuxTreeParser.parse(kFullTreeOutput);
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
        expect(TmuxTreeParser.parse(kNoServerOutput), isEmpty);
      });

      test('skips malformed lines', () {
        expect(
          TmuxTreeParser.parse(
            'one${kLegacyField}two$kLegacyRecord${kFullTreeOutput.trim()}',
          ),
          hasLength(2),
        );
      });

      test('paneCount is updated from parsed panes', () {
        final sessions = TmuxTreeParser.parse(kFullTreeOutput);
        final mysession = sessions.firstWhere((s) => s.name == 'mysession');
        expect(mysession.windows[0].paneCount, 2);
      });

      test(
        'preserves pane current working directories from full-tree output',
        () {
          final sessions = TmuxTreeParser.parse(kFullTreeOutput);
          final shellPanes = sessions.first.windows.first.panes;

          expect(shellPanes[0].currentPath, '/home/user');
          expect(shellPanes[1].currentPath, '/home/user/projects');
        },
      );

      test('TMUX-GEOM-003 and TMUX-GEOM-004: preserves pane position', () {
        final panes = TmuxTreeParser.parse(
          kFullTreeOutput,
        ).first.windows.first.panes;

        expect(panes[1].left, 80);
        expect(panes[1].top, 0);
      });
    });
  });
}
