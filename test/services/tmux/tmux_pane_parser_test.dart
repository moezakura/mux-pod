// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/parsers/pane_parser.dart';
import '../../fixtures/tmux/tmux_parser_fixtures.dart';

void main() {
  group('TmuxParser', () {
    group('parsePanes', () {
      test('parses detailed pane output', () {
        final panes = TmuxPaneParser.parse(kPaneOutput);
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
        final panes = TmuxPaneParser.parse(kPaneOutput);
        expect(panes[1].id, '%1');
        expect(panes[1].active, isFalse);
        expect(panes[1].currentCommand, 'vim');
        expect(panes[1].cursorX, 10);
        expect(panes[1].cursorY, 5);
      });

      test('TMUX-DTO-028: preserves pane title', () {
        final pane = TmuxPaneParser.parse(kPaneOutput).first;

        expect(pane.title, 'shell-title');
      });
    });

    group('parsePanesSimple', () {
      test('parses simple pane output', () {
        final panes = TmuxPaneParser.parseSimple(kPaneOutputSimple);
        expect(panes, hasLength(2));
        expect(panes[0].id, '%0');
        expect(panes[0].width, 80);
        expect(panes[0].height, 24);
        expect(panes[0].sizeString, '80x24');
      });
    });
  });
}
