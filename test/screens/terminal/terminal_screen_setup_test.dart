import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';

import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen setup (G1-6a)', () {
    testWidgets('connects and activates first session on success', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      expect(client.execCommands.any((c) => c.contains('tmux -V')), isTrue);
      expect(client.execCommands.any((c) => c.contains('list-panes -a')), isTrue);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final tmux = container.read(tmuxProvider);
      expect(tmux.activeSession?.name, 'mysession');
      expect(tmux.activePane?.id, '%0');
    });

    testWidgets('shows error when connection is missing', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connectionId: 'missing',
      );

      expect(client.execCommands, isEmpty);
      expect(find.textContaining('Connection not found'), findsWidgets);
    });
  });
}
