// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/parsers/output_validator.dart';
import 'package:flutter_muxpod/services/tmux/parsers/session_parser.dart';
import 'package:flutter_muxpod/services/tmux/tmux_delimiters.dart';
import '../../fixtures/tmux/tmux_parser_fixtures.dart';
import 'helpers/tmux_parser_shared.dart';

void main() {
  group('TmuxParser', () {
    test('TMUX-PARSER-022: hasRecordContent separates mangled output from '
        'nothing to parse', () {
      // An empty parse result over output that carried records means the
      // delimiters did not survive; that used to reach the UI as
      // "no sessions" with exit code 0.
      expect(TmuxOutputValidator.hasRecordContent(''), isFalse);
      expect(TmuxOutputValidator.hasRecordContent('  \n '), isFalse);
      expect(TmuxOutputValidator.hasRecordContent(kNoServerOutput), isFalse);
      expect(
        TmuxOutputValidator.hasRecordContent('claude/monoroll_\$0\n'),
        isTrue,
      );
    });

    group('isServerRunning', () {
      test('returns false for known error strings', () {
        expect(TmuxOutputValidator.isServerRunning(kNoServerOutput), isFalse);
        expect(
          TmuxOutputValidator.isServerRunning('error connecting'),
          isFalse,
        );
        expect(
          TmuxOutputValidator.isServerRunning('command not found'),
          isFalse,
        );
      });

      test('returns true for normal output', () {
        expect(TmuxOutputValidator.isServerRunning('session:1:0'), isTrue);
      });
    });

    group('extractError', () {
      test('extracts no server running', () {
        expect(
          TmuxOutputValidator.extractError(kNoServerOutput),
          'tmux server is not running',
        );
      });

      test('extracts session not found', () {
        expect(
          TmuxOutputValidator.extractError(kSessionNotFoundOutput),
          'Session not found',
        );
      });

      test('extracts pane not found', () {
        expect(
          TmuxOutputValidator.extractError("can't find pane %0"),
          'Pane not found',
        );
      });

      test('returns null for normal output', () {
        expect(TmuxOutputValidator.extractError('session:1:0'), isNull);
      });
    });

    group('normalizeDelimiters', () {
      test('TMUX-PARSER-020: converts literal \\x1f/\\x1e to control chars', () {
        const literal =
            'sess\\x1f123\\x1f0\\x1f2\\x1f\$0\\x1eother\\x1f456\\x1f1\\x1f1\\x1f\$1\\x1e';
        final normalized = TmuxOutputValidator.normalizeDelimiters(
          literal,
          TmuxDelimiters.legacy,
        );
        expect(normalized.contains(kLegacyField), isTrue);
        expect(normalized.contains(kLegacyRecord), isTrue);
        expect(normalized.contains(r'\x1f'), isFalse);
        expect(normalized.contains(r'\x1e'), isFalse);
      });

      test('TMUX-PARSER-020: folds the octal literal \\037/\\036 onto the '
          'delimiters of the current call', () {
        const literal =
            'sess\\037123\\0370\\0372\\037\$0\\036other\\037456\\0371\\0371\\037\$1\\036';
        final delimiters = TmuxDelimiters.random();

        final normalized = TmuxOutputValidator.normalizeDelimiters(
          literal,
          delimiters,
        );

        expect(normalized.contains(delimiters.field), isTrue);
        expect(normalized.contains(delimiters.record), isTrue);
        expect(normalized.contains(r'\037'), isFalse);
        expect(normalized.contains(r'\036'), isFalse);
      });

      test('TMUX-PARSER-020: leaves real control chars untouched', () {
        final literal =
            'sess$kLegacyField"123"$kLegacyField"0"$kLegacyField"2"$kLegacyField"\$0"$kLegacyRecord"other"';
        final normalized = TmuxOutputValidator.normalizeDelimiters(
          literal,
          TmuxDelimiters.legacy,
        );
        expect(normalized, literal);
      });

      test(
        'TMUX-PARSER-002: parseSessions handles literal separator output',
        () {
          // SSH シェル経由で tmux -F の制御文字がリテラル表記に化けたケース。
          const literalOutput =
              'mysession\\x1f1735689600\\x1f1\\x1f3\\x1f\$0\\x1e'
              'other\\x1f1735690000\\x1f0\\x1f1\\x1f\$1\\x1e';
          final sessions = TmuxSessionParser.parse(literalOutput);
          expect(sessions, hasLength(2));
          expect(sessions[0].name, 'mysession');
          expect(sessions[0].attached, isTrue);
          expect(sessions[0].windowCount, 3);
          expect(sessions[0].id, r'$0');
          expect(sessions[1].name, 'other');
        },
      );

      test(
        'TMUX-PARSER-002: parseSessions handles octal literal separator output',
        () {
          const octalOutput =
              'mysession\\0371735689600\\0371\\0373\\037\$0\\036'
              'other\\0371735690000\\0370\\0371\\037\$1\\036';
          final sessions = TmuxSessionParser.parse(octalOutput);
          expect(sessions, hasLength(2));
          expect(sessions[0].name, 'mysession');
          expect(sessions[0].windowCount, 3);
        },
      );
    });
  });
}
