// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/parsers/content_parser.dart';
import '../../fixtures/tmux/tmux_parser_fixtures.dart';

void main() {
  group('TmuxParser', () {
    group('parsePaneContent', () {
      test('splits into lines and preserves ANSI', () {
        final content = TmuxContentParser.parse(kPaneContentWithAnsi);
        expect(content.lines, hasLength(2));
        expect(content.lines[0], contains('\x1b[32m'));
        expect(content.hasAnsiColors, isTrue);
        expect(content.width, greaterThan(0));
      });

      test('strips trailing empty lines', () {
        final content = TmuxContentParser.parse(kPaneContentWithTrailingBlank);
        expect(content.lines, hasLength(1));
        expect(content.lines[0], 'line1');
      });
    });

    group('stripAnsiCodes', () {
      test('removes ANSI color codes', () {
        final stripped = TmuxContentParser.stripAnsi('\x1b[32mhello\x1b[0m');
        expect(stripped, 'hello');
      });

      test('leaves plain text unchanged', () {
        expect(TmuxContentParser.stripAnsi('plain'), 'plain');
      });
    });
  });
}
