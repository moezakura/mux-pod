import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/widgets/special_keys_tmux_composer.dart';

/// SpecialKeysTmuxComposer の純粋部（composeSpecial / composeLiteral /
/// hwSpecialKeyMap）の単体テスト。
/// applyHardwareModifiers は HardwareKeyboard.instance 依存のため対象外
/// （設計書 v2-3: Widget テストで sendKeyDownEvent により検証する）。
void main() {
  const composer = SpecialKeysTmuxComposer();

  group('SpecialKeysTmuxComposer.composeSpecial', () {
    test('returns base key when no modifier is active', () {
      expect(
        composer.composeSpecial('Enter', shift: false, ctrl: false, alt: false),
        'Enter',
      );
      expect(
        composer.composeSpecial(
          'Escape',
          shift: false,
          ctrl: false,
          alt: false,
        ),
        'Escape',
      );
    });

    test('prefixes modifiers in S, C, M order', () {
      expect(
        composer.composeSpecial('a', shift: true, ctrl: true, alt: true),
        'S-C-M-a',
      );
      expect(
        composer.composeSpecial('x', shift: false, ctrl: true, alt: false),
        'C-x',
      );
      expect(
        composer.composeSpecial('x', shift: false, ctrl: true, alt: true),
        'C-M-x',
      );
      expect(
        composer.composeSpecial('Enter', shift: true, ctrl: false, alt: false),
        'S-Enter',
      );
    });

    test('Shift+Tab maps to BTab (Back Tab) regardless of other modifiers', () {
      expect(
        composer.composeSpecial('Tab', shift: true, ctrl: false, alt: false),
        'BTab',
      );
      expect(
        composer.composeSpecial('Tab', shift: true, ctrl: true, alt: true),
        'BTab',
      );
    });

    test('Tab without shift keeps its modifiers', () {
      expect(
        composer.composeSpecial('Tab', shift: false, ctrl: true, alt: false),
        'C-Tab',
      );
      expect(
        composer.composeSpecial('Tab', shift: false, ctrl: false, alt: false),
        'Tab',
      );
    });
  });

  group('SpecialKeysTmuxComposer.composeLiteral', () {
    test('returns null without modifiers (literal send)', () {
      expect(
        composer.composeLiteral('/', shift: false, ctrl: false, alt: false),
        isNull,
      );
    });

    test('returns null for multi-char keys even with modifiers', () {
      expect(
        composer.composeLiteral('ab', shift: true, ctrl: false, alt: false),
        isNull,
      );
    });

    test('composes single-char keys with modifiers in S, C, M order', () {
      expect(
        composer.composeLiteral('a', shift: true, ctrl: true, alt: true),
        'S-C-M-a',
      );
      expect(
        composer.composeLiteral('1', shift: false, ctrl: true, alt: false),
        'C-1',
      );
      expect(
        composer.composeLiteral('-', shift: false, ctrl: false, alt: true),
        'M--',
      );
    });
  });

  group('SpecialKeysTmuxComposer.hwSpecialKeyMap', () {
    test('maps external-keyboard keys to tmux names', () {
      final map = SpecialKeysTmuxComposer.hwSpecialKeyMap;
      expect(map[LogicalKeyboardKey.escape], 'Escape');
      expect(map[LogicalKeyboardKey.tab], 'Tab');
      expect(map[LogicalKeyboardKey.arrowUp], 'Up');
      expect(map[LogicalKeyboardKey.arrowDown], 'Down');
      expect(map[LogicalKeyboardKey.arrowLeft], 'Left');
      expect(map[LogicalKeyboardKey.arrowRight], 'Right');
      expect(map[LogicalKeyboardKey.home], 'Home');
      expect(map[LogicalKeyboardKey.end], 'End');
      expect(map[LogicalKeyboardKey.pageUp], 'PPage');
      expect(map[LogicalKeyboardKey.pageDown], 'NPage');
      expect(map[LogicalKeyboardKey.delete], 'DC');
      expect(map[LogicalKeyboardKey.f1], 'F1');
      expect(map[LogicalKeyboardKey.f12], 'F12');
    });
  });
}
