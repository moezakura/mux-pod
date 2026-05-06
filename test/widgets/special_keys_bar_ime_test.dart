import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

/// Sentinel zero-width space used internally by SpecialKeysBar.
const _sentinel = '​';

/// Helper: build SpecialKeysBar inside a minimal MaterialApp with
/// DirectInput enabled and collect key/special-key emissions.
Future<({List<String> keys, List<String> specialKeys})> _buildBar(
  WidgetTester tester,
) async {
  final keys = <String>[];
  final specialKeys = <String>[];

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SpecialKeysBar(
          directInputEnabled: true,
          hapticFeedback: false,
          onKeyPressed: keys.add,
          onSpecialKeyPressed: specialKeys.add,
        ),
      ),
    ),
  );

  // Let the widget settle (initState sets the sentinel value).
  await tester.pump();

  return (keys: keys, specialKeys: specialKeys);
}

/// Simulate a TextEditingValue update as if the IME sent it.
void _updateEditingValue(WidgetTester tester, TextEditingValue value) {
  tester.testTextInput.updateEditingValue(value);
}

void main() {
  setUpAll(() {
    // Prevent google_fonts from hitting the network in tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('SpecialKeysBar DirectInput IME handling', () {
    testWidgets('compose then commit: onKeyPressed called once with committed text',
        (tester) async {
      final result = await _buildBar(tester);

      // Find the TextField and give it focus.
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.tap(textField);
      await tester.pump();

      // Step 1: Simulate composing — controller has composing range active.
      // The IME is showing "あ" as a composing candidate.
      _updateEditingValue(
        tester,
        TextEditingValue(
          text: '${_sentinel}あ', // sentinel + "あ"
          selection: const TextSelection.collapsed(offset: 2),
          composing: const TextRange(start: 1, end: 2), // "あ" is composing
        ),
      );
      await tester.pump();

      // While composing, nothing should be sent.
      expect(result.keys, isEmpty);
      expect(result.specialKeys, isEmpty);

      // Step 2: User selects a kanji — composing ends, committed text arrives.
      // The controller now shows sentinel + "亜" with no composing range.
      _updateEditingValue(
        tester,
        TextEditingValue(
          text: '${_sentinel}亜', // sentinel + "亜"
          selection: const TextSelection.collapsed(offset: 2),
          composing: TextRange.empty, // composing committed
        ),
      );
      await tester.pump();
      // Sentinel reset is deferred to postFrameCallback.
      await tester.pump();

      // Exactly one emission with the committed kanji.
      expect(result.keys, hasLength(1));
      expect(result.keys.first, '亜'); // "亜"
      expect(result.specialKeys, isEmpty);
    });

    testWidgets(
        'partial-input continuation (no commit): onKeyPressed NOT called',
        (tester) async {
      final result = await _buildBar(tester);

      final textField = find.byType(TextField);
      await tester.tap(textField);
      await tester.pump();

      // Keep the composing range valid throughout multiple updates,
      // simulating the user continuing to type without committing.
      for (final composingChar in ['あ', 'い', 'う']) {
        _updateEditingValue(
          tester,
          TextEditingValue(
            text: '$_sentinel$composingChar',
            selection: const TextSelection.collapsed(offset: 2),
            composing: const TextRange(start: 1, end: 2),
          ),
        );
        await tester.pump();
      }

      expect(result.keys, isEmpty);
      expect(result.specialKeys, isEmpty);
    });

    testWidgets('backspace on empty buffer: BSpace emitted', (tester) async {
      final result = await _buildBar(tester);

      final textField = find.byType(TextField);
      await tester.tap(textField);
      await tester.pump();

      // Simulate the sentinel being deleted (text becomes empty).
      _updateEditingValue(
        tester,
        const TextEditingValue(
          text: '', // sentinel removed → Backspace detected
          selection: TextSelection.collapsed(offset: 0),
          composing: TextRange.empty,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(result.specialKeys, contains('BSpace'));
      expect(result.keys, isEmpty);
    });

    testWidgets('plain text without IME: onKeyPressed called once', (tester) async {
      final result = await _buildBar(tester);

      final textField = find.byType(TextField);
      await tester.tap(textField);
      await tester.pump();

      // Simulate typing "hello" with no composing range.
      _updateEditingValue(
        tester,
        TextEditingValue(
          text: '${_sentinel}hello',
          selection: const TextSelection.collapsed(offset: 6),
          composing: TextRange.empty,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(result.keys, hasLength(1));
      expect(result.keys.first, 'hello');
      expect(result.specialKeys, isEmpty);
    });

    // Regression: the old iOS-style duplicate-detection branch would compare the
    // committed text against a stored composing snapshot and, when the committed
    // text was longer and started with the snapshot, silently substitute the
    // snapshot instead.  That branch was removed; this test pins the new
    // behaviour: the full committed text must be forwarded as-is.
    testWidgets(
        'iOS-style commit longer than composing sends committed text once',
        (tester) async {
      final result = await _buildBar(tester);

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.tap(textField);
      await tester.pump();

      // Step 1: composing 'a' (single ASCII letter, Samsung-style composing).
      _updateEditingValue(
        tester,
        TextEditingValue(
          text: '${_sentinel}a',
          selection: const TextSelection.collapsed(offset: 2),
          composing: const TextRange(start: 1, end: 2),
        ),
      );
      await tester.pump();

      // Nothing emitted while composing.
      expect(result.keys, isEmpty);
      expect(result.specialKeys, isEmpty);

      // Step 2: IME commits '亜亜' — text is longer than the composing snapshot.
      // Previously this would have been truncated to 'a'; now '亜亜' must be sent.
      _updateEditingValue(
        tester,
        TextEditingValue(
          text: '${_sentinel}亜亜',
          selection: const TextSelection.collapsed(offset: 3),
          composing: TextRange.empty,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(result.keys, hasLength(1));
      expect(result.keys.first, '亜亜');
      expect(result.specialKeys, isEmpty);
    });

    testWidgets('hardware Enter while composing: KeyEventResult.ignored',
        (tester) async {
      final result = await _buildBar(tester);

      final textField = find.byType(TextField);
      await tester.tap(textField);
      await tester.pump();

      // Start a composing session.
      _updateEditingValue(
        tester,
        TextEditingValue(
          text: '${_sentinel}あ',
          selection: const TextSelection.collapsed(offset: 2),
          composing: const TextRange(start: 1, end: 2),
        ),
      );
      await tester.pump();

      // Send a hardware Enter key while composing is active.
      // The handler should return KeyEventResult.ignored, so the IME
      // handles it (no Enter special-key emission from our code).
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // No Enter should have been sent by SpecialKeysBar while composing.
      expect(result.specialKeys.where((k) => k == 'Enter'), isEmpty);
      expect(result.keys, isEmpty);
    });
  });
}
