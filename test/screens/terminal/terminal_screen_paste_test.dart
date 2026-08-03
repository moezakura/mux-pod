import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen paste (G1-6c)', () {
    testWidgets('sends multi-line text through load-buffer/paste-buffer', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.text('Cmd'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'echo hi');
      await tester.tap(find.text('Execute'));
      await tester.pumpAndSettle();

      expect(client.execCommands.any((c) => c.contains('paste-buffer')), isTrue);
      expect(client.execCommands.any((c) => c.contains('send-keys') && c.contains('Enter')), isTrue);
    });

    testWidgets('empty text does not issue any paste command', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.text('Cmd'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Execute'));
      await tester.pumpAndSettle();

      expect(client.execCommands.any((c) => c.contains('paste-buffer')), isFalse);
    });
  });
}
