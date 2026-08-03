import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen history (G1-7a)', () {
    testWidgets('scroll mode loads deep history with capture-pane -S', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Switch from Normal Mode to Scroll & Select Mode.
      await tester.tap(find.text('Normal Mode'));
      await tester.pumpAndSettle();

      expect(client.sendKeysCommands.any((c) => c.contains('copy-mode')), isTrue);
      expect(
        client.execCommands.any((c) => c.contains('capture-pane') && c.contains('-S -100000')),
        isTrue,
      );
    });

    testWidgets('settings menu is reachable but copy-mode is skipped when disconnected', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      client.setConnected(SshConnectionState.disconnected);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Normal Mode'));
      await tester.pumpAndSettle();

      expect(client.sendKeysCommands.any((c) => c.contains('copy-mode')), isFalse);
    });
  });
}
