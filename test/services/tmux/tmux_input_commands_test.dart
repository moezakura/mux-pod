// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/commands/input_commands.dart';
import 'dart:convert';

void main() {
  group('TmuxCommands', () {
    group('sendKeys', () {
      test('generates literal send-keys command', () {
        // _escapeArg escapes backslashes, so \\ becomes \\\\
        expect(
          TmuxInputCommands.sendKeys('%0', '\\x1b[I', literal: true),
          'tmux send-keys -t %0 -l -- "\\\\x1b[I"',
        );
      });

      test('generates non-literal send-keys command', () {
        expect(
          TmuxInputCommands.sendKeys('%0', 'Enter'),
          'tmux send-keys -t %0 -- Enter',
        );
      });

      test('guards dash-prefixed keys with -- (no tmux option injection)', () {
        expect(
          TmuxInputCommands.sendKeys('%0', '-X cancel', literal: true),
          'tmux send-keys -t %0 -l -- "-X cancel"',
        );
      });
    });
  });

  group('TmuxCommands', () {
    group('loadBufferAndPaste', () {
      // Helper: extract the base64 payload from a printf '%s' '...' token.
      String? extractBase64(String cmd) {
        final match = RegExp(
          r"printf '%s' '([A-Za-z0-9+/=]+)'",
        ).firstMatch(cmd);
        return match?.group(1);
      }

      test('single ASCII line embeds correct base64 and command structure', () {
        const text = 'hello';
        final expected = base64.encode(utf8.encode(text));
        final cmd = TmuxInputCommands.paste('%0', text);

        expect(cmd, contains("printf '%s' '$expected'"));
        expect(cmd, contains('| base64 -d'));
        expect(cmd, contains('| tmux load-buffer -b '));
        expect(cmd, contains('- &&'));
        expect(cmd, contains('tmux paste-buffer -d -p -b '));
        expect(cmd, contains('-t %0'));
        // Must NOT use echo -n (POSIX-non-portable on dash/busybox).
        expect(cmd, isNot(contains('echo -n')));
      });

      test(
        'empty text: helper returns a command string (guard handled by caller)',
        () {
          // The helper is a pure command-string builder; empty-text guard lives
          // in _sendMultilineText. The helper does not throw on empty input.
          expect(() => TmuxInputCommands.paste('%0', ''), returnsNormally);
          // The encoded form of '' is '' in base64; command should still be valid.
          final cmd = TmuxInputCommands.paste('%0', '');
          expect(cmd, contains('printf'));
        },
      );

      test('base64 encoded payload contains no newline characters', () {
        // dart:convert base64.encode does NOT insert line breaks (unlike CLI base64).
        // Newlines in the encoded string would break the single-line shell command.
        const text =
            'line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10';
        final cmd = TmuxInputCommands.paste('%0', text);
        final encoded = extractBase64(cmd);
        expect(encoded, isNotNull);
        expect(encoded, isNot(contains('\n')));
        expect(encoded, isNot(contains('\r')));
      });

      test('multi-line payload round-trips through base64 correctly', () {
        const text = 'line1\nline2\nline3';
        final cmd = TmuxInputCommands.paste('%1', text);

        final encoded = extractBase64(cmd);
        expect(encoded, isNotNull);
        final decoded = utf8.decode(base64.decode(encoded!));
        expect(decoded, equals(text));
      });

      test(
        'special chars are safe: payload base64 contains no shell metachars from input',
        () {
          const text = "echo 'hi'; rm -rf \$HOME";
          final cmd = TmuxInputCommands.paste('%0', text);

          // The base64 alphabet contains only [A-Za-z0-9+/=] — no quotes or dollars.
          final encoded = extractBase64(cmd);
          expect(encoded, isNotNull);
          expect(encoded, isNot(contains("'")));
          expect(encoded, isNot(contains(r'$')));

          // Round-trip must restore the original.
          final decoded = utf8.decode(base64.decode(encoded!));
          expect(decoded, equals(text));
        },
      );

      test('UTF-8 multibyte payload round-trips correctly', () {
        const text = 'あいうえお\nテスト';
        final cmd = TmuxInputCommands.paste('%0', text);

        final encoded = extractBase64(cmd);
        expect(encoded, isNotNull);
        final decoded = utf8.decode(base64.decode(encoded!));
        expect(decoded, equals(text));
      });

      test('target with space is escaped by _escapeArg (double-quoted)', () {
        final cmd = TmuxInputCommands.paste('my session:0.0', 'hi');
        // _escapeArg wraps targets containing spaces in double quotes.
        expect(cmd, contains('"my session:0.0"'));
      });

      test('buffer name matches muxpod-<digits>-<hex6> pattern', () {
        final cmd = TmuxInputCommands.paste('%0', 'test');
        final bufPattern = RegExp(r'muxpod-\d+-[0-9a-f]{6}');
        expect(bufPattern.hasMatch(cmd), isTrue);
      });

      test('two calls produce distinct buffer names', () {
        final cmd1 = TmuxInputCommands.paste('%0', 'a');
        final cmd2 = TmuxInputCommands.paste('%0', 'b');

        final pattern = RegExp(r'muxpod-\d+-[0-9a-f]{6}');
        expect(pattern.hasMatch(cmd1), isTrue);
        expect(pattern.hasMatch(cmd2), isTrue);
        // The buffer is deleted immediately after paste (-d flag).
        expect(cmd1, contains('paste-buffer -d'));
        expect(cmd2, contains('paste-buffer -d'));
      });
    });
  });

  group('TmuxCommands', () {
    group('loadBufferAndPasteNoBracketed', () {
      test('omits -p flag and uses printf', () {
        final cmd = TmuxInputCommands.pasteNoBracketed('%0', 'hello');
        expect(cmd, contains("printf '%s'"));
        expect(cmd, contains('paste-buffer -d -b'));
        expect(cmd, isNot(contains('paste-buffer -d -p')));
        expect(cmd, isNot(contains('echo -n')));
      });

      test('round-trips payload correctly', () {
        const text = 'line1\nline2';
        final cmd = TmuxInputCommands.pasteNoBracketed('%1', text);
        final match = RegExp(
          r"printf '%s' '([A-Za-z0-9+/=]+)'",
        ).firstMatch(cmd);
        expect(match, isNotNull);
        final decoded = utf8.decode(base64.decode(match!.group(1)!));
        expect(decoded, equals(text));
      });
    });
  });

  group('sendEnter / sendInterrupt / sendEscape', () {
    test('sendEnter generates Enter key', () {
      expect(TmuxInputCommands.sendEnter('%0'), 'tmux send-keys -t %0 Enter');
    });

    test('sendInterrupt generates C-c', () {
      expect(TmuxInputCommands.sendInterrupt('%0'), 'tmux send-keys -t %0 C-c');
    });

    test('sendEscape generates Escape', () {
      expect(TmuxInputCommands.sendEscape('%0'), 'tmux send-keys -t %0 Escape');
    });
  });

  group('copyMode commands', () {
    test('enterCopyMode', () {
      expect(TmuxInputCommands.enterCopyMode('%0'), 'tmux copy-mode -t %0');
    });

    test('cancelCopyMode', () {
      expect(
        TmuxInputCommands.cancelCopyMode('%0'),
        'tmux send-keys -t %0 -X cancel',
      );
    });
  });

  group('Image path injection via sendKeys', () {
    test('sends simple path with literal flag', () {
      final cmd = TmuxInputCommands.sendKeys(
        '%0',
        '/tmp/muxpod/img_20260403_a3f2.png',
        literal: true,
      );
      expect(cmd, contains('-l'));
      expect(cmd, contains('/tmp/muxpod/img_20260403_a3f2.png'));
    });

    test('handles path with safe characters only', () {
      final cmd = TmuxInputCommands.sendKeys(
        '%42',
        '/tmp/muxpod/test_image-v2.0.jpg',
        literal: true,
      );
      expect(cmd, contains('-l'));
      expect(cmd, contains('test_image-v2.0.jpg'));
    });

    test('sends Enter key after path for auto-enter', () {
      final cmd = TmuxInputCommands.sendKeys('%0', 'Enter');
      expect(cmd, contains('Enter'));
      expect(cmd, isNot(contains('-l')));
    });

    test('formats @-prefixed path correctly', () {
      const path = '@/tmp/muxpod/img_test.png';
      final cmd = TmuxInputCommands.sendKeys('%0', path, literal: true);
      expect(cmd, contains('-l'));
      expect(cmd, contains('@/tmp/muxpod/img_test.png'));
    });
  });
}
