// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/parsers/window_parser.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';
import '../../fixtures/tmux/tmux_parser_fixtures.dart';

void main() {
  group('TmuxParser', () {
    group('parseWindows', () {
      test('parses detailed window output', () {
        final windows = TmuxWindowParser.parse(kWindowOutput);
        expect(windows, hasLength(3));
        expect(windows[0].index, 0);
        expect(windows[0].name, 'shell');
        expect(windows[0].active, isTrue);
        expect(windows[0].isCurrent, isFalse);
        expect(windows[1].isCurrent, isTrue);
        expect(windows[2].isZoomed, isTrue);
      });

      test('ignores no server running', () {
        expect(TmuxWindowParser.parse(kNoServerOutput), isEmpty);
      });

      test('target formats session:index', () {
        final windows = TmuxWindowParser.parse(kWindowOutput);
        expect(windows[0].target('mysession'), 'mysession:0');
      });

      test('TMUX-DTO-013 and TMUX-DTO-017: preserves id and parsed flags', () {
        final windows = TmuxWindowParser.parse(kWindowOutput);

        expect(windows[2].id, '@2');
        expect(windows[2].flags, {
          TmuxWindowFlag.current,
          TmuxWindowFlag.zoomed,
        });
      });
    });

    group('parseWindowsSimple', () {
      test('parses simple window output', () {
        final windows = TmuxWindowParser.parseSimple(kWindowOutputSimple);
        expect(windows, hasLength(2));
        expect(windows[0].index, 0);
        expect(windows[0].name, 'shell');
        expect(windows[0].active, isTrue);
        expect(windows[0].paneCount, 2);
      });
    });
  });
}
