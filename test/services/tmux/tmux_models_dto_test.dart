// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';
import 'package:flutter_muxpod/services/tmux/commands/layout.dart';

void main() {
  group('TmuxParser', () {
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
  });
}
