import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';

import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen resize (G1-7b)', () {
    testWidgets(
      'auto-resize emits resize-window when adjustMode is autoResize',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          settings: const AppSettings(
            keepScreenOn: false,
            adjustMode: 'autoResize',
          ),
        );

        // Allow the post-frame auto-resize debounce to fire.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          client.execCommands.any(
            (c) => c.contains('resize-window') && !c.contains('-A'),
          ),
          isTrue,
        );
      },
    );

    testWidgets('auto-resize is skipped when adjustMode is not autoResize', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        client.execCommands.any(
          (c) => c.contains('resize-window') && !c.contains('-A'),
        ),
        isFalse,
      );
    });
  });
}
