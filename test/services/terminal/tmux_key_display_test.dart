import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/terminal/tmux_key_display.dart';

void main() {
  group('TmuxKeyDisplay.categoryOf', () {
    group('modifier keys', () {
      test('Ctrl+letter returns modifier', () {
        expect(TmuxKeyDisplay.categoryOf('C-c'), KeyOverlayCategory.modifier);
        expect(TmuxKeyDisplay.categoryOf('C-a'), KeyOverlayCategory.modifier);
        expect(TmuxKeyDisplay.categoryOf('C-z'), KeyOverlayCategory.modifier);
      });

      test('Alt+letter returns modifier', () {
        expect(TmuxKeyDisplay.categoryOf('M-x'), KeyOverlayCategory.modifier);
        expect(TmuxKeyDisplay.categoryOf('M-a'), KeyOverlayCategory.modifier);
      });

      test('Shift+letter returns modifier', () {
        expect(TmuxKeyDisplay.categoryOf('S-a'), KeyOverlayCategory.modifier);
        expect(TmuxKeyDisplay.categoryOf('S-z'), KeyOverlayCategory.modifier);
      });

      test('compound modifiers return modifier', () {
        expect(TmuxKeyDisplay.categoryOf('C-M-a'), KeyOverlayCategory.modifier);
        expect(TmuxKeyDisplay.categoryOf('C-S-x'), KeyOverlayCategory.modifier);
      });
    });

    group('special keys', () {
      test('Escape returns special', () {
        expect(TmuxKeyDisplay.categoryOf('Escape'), KeyOverlayCategory.special);
      });

      test('Enter returns special', () {
        expect(TmuxKeyDisplay.categoryOf('Enter'), KeyOverlayCategory.special);
      });

      test('Tab returns special', () {
        expect(TmuxKeyDisplay.categoryOf('Tab'), KeyOverlayCategory.special);
      });

      test('S-Enter returns special (not modifier)', () {
        expect(
          TmuxKeyDisplay.categoryOf('S-Enter'),
          KeyOverlayCategory.special,
        );
      });

      test('BSpace returns special', () {
        expect(TmuxKeyDisplay.categoryOf('BSpace'), KeyOverlayCategory.special);
      });

      test('BTab returns special', () {
        expect(TmuxKeyDisplay.categoryOf('BTab'), KeyOverlayCategory.special);
      });
    });

    group('arrow keys', () {
      test('arrow keys return arrow', () {
        expect(TmuxKeyDisplay.categoryOf('Up'), KeyOverlayCategory.arrow);
        expect(TmuxKeyDisplay.categoryOf('Down'), KeyOverlayCategory.arrow);
        expect(TmuxKeyDisplay.categoryOf('Left'), KeyOverlayCategory.arrow);
        expect(TmuxKeyDisplay.categoryOf('Right'), KeyOverlayCategory.arrow);
      });
    });

    group('shortcut keys', () {
      test('shortcut keys return shortcut', () {
        expect(TmuxKeyDisplay.categoryOf('/'), KeyOverlayCategory.shortcut);
        expect(TmuxKeyDisplay.categoryOf('-'), KeyOverlayCategory.shortcut);
        expect(TmuxKeyDisplay.categoryOf('1'), KeyOverlayCategory.shortcut);
        expect(TmuxKeyDisplay.categoryOf('2'), KeyOverlayCategory.shortcut);
        expect(TmuxKeyDisplay.categoryOf('3'), KeyOverlayCategory.shortcut);
        expect(TmuxKeyDisplay.categoryOf('4'), KeyOverlayCategory.shortcut);
      });
    });

    group('unknown keys', () {
      test('regular characters return null', () {
        expect(TmuxKeyDisplay.categoryOf('a'), isNull);
        expect(TmuxKeyDisplay.categoryOf('hello'), isNull);
        expect(TmuxKeyDisplay.categoryOf('!'), isNull);
      });
    });
  });

  group('TmuxKeyDisplay.isShortcutKey', () {
    test('shortcut keys return true', () {
      expect(TmuxKeyDisplay.isShortcutKey('/'), isTrue);
      expect(TmuxKeyDisplay.isShortcutKey('-'), isTrue);
      expect(TmuxKeyDisplay.isShortcutKey('1'), isTrue);
      expect(TmuxKeyDisplay.isShortcutKey('2'), isTrue);
      expect(TmuxKeyDisplay.isShortcutKey('3'), isTrue);
      expect(TmuxKeyDisplay.isShortcutKey('4'), isTrue);
    });

    test('non-shortcut keys return false', () {
      expect(TmuxKeyDisplay.isShortcutKey('a'), isFalse);
      expect(TmuxKeyDisplay.isShortcutKey('5'), isFalse);
      expect(TmuxKeyDisplay.isShortcutKey('Escape'), isFalse);
    });
  });

  group('TmuxKeyDisplay.displayText', () {
    group('modifier keys', () {
      test('Ctrl+letter', () {
        expect(TmuxKeyDisplay.displayText('C-c'), 'Ctrl+C');
        expect(TmuxKeyDisplay.displayText('C-a'), 'Ctrl+A');
      });

      test('Alt+letter', () {
        expect(TmuxKeyDisplay.displayText('M-x'), 'Alt+X');
        expect(TmuxKeyDisplay.displayText('M-a'), 'Alt+A');
      });

      test('Shift+letter', () {
        expect(TmuxKeyDisplay.displayText('S-a'), 'Shift+A');
      });

      test('compound modifiers', () {
        expect(TmuxKeyDisplay.displayText('C-M-a'), 'Ctrl+Alt+A');
      });
    });

    group('special keys', () {
      test('Escape → ESC', () {
        expect(TmuxKeyDisplay.displayText('Escape'), 'ESC');
      });

      test('Enter → ENTER', () {
        expect(TmuxKeyDisplay.displayText('Enter'), 'ENTER');
      });

      test('Tab → TAB', () {
        expect(TmuxKeyDisplay.displayText('Tab'), 'TAB');
      });

      test('S-Enter → Shift+Enter', () {
        expect(TmuxKeyDisplay.displayText('S-Enter'), 'Shift+Enter');
      });

      test('BSpace → BS', () {
        expect(TmuxKeyDisplay.displayText('BSpace'), 'BS');
      });

      test('BTab → Shift+TAB', () {
        expect(TmuxKeyDisplay.displayText('BTab'), 'Shift+TAB');
      });
    });

    group('arrow keys', () {
      test('arrows display as unicode symbols', () {
        expect(TmuxKeyDisplay.displayText('Up'), '↑');
        expect(TmuxKeyDisplay.displayText('Down'), '↓');
        expect(TmuxKeyDisplay.displayText('Left'), '←');
        expect(TmuxKeyDisplay.displayText('Right'), '→');
      });
    });

    group('shortcut keys', () {
      test('literal keys display as-is', () {
        expect(TmuxKeyDisplay.displayText('/'), '/');
        expect(TmuxKeyDisplay.displayText('-'), '-');
        expect(TmuxKeyDisplay.displayText('1'), '1');
        expect(TmuxKeyDisplay.displayText('4'), '4');
      });
    });

    group('unknown keys', () {
      test('unknown keys return as-is', () {
        expect(TmuxKeyDisplay.displayText('DC'), 'DC');
        expect(TmuxKeyDisplay.displayText('F1'), 'F1');
      });
    });
  });
}
