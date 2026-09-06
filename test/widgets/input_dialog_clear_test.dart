// Widget tests for the command-input dialog (_InputDialogContent).
//
// Semantics under test (PR #50, revised):
//   - SEND path  : the input buffer is cleared. After a successful send the
//                  host's saved draft becomes '' and stays '' — even if the
//                  controller fires a late change notification during teardown
//                  (IME composing-confirm on focus loss). The _sent latch
//                  suppresses that re-notification.
//   - CANCEL path: the draft is PRESERVED. Dismissing via cancel / swipe /
//                  back keeps whatever the user typed, so reopening restores it.
//
// We model the host's _savedCommandInput with a local `saved` variable that
// onValueChanged writes to (mirroring _showInputDialog) and that the send
// callback clears (mirroring onSend's `_savedCommandInput = ''`). The dialog is
// pumped in isolation through the @visibleForTesting seam
// buildInputDialogContentForTesting(), avoiding the full
// SSH/tmux provider stack.
//
// NOTE: tester.enterText() fires the controller listener synchronously and does
// NOT reproduce the real async focus-loss -> IME-confirm race. These tests
// therefore verify the _sent latch *logic*, not the underlying platform race.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';

Widget _buildHarness({
  String initialValue = '',
  required void Function(String) onValueChanged,
  required Future<void> Function(String) onSend,
}) {
  return MaterialApp(
    home: Scaffold(
      body: buildInputDialogContentForTesting(
        initialValue: initialValue,
        onValueChanged: onValueChanged,
        onSend: onSend,
      ),
    ),
  );
}

void main() {
  group('_InputDialogContent — clear on send / keep on cancel', () {
    testWidgets('text field is pre-populated with initialValue', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          initialValue: 'hello world',
          onValueChanged: (_) {},
          onSend: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      expect(
        tester.widget<TextField>(textField).controller?.text,
        'hello world',
        reason: 'initialValue must be reflected in the text field on open',
      );
    });

    testWidgets('text field is empty when initialValue is empty string',
        (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          initialValue: '',
          onValueChanged: (_) {},
          onSend: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '',
        reason: 'text field must start empty when initialValue is empty',
      );
    });

    testWidgets('onValueChanged fires as user types', (tester) async {
      String captured = '';

      await tester.pumpWidget(
        _buildHarness(
          initialValue: '',
          onValueChanged: (v) => captured = v,
          onSend: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ls -la');
      await tester.pump();

      expect(captured, 'ls -la',
          reason: 'onValueChanged must track every keystroke so the host can '
              'persist the draft in real time');
    });

    testWidgets('onSend receives the current text when Execute is tapped',
        (tester) async {
      String? sentValue;

      await tester.pumpWidget(
        _buildHarness(
          initialValue: '',
          onValueChanged: (_) {},
          onSend: (v) async {
            sentValue = v;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'echo hi');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Execute'));
      await tester.pumpAndSettle();

      expect(sentValue, 'echo hi',
          reason: 'onSend must receive the full text the user typed');
    });

    // ---- CANCEL: draft is preserved -------------------------------------
    testWidgets('cancel preserves the draft — reopen restores typed text',
        (tester) async {
      // Model the host's _savedCommandInput.
      var saved = '';

      await tester.pumpWidget(
        _buildHarness(
          initialValue: saved,
          onValueChanged: (v) => saved = v,
          onSend: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'draft me');
      await tester.pump();
      expect(saved, 'draft me');

      // Dismiss WITHOUT sending (cancel / swipe / back). State is destroyed,
      // but the host keeps `saved` (the .then() no longer clears it).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Reopen with the preserved draft.
      await tester.pumpWidget(
        _buildHarness(
          initialValue: saved,
          onValueChanged: (v) => saved = v,
          onSend: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'draft me',
        reason: 'cancel must preserve the draft so the next open restores it',
      );
    });

    // ---- SEND: buffer is cleared ----------------------------------------
    testWidgets('send clears the draft — reopen yields empty field',
        (tester) async {
      var saved = '';

      await tester.pumpWidget(
        _buildHarness(
          initialValue: saved,
          onValueChanged: (v) => saved = v,
          // Mirror host onSend: clear the draft. (No Navigator.pop here.)
          onSend: (_) async {
            saved = '';
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'rm -rf /tmp/test');
      await tester.pump();
      expect(saved, 'rm -rf /tmp/test');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Execute'));
      await tester.pumpAndSettle();
      expect(saved, '', reason: 'send must clear the host draft');

      // Tear down and reopen with the cleared draft.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _buildHarness(
          initialValue: saved,
          onValueChanged: (v) => saved = v,
          onSend: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '',
        reason: 'text field must be empty on reopen after send',
      );
    });

    // ---- SEND latch: teardown re-notification must NOT resurrect draft ----
    testWidgets(
        'after send, a late controller notification does not resurrect the draft',
        (tester) async {
      var saved = '';

      await tester.pumpWidget(
        _buildHarness(
          initialValue: saved,
          onValueChanged: (v) => saved = v,
          onSend: (_) async {
            saved = '';
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'sent command');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Execute'));
      await tester.pumpAndSettle();
      expect(saved, '', reason: 'send cleared the draft');

      // Simulate the teardown re-notification: the controller fires another
      // change carrying the still-present sent text (as IME composing-confirm
      // would on focus loss). The _sent latch must suppress onValueChanged so
      // `saved` is NOT overwritten back to the sent command.
      await tester.enterText(find.byType(TextField), 'sent command');
      await tester.pump();

      expect(
        saved,
        '',
        reason: 'the _sent latch must ignore post-send notifications so the '
            'cleared draft is not resurrected',
      );
    });
  });
}
