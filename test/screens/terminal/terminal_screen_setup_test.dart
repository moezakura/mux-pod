import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';

import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen setup (G1-6a)', () {
    testWidgets('connects and activates first session on success', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      expect(client.execCommands.any((c) => c.contains('tmux -V')), isTrue);
      expect(
        client.execCommands.any((c) => c.contains('list-panes -a')),
        isTrue,
      );
      expect(
        client.execCommands.any(
          (c) => c.contains('set-option') && c.contains('history-limit'),
        ),
        isTrue,
      );
      expect(
        client.execCommands.any(
          (c) => c.contains('send-keys') && c.contains('-l --'),
        ),
        isTrue,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final tmux = container.read(tmuxProvider);
      expect(tmux.activeSession?.name, 'mysession');
      expect(tmux.activePane?.id, '%0');
    });

    testWidgets('discovers tmux before it reads the session tree', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      final versionIndex = client.execCommands.indexWhere(
        (c) => c.contains('tmux -V'),
      );
      final treeIndex = client.execCommands.indexWhere(
        (c) => c.contains('list-panes -a'),
      );
      expect(versionIndex, greaterThanOrEqualTo(0));
      expect(treeIndex, greaterThan(versionIndex));
    });

    testWidgets('TERM-LIFE-013 refreshes the session tree every 10 seconds', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      client.execCommands.clear();

      await tester.pump(const Duration(milliseconds: 9999));
      expect(
        client.execCommands.any((command) => command.contains('list-panes -a')),
        isFalse,
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        client.execCommands.any((command) => command.contains('list-panes -a')),
        isTrue,
      );
    });

    testWidgets('TERM-LIFE-015 input boost schedules its poll at 50ms', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      await tester.tap(find.text('ESC'));
      client.execPersistentCommands.clear();

      await tester.pump(const Duration(milliseconds: 49));
      expect(client.execPersistentCommands, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        client.execPersistentCommands.any(
          (command) => command.contains('capture-pane'),
        ),
        isTrue,
      );
    });

    testWidgets('TERM-LIFE-017 unchanged polls reduce polling frequency', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      await tester.tap(find.text('ESC'));
      client.execPersistentCommands.clear();
      for (var interval = 0; interval < 10; interval++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final activePolls = client.execPersistentCommands.length;
      expect(activePolls, greaterThan(0));

      for (var poll = 0; poll < 30; poll++) {
        await tester.pump(const Duration(seconds: 2));
      }
      final before = client.execPersistentCommands.length;

      await tester.pump(const Duration(milliseconds: 500));
      expect(client.execPersistentCommands.length, before);
      expect(
        activePolls,
        greaterThan(client.execPersistentCommands.length - before),
      );
    });

    testWidgets('TERM-LIFE-024 reads password auth into SSH connect options', (
      tester,
    ) async {
      const connectionId = 'password-connection';
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connectionId: connectionId,
        connection: Connection(
          id: connectionId,
          name: 'Password Host',
          host: 'host',
          username: 'user',
          createdAt: DateTime(2026),
        ),
        secureStorageValues: const {
          'password_password-connection': 'secret-password',
        },
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;
      expect(notifier.lastConnectConnection?.id, connectionId);
      expect(notifier.lastConnectOptions?.password, 'secret-password');
      expect(notifier.lastConnectOptions?.privateKey, isNull);
    });

    testWidgets('TERM-LIFE-024 reads key auth into SSH connect options', (
      tester,
    ) async {
      const connectionId = 'key-connection';
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connectionId: connectionId,
        connection: Connection(
          id: connectionId,
          name: 'Key Host',
          host: 'host',
          username: 'user',
          authMethod: 'key',
          keyId: 'key-1',
          createdAt: DateTime(2026),
        ),
        secureStorageValues: const {
          'privatekey_key-1': 'PRIVATE KEY',
          'passphrase_key-1': 'key-passphrase',
        },
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;
      expect(notifier.lastConnectConnection?.id, connectionId);
      expect(notifier.lastConnectOptions?.privateKey, 'PRIVATE KEY');
      expect(notifier.lastConnectOptions?.passphrase, 'key-passphrase');
      expect(notifier.lastConnectOptions?.password, isNull);
    });

    testWidgets(
      'G1-6a poll command keeps content cursor and mode markers together',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
        client.execOutputQueues['capture-pane'] = ['marker-body\n7,8,90,30\n'];

        await tester.tap(find.text('ESC'));
        await tester.pump(const Duration(milliseconds: 60));

        final poll = client.execPersistentCommands.lastWhere(
          (c) => c.contains('capture-pane'),
        );
        expect(
          poll,
          allOf(
            contains('capture-pane'),
            contains('cursor_x'),
            contains('pane_mode'),
          ),
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        expect(container.read(tmuxProvider).activePane?.cursorX, 7);
        expect(container.read(tmuxProvider).activePane?.cursorY, 8);
      },
    );

    testWidgets('G1-6b focus-in is sent after setup and before polling', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      await tester.pump(const Duration(milliseconds: 150));

      final tree = client.execCommands.indexWhere(
        (c) => c.contains('list-panes -a'),
      );
      final focus = client.execCommands.indexWhere(
        (c) => c.contains('send-keys') && c.contains('-l --'),
      );
      final poll = client.execCommands.indexWhere(
        (c) => c.contains('capture-pane') && c.contains('pane_mode'),
      );
      expect(focus, greaterThan(tree));
      expect(poll, greaterThan(focus));
    });

    testWidgets(
      'TERM-SCREEN-003 deep link restores window and pane before focus and polling',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          deepLinkWindowName: 'shell',
          deepLinkPaneIndex: 1,
        );
        await tester.pump(const Duration(milliseconds: 150));

        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final tmux = container.read(tmuxProvider);
        expect(tmux.activeWindow?.name, 'shell');
        expect(tmux.activeWindowIndex, 0);
        expect(tmux.activePane?.id, '%1');

        final focus = client.execCommands.indexWhere(
          (command) =>
              command.contains('send-keys') &&
              command.contains('-t %1') &&
              command.contains('-l --'),
        );
        final poll = client.execCommands.indexWhere(
          (command) =>
              command.contains('capture-pane') &&
              command.contains('-t %1') &&
              command.contains('pane_mode'),
        );
        expect(focus, greaterThanOrEqualTo(0));
        expect(poll, greaterThan(focus));
      },
    );

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
