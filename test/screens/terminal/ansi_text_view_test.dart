import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/terminal_display_provider.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';

import '../../helpers/fake_settings_notifier.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildSubject(String text) {
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => FakeSettingsNotifier()),
        terminalDisplayProvider.overrideWith(() => _FixedTerminalDisplayNotifier()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AnsiTextView(
            text: text,
            paneWidth: 80,
            paneHeight: 24,
          ),
        ),
      ),
    );
  }

  testWidgets('renders plain text without crashing', (tester) async {
    await tester.pumpWidget(buildSubject('hello world'));
    await tester.pumpAndSettle();
    expect(find.textContaining('hello'), findsOneWidget);
  });

  testWidgets('renders ANSI colored text', (tester) async {
    await tester.pumpWidget(buildSubject('\x1B[31mred\x1B[0m text'));
    await tester.pumpAndSettle();
    expect(find.textContaining('red'), findsOneWidget);
  });

  testWidgets('long text wraps to multiple text widgets', (tester) async {
    final text = 'line1\nline2\nline3';
    await tester.pumpWidget(buildSubject(text));
    await tester.pumpAndSettle();
    expect(find.textContaining('line1'), findsOneWidget);
    expect(find.textContaining('line2'), findsOneWidget);
    expect(find.textContaining('line3'), findsOneWidget);
  });

  testWidgets('tapping terminal calls onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => FakeSettingsNotifier()),
          terminalDisplayProvider.overrideWith(() => _FixedTerminalDisplayNotifier()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AnsiTextView(
              text: 'hello',
              paneWidth: 80,
              paneHeight: 24,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AnsiTextView));
    expect(tapped, isTrue);
  });
}
