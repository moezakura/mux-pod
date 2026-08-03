import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen input (G1-6b)', () {
    testWidgets('sends a special key via send-keys when connected', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.text('ESC'));
      await tester.pumpAndSettle();

      expect(client.sendKeysCommands, isNotEmpty);
      final last = client.sendKeysCommands.last;
      expect(last, contains('send-keys'));
      expect(last, contains('Escape'));
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
