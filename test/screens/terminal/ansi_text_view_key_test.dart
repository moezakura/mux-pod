import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/terminal_display_provider.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';

import '../../helpers/fake_settings_notifier.dart';

/// Issue #116: iPadOS で Option+O が OS 合成文字 'ø' (U+00F8) として
/// event.character に届くため、ESC+ø (1b c3 b8) が送信されていた。
/// 修正後は Alt/Meta 押下かつ非 ASCII character の場合に
/// logicalKey から ASCII 文字を導出して ESC+base-char を送る。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<KeyInputEvent> events = [];

  Widget buildSubject() {
    events.clear();
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => FakeSettingsNotifier()),
        terminalDisplayProvider.overrideWith(
          () => _FixedTerminalDisplayNotifier(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AnsiTextView(
            text: '',
            paneWidth: 80,
            paneHeight: 24,
            onKeyInput: events.add,
          ),
        ),
      ),
    );
  }

  Future<void> pressKey(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    String? character,
  }) async {
    await tester.sendKeyDownEvent(key, character: character);
    await tester.pump();
  }

  Future<void> releaseKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyUpEvent(key);
    await tester.pump();
  }

  String? lastData() => events.isEmpty ? null : events.last.data;

  group('Alt + composed character (Issue #116)', () {
    testWidgets('1. Option+O (composed ø) sends ESC+o', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.altLeft);
      await pressKey(tester, LogicalKeyboardKey.keyO, character: 'ø');

      expect(lastData(), '\x1bo');
      await releaseKey(tester, LogicalKeyboardKey.keyO);
      await releaseKey(tester, LogicalKeyboardKey.altLeft);
    });

    testWidgets('2. Alt+O (plain ASCII character) keeps same ESC+o', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.altLeft);
      await pressKey(tester, LogicalKeyboardKey.keyO, character: 'o');

      expect(lastData(), '\x1bo');
      await releaseKey(tester, LogicalKeyboardKey.keyO);
      await releaseKey(tester, LogicalKeyboardKey.altLeft);
    });

    testWidgets('3. Alt+Shift+O (composed Ø) sends ESC+O (uppercase)', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.altLeft);
      await pressKey(tester, LogicalKeyboardKey.shiftLeft);
      await pressKey(tester, LogicalKeyboardKey.keyO, character: 'Ø');

      expect(lastData(), '\x1bO');
      await releaseKey(tester, LogicalKeyboardKey.keyO);
      await releaseKey(tester, LogicalKeyboardKey.shiftLeft);
      await releaseKey(tester, LogicalKeyboardKey.altLeft);
    });

    testWidgets('4. Ctrl+Alt+O (composed ø) sends ESC+0x0f (R4 order)', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.controlLeft);
      await pressKey(tester, LogicalKeyboardKey.altLeft);
      await pressKey(tester, LogicalKeyboardKey.keyO, character: 'ø');

      expect(lastData(), '\x1b\x0f');
      await releaseKey(tester, LogicalKeyboardKey.keyO);
      await releaseKey(tester, LogicalKeyboardKey.altLeft);
      await releaseKey(tester, LogicalKeyboardKey.controlLeft);
    });

    testWidgets('5. Alt+comma (composed ≤) derives ESC+,', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.altLeft);
      await pressKey(tester, LogicalKeyboardKey.comma, character: '≤');

      expect(lastData(), '\x1b,');
      await releaseKey(tester, LogicalKeyboardKey.comma);
      await releaseKey(tester, LogicalKeyboardKey.altLeft);
    });

    testWidgets('6. Alt+1 (composed ¡) derives ESC+1', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.altLeft);
      await pressKey(tester, LogicalKeyboardKey.digit1, character: '¡');

      expect(lastData(), '\x1b1');
      await releaseKey(tester, LogicalKeyboardKey.digit1);
      await releaseKey(tester, LogicalKeyboardKey.altLeft);
    });
  });

  group('right-side modifiers & coverage extension', () {
    testWidgets('13. altRight + composed ø sends ESC+o', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.altRight);
      await pressKey(tester, LogicalKeyboardKey.keyO, character: 'ø');

      expect(lastData(), '\x1bo');
      await releaseKey(tester, LogicalKeyboardKey.keyO);
      await releaseKey(tester, LogicalKeyboardKey.altRight);
    });

    testWidgets('14. metaRight + composed ø sends ESC+o', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.metaRight);
      await pressKey(tester, LogicalKeyboardKey.keyO, character: 'ø');

      expect(lastData(), '\x1bo');
      await releaseKey(tester, LogicalKeyboardKey.keyO);
      await releaseKey(tester, LogicalKeyboardKey.metaRight);
    });

    testWidgets("15. Alt+Space (NBSP) sends ESC+SPC (not ESC+NBSP)", (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.altLeft);
      await pressKey(tester, LogicalKeyboardKey.space, character: '\u00A0');

      expect(lastData(), '\x1b ');
      await releaseKey(tester, LogicalKeyboardKey.space);
      await releaseKey(tester, LogicalKeyboardKey.altLeft);
    });

    testWidgets(
      '16. Alt+Arrow keys keep xterm CSI 1;3 sequences (existing path intact)',
      (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        await pressKey(tester, LogicalKeyboardKey.altLeft);
        await pressKey(tester, LogicalKeyboardKey.arrowRight);
        expect(lastData(), '\x1b[1;3C');
        await releaseKey(tester, LogicalKeyboardKey.arrowRight);

        await pressKey(tester, LogicalKeyboardKey.arrowLeft);
        expect(lastData(), '\x1b[1;3D');
        await releaseKey(tester, LogicalKeyboardKey.arrowLeft);

        await releaseKey(tester, LogicalKeyboardKey.altLeft);
      },
    );

    testWidgets(
      '17. Alt+F1 keeps xterm CSI 1;3P sequence (existing path intact)',
      (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        await pressKey(tester, LogicalKeyboardKey.altLeft);
        await pressKey(tester, LogicalKeyboardKey.f1);

        expect(lastData(), '\x1b[1;3P');
        await releaseKey(tester, LogicalKeyboardKey.f1);
        await releaseKey(tester, LogicalKeyboardKey.altLeft);
      },
    );

    testWidgets(
      '18. multi-char character with Alt derives single base char (guard)',
      (tester) async {
        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        await pressKey(tester, LogicalKeyboardKey.altLeft);
        // 極端な IME 状態等で複数文字 character が来ても、
        // 導出結果は必ず単一 ASCII 文字になる契約。
        await pressKey(tester, LogicalKeyboardKey.keyO, character: 'øø');

        expect(lastData(), '\x1bo');
        await releaseKey(tester, LogicalKeyboardKey.keyO);
        await releaseKey(tester, LogicalKeyboardKey.altLeft);
      },
    );

    testWidgets('19. Ctrl+letter keeps control-char generation (no Alt)', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.controlLeft);
      await pressKey(tester, LogicalKeyboardKey.keyA, character: 'a');

      expect(lastData(), '\x01');
      await releaseKey(tester, LogicalKeyboardKey.keyA);
      await releaseKey(tester, LogicalKeyboardKey.controlLeft);
    });
  });

  group('non-Alt paths unchanged', () {
    testWidgets('7. plain O with composed ø keeps ø (no Alt)', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.keyO, character: 'ø');

      expect(lastData(), 'ø');
      await releaseKey(tester, LogicalKeyboardKey.keyO);
    });
  });

  group('Meta (Cmd) path unified (D5)', () {
    testWidgets('8. Cmd+O (ASCII) sends ESC+o', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.metaLeft);
      await pressKey(tester, LogicalKeyboardKey.keyO, character: 'o');

      expect(lastData(), '\x1bo');
      await releaseKey(tester, LogicalKeyboardKey.keyO);
      await releaseKey(tester, LogicalKeyboardKey.metaLeft);
    });

    testWidgets('9. Cmd+O (composed ø) sends ESC+o', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.metaLeft);
      await pressKey(tester, LogicalKeyboardKey.keyO, character: 'ø');

      expect(lastData(), '\x1bo');
      await releaseKey(tester, LogicalKeyboardKey.keyO);
      await releaseKey(tester, LogicalKeyboardKey.metaLeft);
    });
  });

  group('modifier reset & special keys', () {
    testWidgets('10. Alt released: next O sends plain o', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.altLeft);
      await pressKey(tester, LogicalKeyboardKey.keyO, character: 'ø');
      expect(lastData(), '\x1bo');

      await releaseKey(tester, LogicalKeyboardKey.keyO);
      await releaseKey(tester, LogicalKeyboardKey.altLeft);

      await pressKey(tester, LogicalKeyboardKey.keyO, character: 'o');
      expect(lastData(), 'o');
      await releaseKey(tester, LogicalKeyboardKey.keyO);
    });

    testWidgets('11. Alt+Enter keeps special-key path (R10)', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.altLeft);
      await pressKey(tester, LogicalKeyboardKey.enter);

      expect(events, isNotEmpty);
      expect(events.last.isSpecialKey, isTrue);
      expect(events.last.tmuxKeyName, 'Enter');
      expect(lastData(), '\r');
      await releaseKey(tester, LogicalKeyboardKey.enter);
      await releaseKey(tester, LogicalKeyboardKey.altLeft);
    });

    testWidgets('12. KeyRepeat with Alt+composed char sends ESC+o (R9)', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await pressKey(tester, LogicalKeyboardKey.altLeft);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyO, character: 'ø');
      await tester.pump();
      expect(lastData(), '\x1bo');

      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyO, character: 'ø');
      await tester.pump();
      expect(lastData(), '\x1bo');

      await releaseKey(tester, LogicalKeyboardKey.keyO);
      await releaseKey(tester, LogicalKeyboardKey.altLeft);
    });
  });
}

class _FixedTerminalDisplayNotifier extends TerminalDisplayNotifier {
  @override
  TerminalDisplayState build() => const TerminalDisplayState(
    paneWidth: 80,
    paneHeight: 24,
    screenWidth: 400.0,
    screenHeight: 800.0,
    calculatedFontSize: 14.0,
  );
}
