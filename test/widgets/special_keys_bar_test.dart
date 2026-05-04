import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

/// Build a minimal test app around [SpecialKeysBar].
Widget _buildTestApp({
  required void Function(String) onKeyPressed,
  required void Function(String) onSpecialKeyPressed,
  bool directInputEnabled = true,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SpecialKeysBar(
        onKeyPressed: onKeyPressed,
        onSpecialKeyPressed: onSpecialKeyPressed,
        directInputEnabled: directInputEnabled,
        hapticFeedback: false,
      ),
    ),
  );
}

void main() {
  group('SpecialKeysBar — hardware-key repeat, no throttle drops', () {
    testWidgets(
        'rapid Enter repeats (10x) all reach onSpecialKeyPressed',
        (tester) async {
      final List<String> received = [];

      await tester.pumpWidget(_buildTestApp(
        onKeyPressed: (_) {},
        onSpecialKeyPressed: received.add,
      ));
      await tester.pump();

      // Focus the direct-input field so _handleKeyEvent fires.
      await tester.tap(find.byType(TextField));
      await tester.pump();

      for (int i = 0; i < 10; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        // One frame between repeats — fastPath clears _isResettingController
        // synchronously so _onDirectInputChanged never blocks on next press.
        await tester.pump();
      }

      final enterCount = received.where((k) => k == 'Enter').length;
      expect(enterCount, 10,
          reason:
              'Expected all 10 Enter repeats, got $enterCount. '
              'The 100 ms throttle may still be active.');
    });

    testWidgets(
        'rapid ArrowLeft repeats (10x) all reach onSpecialKeyPressed',
        (tester) async {
      final List<String> received = [];

      await tester.pumpWidget(_buildTestApp(
        onKeyPressed: (_) {},
        onSpecialKeyPressed: received.add,
      ));
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.pump();

      for (int i = 0; i < 10; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
      }

      // ArrowLeft maps to 'Left' in tmux format.
      final leftCount = received.where((k) => k == 'Left').length;
      expect(leftCount, 10,
          reason:
              'Expected all 10 ArrowLeft repeats, got $leftCount.');
    });
  });

  group('SpecialKeysBar — single-shot iOS echo suppression', () {
    testWidgets(
        'onDirectInputSubmitted fired by HW Enter is suppressed; '
        'a subsequent software-Enter call goes through', (tester) async {
      // This test verifies that consumeRecentKeyEventFlag() correctly
      // allows only one suppression: the immediate iOS UITextInput callback
      // that follows a hardware keystroke.
      //
      // Strategy: send one HW Enter (sets the flag), then trigger
      // _onDirectInputSubmitted via TextInputAction.send (should be
      // suppressed because the flag is set). Then trigger it again
      // (flag consumed — should go through).
      final List<String> received = [];

      await tester.pumpWidget(_buildTestApp(
        onKeyPressed: (_) {},
        onSpecialKeyPressed: received.add,
      ));
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.pump();

      // 1. HW Enter fires → _markKeyEventHandled() → _expectIosTextEcho = true
      //    AND _sendDirectEnterAndClear → 'Enter' is sent, _resetToSentinel(fastPath).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      // Do NOT pump postFrameCallback yet — flag is still hot.

      final countAfterHwEnter = received.where((k) => k == 'Enter').length;
      expect(countAfterHwEnter, 1, reason: 'HW Enter should send exactly one Enter.');

      // 2. Simulate iOS UITextInput echo: the OS fires onSubmitted again for
      //    the same keystroke. _consumeRecentKeyEventFlag() should return true
      //    and block this second 'Enter' from reaching onSpecialKeyPressed.
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      final countAfterEcho = received.where((k) => k == 'Enter').length;
      expect(countAfterEcho, 1,
          reason:
              'The OS echo of the HW Enter via onSubmitted must be suppressed '
              'by consumeRecentKeyEventFlag(). Count should still be 1, '
              'but got $countAfterEcho.');

      // 3. Pump to let postFrameCallback run (auto-clear, already consumed).
      await tester.pump();

      // 4. A new software-keyboard Enter (no preceding HW key) should go through.
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      final countAfterSoftEnter = received.where((k) => k == 'Enter').length;
      expect(countAfterSoftEnter, 2,
          reason:
              'A second onSubmitted call (software keyboard Enter) should '
              'reach onSpecialKeyPressed because the flag was already consumed.');
    });
  });
}
