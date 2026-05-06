// Widget tests verifying that the input dialog controller starts empty
// whenever the dialog is opened after a previous session.
//
// Strategy: pump _InputDialogContent via the @visibleForTesting seam
// TerminalScreen.buildInputDialogContentForTesting().  This avoids standing
// up the full TerminalScreen with its SSH/tmux provider dependencies while
// still exercising the real widget tree.
//
// The tests mirror the dismissal paths added by PR #50:
//   - cancel (Navigator.pop without sending)
//   - send  (onSend callback fires, then Navigator.pop)
//
// In both cases the host state resets _savedCommandInput to '' in the
// .then((_) { if (mounted) _savedCommandInput = ''; }) callback, so the
// *next* open receives initialValue: ''.  We verify that invariant by
// reopening the dialog with initialValue: '' and asserting the TextField
// starts empty.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pumps [_InputDialogContent] inside a minimal navigator scaffold so that
/// Cancel's Navigator.pop(context) resolves correctly.
///
/// [initialValue] simulates _savedCommandInput at open time.
/// [onValueChanged] / [onSend] are forwarded verbatim.
Widget _buildHarness({
  String initialValue = '',
  required void Function(String) onValueChanged,
  required Future<void> Function(String) onSend,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TerminalScreen.buildInputDialogContentForTesting(
        initialValue: initialValue,
        onValueChanged: onValueChanged,
        onSend: onSend,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('_InputDialogContent — controller starts empty on reopen', () {
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
        (tester.widget<TextField>(textField).controller)?.text,
        'hello world',
        reason: 'initialValue must be reflected in the text field on open',
      );
    });

    testWidgets('text field is empty when initialValue is empty string',
        (tester) async {
      // Simulates reopening after the host has reset _savedCommandInput = ''.
      await tester.pumpWidget(
        _buildHarness(
          initialValue: '',
          onValueChanged: (_) {},
          onSend: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      expect(
        (tester.widget<TextField>(textField).controller)?.text,
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
              'persist _savedCommandInput in real time');
    });

    testWidgets('onSend is called with the current text when Send is tapped',
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

      // Tap the Execute button (ElevatedButton labelled 'Execute').
      await tester.tap(find.widgetWithText(ElevatedButton, 'Execute'));
      await tester.pumpAndSettle();

      expect(sentValue, 'echo hi',
          reason: 'onSend must receive the full text the user typed');
    });

    testWidgets(
        'reopening with initialValue empty after cancel yields empty field',
        (tester) async {
      // Round-trip test:
      //   1. Open dialog with some pre-saved text (initialValue: 'draft').
      //   2. Simulate host clearing _savedCommandInput (initialValue: '').
      //   3. Open dialog again — field must be empty.

      // First open: pre-populated.
      await tester.pumpWidget(
        _buildHarness(
          initialValue: 'draft',
          onValueChanged: (_) {},
          onSend: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        (tester.widget<TextField>(find.byType(TextField)).controller)?.text,
        'draft',
      );

      // Host resets _savedCommandInput (simulated by pumping with '').
      await tester.pumpWidget(
        _buildHarness(
          initialValue: '',
          onValueChanged: (_) {},
          onSend: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        (tester.widget<TextField>(find.byType(TextField)).controller)?.text,
        '',
        reason: 'after the host resets _savedCommandInput the next open must '
            'show an empty field',
      );
    });

    testWidgets('reopening with initialValue empty after send yields empty field',
        (tester) async {
      bool sendCalled = false;

      // First open: user types and sends.
      await tester.pumpWidget(
        _buildHarness(
          initialValue: '',
          onValueChanged: (_) {},
          onSend: (_) async {
            sendCalled = true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'rm -rf /tmp/test');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Execute'));
      await tester.pumpAndSettle();

      expect(sendCalled, isTrue);

      // Host clears _savedCommandInput then reopens dialog with ''.
      await tester.pumpWidget(
        _buildHarness(
          initialValue: '',
          onValueChanged: (_) {},
          onSend: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        (tester.widget<TextField>(find.byType(TextField)).controller)?.text,
        '',
        reason: 'text field must be empty on reopen after send + host reset',
      );
    });
  });
}
