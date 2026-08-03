import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';

import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen CRUD (G1-7c)', () {
    testWidgets('selecting another session updates active session', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      // Open the session selector by tapping the active session name.
      await tester.tap(find.text('mysession'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('other'));
      await tester.pumpAndSettle();

      expect(client.execCommands.any((c) => c.contains('select-pane')), isTrue);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final tmux = container.read(tmuxProvider);
      expect(tmux.activeSessionName, 'other');
    });

    testWidgets('session selection is a no-op when disconnected', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;
      await notifier.disconnect();

      await tester.tap(find.text('mysession'));
      await tester.pumpAndSettle();

      // The bottom sheet still opens, so 'other' is present.
      await tester.tap(find.text('other'));
      await tester.pumpAndSettle();

      expect(client.execCommands.any((c) => c.contains('select-pane')), isFalse);
      expect(container.read(tmuxProvider).activeSessionName, 'mysession');
    });
  });
}
