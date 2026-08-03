import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';

import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen lifecycle (G1-7d)', () {
    testWidgets('pause restores resized windows and resume keeps the screen stable', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: const AppSettings(
          keepScreenOn: false,
          adjustMode: 'autoResize',
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(client.restoreWindowCommands, isNotEmpty);
      expect(client.restoreWindowCommands.last, contains('resize-window'));
      expect(client.restoreWindowCommands.last, contains(' -A'));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // No crash after foregrounding.
      expect(find.byType(TerminalScreen), findsOneWidget);
    });

    testWidgets('pause does not restore windows when auto-resize was never used', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(client.restoreWindowCommands, isEmpty);
    });
  });
}
