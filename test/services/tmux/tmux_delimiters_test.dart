import 'package:flutter_muxpod/services/tmux/tmux_delimiters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TmuxDelimiters', () {
    test('TMUX-DELIM-001: a minted pair is printable ASCII', () {
      // tmux rewrites every non-printable byte of `-F` output to '_' when the
      // client is not in UTF-8 mode, which makes a control-character delimiter
      // indistinguishable from the content around it.
      for (var i = 0; i < 32; i++) {
        final delimiters = TmuxDelimiters.random();
        for (final delimiter in [delimiters.field, delimiters.record]) {
          expect(
            delimiter.codeUnits.every((c) => c > 0x20 && c < 0x7f),
            isTrue,
            reason: 'delimiter must be printable ASCII: $delimiter',
          );
        }
      }
    });

    test('TMUX-DELIM-002: field and record delimiters are distinct', () {
      final delimiters = TmuxDelimiters.random();
      expect(delimiters.field, isNot(delimiters.record));
    });

    test('TMUX-DELIM-003: every call mints a fresh pair', () {
      // The whole point of minting per invocation: a delimiter nobody can type
      // into a session name, because it did not exist when the name was set.
      final seen = <String>{};
      for (var i = 0; i < 64; i++) {
        final delimiters = TmuxDelimiters.random();
        expect(
          seen.add(delimiters.field),
          isTrue,
          reason: 'field delimiter repeated: ${delimiters.field}',
        );
        expect(
          seen.add(delimiters.record),
          isTrue,
          reason: 'record delimiter repeated: ${delimiters.record}',
        );
      }
    });

    test(
      'TMUX-DELIM-004: a minted pair carries at least 64 bits of entropy',
      () {
        final delimiters = TmuxDelimiters.random();
        expect(RegExp(r'[0-9a-f]{16}').hasMatch(delimiters.field), isTrue);
        expect(RegExp(r'[0-9a-f]{16}').hasMatch(delimiters.record), isTrue);
      },
    );

    test('TMUX-DELIM-005: the legacy pair is the historical US/RS pair', () {
      // Parse-side only: output from a MuxPod that still asked tmux for
      // 0x1f/0x1e must keep parsing.
      expect(TmuxDelimiters.legacy.field, '\x1f');
      expect(TmuxDelimiters.legacy.record, '\x1e');
    });
  });
}
