import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen input (G1-6b)', () {
    testWidgets('sends a special key via send-keys when connected', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.text('ESC'));
      await tester.pumpAndSettle();

      expect(client.sendKeysCommands, isNotEmpty);
      final last = client.sendKeysCommands.last;
      expect(last, contains('send-keys'));
      expect(last, contains('Escape'));
    });

    testWidgets('TERM-INPUT-007 special-key UI shows and expires its overlay', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      expect(find.text('ESC'), findsOneWidget);

      await tester.tap(find.text('ESC'));
      await tester.pump();
      expect(find.text('ESC'), findsNWidgets(2));

      await tester.pump(const Duration(milliseconds: 1499));
      expect(find.text('ESC'), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('ESC'), findsOneWidget);
    });

    testWidgets(
      'keeps tmux special-key syntax instead of treating ESC as literal text',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

        await tester.tap(find.text('ESC'));
        await tester.pumpAndSettle();

        final command = client.sendKeysCommands.last;
        expect(command, contains('Escape'));
        expect(command, isNot(contains(' -l Escape')));
      },
    );

    testWidgets('G1-6b TERM-INPUT-001 sends keyboard text literally', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      final before = client.sendKeysCommands.length;

      await tester.tap(find.byType(AnsiTextView));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      final typed = client.sendKeysCommands.skip(before).last;
      expect(typed, contains('send-keys -t %0 -l -- a'));
    });

    testWidgets('does not send keys when disconnected', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      final before = client.sendKeysCommands.length;

      client.setConnected(SshConnectionState.disconnected);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;
      notifier.state = notifier.state.copyWith(
        connectionState: SshConnectionState.disconnected,
      );

      await tester.tap(find.text('ESC'));
      await tester.pumpAndSettle();

      expect(client.sendKeysCommands.length, before);
    });
  });
}
