import 'package:flutter_muxpod/services/backend/domain/pane_writer.dart';
import 'package:flutter_muxpod/services/herdr/herdr_keymap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaneKeyMap: ① send-keys 受理キー（T0 実測 1-a: 21 種）', () {
    test('function keys F1-F12 route to send-keys', () {
      for (final key in [
        'F1',
        'F2',
        'F3',
        'F4',
        'F5',
        'F6',
        'F7',
        'F8',
        'F9',
        'F10',
        'F11',
        'F12',
      ]) {
        final route = PaneKeyMap.mapSpecialKey(key);
        expect(route, isA<HerdrKeyRouteSendKeys>(), reason: key);
        expect((route as HerdrKeyRouteSendKeys).keyName, key);
      }
    });

    test('basic keys route to send-keys', () {
      for (final entry in {
        'Enter': 'Enter',
        'Tab': 'Tab',
        'Space': 'Space',
        'Backspace': 'Backspace',
        'BS': 'BS',
        'Escape': 'Escape',
      }.entries) {
        final route = PaneKeyMap.mapSpecialKey(entry.key);
        expect(route, isA<HerdrKeyRouteSendKeys>(), reason: entry.key);
        expect((route as HerdrKeyRouteSendKeys).keyName, entry.value);
      }
    });

    test('tmux BSpace is normalized to the accepted Backspace', () {
      final route = PaneKeyMap.mapSpecialKey('BSpace');
      expect(route, isA<HerdrKeyRouteSendKeys>());
      expect((route as HerdrKeyRouteSendKeys).keyName, 'Backspace');
    });

    test('arrow keys route to send-keys', () {
      for (final key in ['Up', 'Down', 'Left', 'Right']) {
        final route = PaneKeyMap.mapSpecialKey(key);
        expect(route, isA<HerdrKeyRouteSendKeys>(), reason: key);
        expect((route as HerdrKeyRouteSendKeys).keyName, key);
      }
    });

    test('C-c is the only accepted control key (Q-03)', () {
      for (final key in ['C-c', 'c-c']) {
        final route = PaneKeyMap.mapSpecialKey(key);
        expect(route, isA<HerdrKeyRouteSendKeys>(), reason: key);
        expect((route as HerdrKeyRouteSendKeys).keyName, key);
      }
    });
  });

  group('PaneKeyMap: ② send-keys 拒否キー → send-text エスケープ（T0 実測②）', () {
    test('unmodified reject keys use the measured escape sequences', () {
      for (final entry in {
        'Home': '\x1b[H',
        'End': '\x1b[F',
        'PPage': '\x1b[5~',
        'NPage': '\x1b[6~',
        'DC': '\x1b[3~',
        'Insert': '\x1b[2~',
        'BTab': '\x1b[Z',
      }.entries) {
        final route = PaneKeyMap.mapSpecialKey(entry.key);
        expect(route, isA<HerdrKeyRouteSendTextEscape>(), reason: entry.key);
        expect(
          (route as HerdrKeyRouteSendTextEscape).bytes,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('reject-key alternative spellings normalize to the same sequence', () {
      for (final entry in {
        'PageUp': '\x1b[5~',
        'PgUp': '\x1b[5~',
        'PageDown': '\x1b[6~',
        'PgDn': '\x1b[6~',
        'Delete': '\x1b[3~',
        'Del': '\x1b[3~',
        'Ins': '\x1b[2~',
      }.entries) {
        final route = PaneKeyMap.mapSpecialKey(entry.key);
        expect(route, isA<HerdrKeyRouteSendTextEscape>(), reason: entry.key);
        expect((route as HerdrKeyRouteSendTextEscape).bytes, entry.value);
      }
    });

    test('modified arrow keys use xterm modifier encoding (T0 実測②)', () {
      for (final entry in {
        'S-Up': '\x1b[1;2A',
        'C-Up': '\x1b[1;5A',
        'M-Up': '\x1b[1;3A',
        'S-Down': '\x1b[1;2B',
        'C-Down': '\x1b[1;5B',
        'M-Down': '\x1b[1;3B',
        'S-Right': '\x1b[1;2C',
        'C-Right': '\x1b[1;5C',
        'M-Right': '\x1b[1;3C',
        'S-Left': '\x1b[1;2D',
        'C-Left': '\x1b[1;5D',
        'M-Left': '\x1b[1;3D',
      }.entries) {
        final route = PaneKeyMap.mapSpecialKey(entry.key);
        expect(route, isA<HerdrKeyRouteSendTextEscape>(), reason: entry.key);
        expect((route as HerdrKeyRouteSendTextEscape).bytes, entry.value);
      }
    });

    test('modified Home/End use xterm modifier encoding', () {
      for (final entry in {
        'S-Home': '\x1b[1;2H',
        'C-Home': '\x1b[1;5H',
        'M-Home': '\x1b[1;3H',
        'S-End': '\x1b[1;2F',
        'C-End': '\x1b[1;5F',
        'M-End': '\x1b[1;3F',
      }.entries) {
        final route = PaneKeyMap.mapSpecialKey(entry.key);
        expect(route, isA<HerdrKeyRouteSendTextEscape>(), reason: entry.key);
        expect((route as HerdrKeyRouteSendTextEscape).bytes, entry.value);
      }
    });

    test(
      'modified PgUp/PgDn/Delete/Insert use CSI param modifier encoding',
      () {
        for (final entry in {
          'S-PPage': '\x1b[5;2~',
          'C-PageUp': '\x1b[5;5~',
          'M-PageUp': '\x1b[5;3~',
          'S-NPage': '\x1b[6;2~',
          'C-PageDown': '\x1b[6;5~',
          'M-PageDown': '\x1b[6;3~',
          'C-Delete': '\x1b[3;5~',
          'S-DC': '\x1b[3;2~',
          'M-DC': '\x1b[3;3~',
          'C-Insert': '\x1b[2;5~',
        }.entries) {
          final route = PaneKeyMap.mapSpecialKey(entry.key);
          expect(route, isA<HerdrKeyRouteSendTextEscape>(), reason: entry.key);
          expect((route as HerdrKeyRouteSendTextEscape).bytes, entry.value);
        }
      },
    );

    test('modified function keys use xterm encoding', () {
      for (final entry in {
        'S-F1': '\x1b[1;2P',
        'C-F4': '\x1b[1;5S',
        'M-F2': '\x1b[1;3Q',
        'S-F5': '\x1b[15;2~',
        'C-F5': '\x1b[15;5~',
        'M-F10': '\x1b[21;3~',
        'S-F12': '\x1b[24;2~',
      }.entries) {
        final route = PaneKeyMap.mapSpecialKey(entry.key);
        expect(route, isA<HerdrKeyRouteSendTextEscape>(), reason: entry.key);
        expect((route as HerdrKeyRouteSendTextEscape).bytes, entry.value);
      }
    });

    test('S-Tab uses CSI Z (back tab)', () {
      final route = PaneKeyMap.mapSpecialKey('S-Tab');
      expect(route, isA<HerdrKeyRouteSendTextEscape>());
      expect((route as HerdrKeyRouteSendTextEscape).bytes, '\x1b[Z');
    });

    test('modified Enter/Tab/Space/Backspace use xterm 27-sequence', () {
      for (final entry in {
        'S-Enter': '\x1b[27;2;13~',
        'C-Enter': '\x1b[27;5;13~',
        'M-Enter': '\x1b[27;3;13~',
        'C-Tab': '\x1b[27;5;9~',
        'C-Space': null, // C-Space は制御文字 0x00（下記 group で検証）
        'C-Backspace': '\x1b[27;5;8~',
        'M-Backspace': '\x1b[27;3;8~',
      }.entries) {
        final bytes = entry.value;
        if (bytes == null) continue;
        final route = PaneKeyMap.mapSpecialKey(entry.key);
        expect(route, isA<HerdrKeyRouteSendTextEscape>(), reason: entry.key);
        expect((route as HerdrKeyRouteSendTextEscape).bytes, bytes);
      }
    });

    test('Alt+letter is ESC + letter', () {
      final route = PaneKeyMap.mapSpecialKey('M-a');
      expect(route, isA<HerdrKeyRouteSendTextEscape>());
      expect((route as HerdrKeyRouteSendTextEscape).bytes, '\x1ba');
    });

    test('Shift+letter sends the uppercase letter', () {
      final route = PaneKeyMap.mapSpecialKey('S-a');
      expect(route, isA<HerdrKeyRouteSendTextEscape>());
      expect((route as HerdrKeyRouteSendTextEscape).bytes, 'A');
    });

    test('combined modifiers combine ESC prefix and control byte', () {
      final route = PaneKeyMap.mapSpecialKey('C-M-a');
      expect(route, isA<HerdrKeyRouteSendTextEscape>());
      // Alt+Ctrl+a = ESC + C-a（0x01）。
      expect((route as HerdrKeyRouteSendTextEscape).bytes, '\x1b\x01');
    });
  });

  group('PaneKeyMap: ③ 制御文字 → send-text 制御バイト（T0 実測③）', () {
    test('C-<letter> except C-c maps to its control byte', () {
      for (final entry in {
        'C-a': 0x01,
        'C-b': 0x02,
        'C-d': 0x04,
        'C-e': 0x05,
        'C-f': 0x06,
        'C-g': 0x07,
        'C-h': 0x08,
        'C-k': 0x0b,
        'C-l': 0x0c,
        'C-n': 0x0e,
        'C-o': 0x0f,
        'C-p': 0x10,
        'C-q': 0x11,
        'C-r': 0x12,
        'C-s': 0x13,
        'C-t': 0x14,
        'C-u': 0x15,
        'C-v': 0x16,
        'C-w': 0x17,
        'C-x': 0x18,
        'C-y': 0x19,
        'C-z': 0x1a,
      }.entries) {
        final route = PaneKeyMap.mapSpecialKey(entry.key);
        expect(route, isA<HerdrKeyRouteSendTextControl>(), reason: entry.key);
        expect((route as HerdrKeyRouteSendTextControl).byte, entry.value);
      }
    });

    test('uppercase C-<letter> maps to the same control byte', () {
      final route = PaneKeyMap.mapSpecialKey('C-D');
      expect(route, isA<HerdrKeyRouteSendTextControl>());
      expect((route as HerdrKeyRouteSendTextControl).byte, 0x04);
    });

    test('special control characters map to raw bytes', () {
      for (final entry in {
        'C-@': 0x00,
        'C-Space': 0x00,
        'C-[': 0x1b,
        r'C-\': 0x1c,
        'C-]': 0x1d,
        'C-^': 0x1e,
        'C-_': 0x1f,
        'C-?': 0x7f,
      }.entries) {
        final route = PaneKeyMap.mapSpecialKey(entry.key);
        expect(route, isA<HerdrKeyRouteSendTextControl>(), reason: entry.key);
        expect((route as HerdrKeyRouteSendTextControl).byte, entry.value);
      }
    });
  });

  group('PaneKeyMap: 全キーで送信経路が返る（Q-07）', () {
    test('the complete app key vocabulary always returns a route', () {
      final keys = <String>[
        // 受理キー（21 種）
        ...[
          'F1',
          'F2',
          'F3',
          'F4',
          'F5',
          'F6',
          'F7',
          'F8',
          'F9',
          'F10',
          'F11',
          'F12',
        ],
        'Enter', 'Tab', 'Space', 'Backspace', 'BS', 'BSpace', 'Escape',
        'Up', 'Down', 'Left', 'Right',
        'C-c', 'c-c',
        // 拒否キー
        'Home', 'End', 'PPage', 'NPage', 'DC', 'Insert', 'BTab',
        'PageUp', 'PageDown', 'PgUp', 'PgDn', 'Delete', 'Del', 'Ins',
        // 修飾キー（S / C / M × 全ベース）
        for (final mod in ['S', 'C', 'M'])
          for (final base in [
            'Up',
            'Down',
            'Left',
            'Right',
            'Home',
            'End',
            'PPage',
            'NPage',
            'DC',
            'Insert',
            'Tab',
            'Enter',
            'Space',
            'Backspace',
            'F1',
            'F2',
            'F3',
            'F4',
            'F5',
            'F6',
            'F7',
            'F8',
            'F9',
            'F10',
            'F11',
            'F12',
          ])
            '$mod-$base',
        // 制御文字
        for (final letter in 'abcdefghijklmnopqrstuvwxyz'.split(''))
          'C-$letter',
        'C-@', 'C-Space', 'C-[', r'C-\', 'C-]', 'C-^', 'C-_', 'C-?',
        // Alt+文字
        for (final letter in 'abcdefghijklmnopqrstuvwxyz'.split(''))
          'M-$letter',
        // 合成修飾
        'S-C-M-F5',
        'C-M-a',
        'S-C-Up',
      ];

      for (final key in keys) {
        // 必ず何らかの送信経路が返る（throw しない）。
        final route = PaneKeyMap.mapSpecialKey(key);
        expect(route, isA<HerdrKeyRoute>(), reason: key);
      }
    });

    test('sendKeys fallback covers genuinely unknown keys (defensive)', () {
      final route = PaneKeyMap.mapSpecialKey('UnknownKey123');
      expect(route, isA<HerdrKeyRouteSendKeys>());
      expect((route as HerdrKeyRouteSendKeys).keyName, 'UnknownKey123');
    });
  });
}
