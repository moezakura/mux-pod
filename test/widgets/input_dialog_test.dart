import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';

/// Helper that wraps the dialog content in a testable widget tree.
Widget _buildWidget({
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
  group('InputDialogContent – Enter key behaviour', () {
    testWidgets('plain Enter calls onSend exactly once', (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(_buildWidget(
        initialValue: 'hello',
        onValueChanged: (_) {},
        onSend: (v) async => sendCount++,
      ));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sendCount, 1);
    });

    testWidgets('Shift+Enter inserts newline and does not call onSend',
        (tester) async {
      int sendCount = 0;
      String? lastValue;
      await tester.pumpWidget(_buildWidget(
        initialValue: 'hello',
        onValueChanged: (v) => lastValue = v,
        onSend: (v) async => sendCount++,
      ));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(sendCount, 0);
      expect(lastValue, contains('\n'));
    });

    testWidgets(
        'Enter while composing range is active does not call onSend',
        (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(_buildWidget(
        initialValue: '',
        onValueChanged: (_) {},
        onSend: (v) async => sendCount++,
      ));
      await tester.pump();

      // Simulate IME composition: set composing range to a non-collapsed range.
      final TextField textField =
          tester.widget<TextField>(find.byType(TextField));
      final TextEditingController controller = textField.controller!;
      controller.value = const TextEditingValue(
        text: 'あ',
        composing: TextRange(start: 0, end: 1),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sendCount, 0);
      expect(controller.text, 'あ');
    });
  });
}
