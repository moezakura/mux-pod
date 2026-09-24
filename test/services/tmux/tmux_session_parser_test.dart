// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/tmux_delimiters.dart';
import 'package:flutter_muxpod/services/tmux/parsers/session_parser.dart';
import '../../fixtures/tmux/tmux_parser_fixtures.dart';
import 'helpers/tmux_parser_shared.dart';

void main() {
  group('TmuxParser', () {
    test('TMUX-PARSER-001: records written with the legacy pair parse under a '
        'freshly minted one', () {
      // Output from a MuxPod that still asked tmux for 0x1f/0x1e, and every
      // fixture modelled on it, has to keep parsing.
      final sessions = TmuxSessionParser.parse(
        kSessionOutput,
        delimiters: TmuxDelimiters.random(),
      );

      expect(sessions.map((s) => s.name), ['mysession', 'other']);
      expect(sessions.first.windowCount, 3);
    });

    test(
      'TMUX-PARSER-001: the literal octal spelling of the legacy pair parses '
      'under a freshly minted one',
      () {
        // tmux <= 3.5a escapes the control bytes on the way out, so the
        // delimiter reaches the app as the four characters \037.
        const output =
            r'mysession\0371735689600\0371\0373\037$0\036'
            r'other\0371735689700\0370\0371\037$1\036';

        final sessions = TmuxSessionParser.parse(
          output,
          delimiters: TmuxDelimiters.random(),
        );

        expect(sessions.map((s) => s.name), ['mysession', 'other']);
        expect(sessions.first.windowCount, 3);
      },
    );

    group('parseSessions', () {
      test('parses detailed session output', () {
        final sessions = TmuxSessionParser.parse(kSessionOutput);
        expect(sessions, hasLength(2));
        expect(sessions[0].name, 'mysession');
        expect(sessions[0].attached, isTrue);
        expect(sessions[0].windowCount, 3);
        expect(sessions[0].id, r'$0');
        expect(sessions[1].name, 'other');
        expect(sessions[1].attached, isFalse);
      });

      test('ignores no server running output', () {
        final sessions = TmuxSessionParser.parse(kNoServerOutput);
        expect(sessions, isEmpty);
      });

      test('ignores empty output', () {
        final sessions = TmuxSessionParser.parse(kEmptyOutput);
        expect(sessions, isEmpty);
      });

      test('ignores malformed lines with too few fields', () {
        final sessions = TmuxSessionParser.parse(kMalformedTooFewFields);
        expect(sessions, isEmpty);
      });

      test(
        'TMUX-DTO-004 and TMUX-PARSER-014: parses Unix seconds into created',
        () {
          final session = TmuxSessionParser.parse(kSessionOutput).first;

          expect(
            session.created,
            DateTime.fromMillisecondsSinceEpoch(1735689600000),
          );
        },
      );

      test(
        'TMUX-PARSER-014: invalid Unix seconds result in a null created value',
        () {
          final session = TmuxSessionParser.parseLine(
            'main$kLegacyField'
            'not-a-timestamp$kLegacyField'
            '0$kLegacyField'
            '1$kLegacyField\$0',
          );

          expect(session, isNotNull);
          expect(session!.created, isNull);
        },
      );
    });

    group('parseSessionsSimple', () {
      test('parses simple session output', () {
        final sessions = TmuxSessionParser.parseSimple(kSessionOutputSimple);
        expect(sessions, hasLength(2));
        expect(sessions[0].name, 'mysession');
        expect(sessions[0].windowCount, 3);
      });

      test('returns empty for no server running', () {
        expect(TmuxSessionParser.parseSimple(kNoServerOutput), isEmpty);
      });
    });
  });
}
