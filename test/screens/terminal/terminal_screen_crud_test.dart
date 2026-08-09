import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';

import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen CRUD (G1-7c)', () {
    testWidgets('TERM-CRUD session creation is orchestrated during setup', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        sessionName: 'created-by-screen',
      );

      final create = client.execCommands.indexWhere(
        (c) => c.contains('new-session') && c.contains('created-by-screen'),
      );
      expect(create, greaterThanOrEqualTo(0));
      expect(
        client.execCommands
            .skip(create + 1)
            .any((c) => c.contains('list-panes -a')),
        isTrue,
      );
    });

    testWidgets(
      'TERM-CRUD-001..002 creates a named window then refreshes tree',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

        await tester.tap(find.text('shell'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('New Window'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'build');
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        final create = client.execCommands.indexWhere(
          (c) => c.contains('new-window') && c.contains('build'),
        );
        expect(create, greaterThanOrEqualTo(0));
        expect(
          client.execCommands
              .skip(create + 1)
              .any((c) => c.contains('list-panes -a')),
          isTrue,
        );
      },
    );

    testWidgets('TERM-NAV-006 selects a pane and synchronizes tmux target', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.text('Pane 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('vim').last);
      await tester.pumpAndSettle();

      expect(
        client.execCommands.any(
          (c) => c.contains('select-pane') && c.contains('%1'),
        ),
        isTrue,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      expect(container.read(tmuxProvider).activePaneId, '%1');
    });

    testWidgets('TERM-CRUD-004..005 closes a pane only after confirmation', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.text('Pane 0'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('vim').last);
      await tester.pumpAndSettle();
      expect(find.text('Close Pane?'), findsOneWidget);
      expect(client.execCommands.any((c) => c.contains('kill-pane')), isFalse);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(
        client.execCommands.any(
          (c) => c.contains('kill-pane') && c.contains('%1'),
        ),
        isTrue,
      );
    });

    testWidgets('TERM-CRUD-008..009 renames a window through its action menu', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      await tester.tap(find.text('shell'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename Window'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'renamed');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(
        client.execCommands.any(
          (c) => c.contains('rename-window') && c.contains('renamed'),
        ),
        isTrue,
      );
    });

    testWidgets('TERM-CRUD-006..007 closes a window only after confirmation', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      await tester.tap(find.text('shell'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close Window'));
      await tester.pumpAndSettle();
      expect(find.text('Close Window?'), findsOneWidget);
      expect(
        client.execCommands.any((c) => c.contains('kill-window')),
        isFalse,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(client.execCommands.any((c) => c.contains('kill-window')), isTrue);
    });

    testWidgets('selecting another session updates active session', (
      tester,
    ) async {
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

    testWidgets('session selection is a no-op when disconnected', (
      tester,
    ) async {
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

      expect(
        client.execCommands.any((c) => c.contains('select-pane')),
        isFalse,
      );
      expect(container.read(tmuxProvider).activeSessionName, 'mysession');
    });
  });
}
