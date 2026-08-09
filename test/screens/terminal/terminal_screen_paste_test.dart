import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen paste (G1-6c)', () {
    testWidgets('sends multi-line text through load-buffer/paste-buffer', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.text('Cmd'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'echo hi');
      await tester.tap(find.text('Execute'));
      await tester.pumpAndSettle();

      expect(
        client.execCommands.any((c) => c.contains('paste-buffer')),
        isTrue,
      );
      expect(
        client.execCommands.any(
          (c) => c.contains('send-keys') && c.contains('Enter'),
        ),
        isTrue,
      );
    });

    testWidgets('empty text does not issue any paste command', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.text('Cmd'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Execute'));
      await tester.pumpAndSettle();

      expect(
        client.execCommands.any((c) => c.contains('paste-buffer')),
        isFalse,
      );
    });

    testWidgets(
      'uses bracketed paste and preserves shell-special multiline input',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

        await tester.tap(find.text('Cmd'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          "printf '\$HOME'\n# keep this literal",
        );
        await tester.tap(find.text('Execute'));
        await tester.pumpAndSettle();

        final paste = client.execCommands.firstWhere(
          (c) => c.contains('paste-buffer'),
        );
        expect(paste, contains('paste-buffer -d -p'));
        expect(
          paste,
          contains('cHJpbnRmICckSE9NRScKIyBrZWVwIHRoaXMgbGl0ZXJhbA=='),
        );
      },
    );

    testWidgets('falls back to non-bracketed paste when tmux rejects -p', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        execExitCodes: const {'paste-buffer -d -p': 1},
      );

      await tester.tap(find.text('Cmd'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'echo fallback');
      await tester.tap(find.text('Execute'));
      await tester.pumpAndSettle();

      expect(
        client.execCommands.where((c) => c.contains('paste-buffer')).length,
        2,
      );
      expect(
        client.execCommands.any((c) => c.contains('paste-buffer -d -b')),
        isTrue,
      );
      expect(
        client.execCommands
            .where((c) => c.contains('send-keys') && c.contains('Enter'))
            .length,
        1,
      );
    });
  });
}
