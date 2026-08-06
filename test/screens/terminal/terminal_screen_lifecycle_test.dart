import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../helpers/fake_ssh_notifier.dart';

import '../../helpers/terminal_test_scaffold.dart';

class _RecordingWakelockPlatform extends WakelockPlusPlatformInterface {
  final toggles = <bool>[];

  @override
  Future<void> toggle({required bool enable}) async {
    toggles.add(enable);
  }

  @override
  Future<bool> get enabled async => toggles.isNotEmpty && toggles.last;
}

void main() {
  group('TerminalScreen lifecycle (G1-7d)', () {
    testWidgets('TERM-LIFE-007 applies keep-screen-on setting changes', (
      tester,
    ) async {
      final previous = WakelockPlusPlatformInterface.instance;
      final wakelock = _RecordingWakelockPlatform();
      WakelockPlusPlatformInterface.instance = wakelock;
      addTearDown(() => WakelockPlusPlatformInterface.instance = previous);

      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: const AppSettings(keepScreenOn: true),
      );
      expect(wakelock.toggles, contains(true));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      await container.read(settingsProvider.notifier).setKeepScreenOn(false);
      await tester.pump();
      expect(wakelock.toggles.last, isFalse);
    });

    testWidgets('TERM-LIFE-003 metrics changes debounce auto-resize', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: const AppSettings(
          keepScreenOn: false,
          adjustMode: 'autoResize',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      client.execCommands.clear();

      tester.view.physicalSize = const Size(900, 1600);
      tester.binding.handleMetricsChanged();
      await tester.pump(const Duration(milliseconds: 499));
      expect(
        client.execCommands.any((command) => command.contains('resize-window')),
        isFalse,
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        client.execCommands.any((command) => command.contains('resize-window')),
        isTrue,
      );
    });

    testWidgets('TERM-LIFE-021 disconnected poll attempts SSH reconnect', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;
      client.setConnected(SshConnectionState.disconnected);
      expect(notifier.reconnectCalls, 0);

      await tester.pump(const Duration(milliseconds: 100));
      expect(notifier.reconnectCalls, greaterThan(0));
    });
    testWidgets(
      'pause restores resized windows and resume keeps the screen stable',
      (tester) async {
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

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        // No crash after foregrounding.
        expect(find.byType(TerminalScreen), findsOneWidget);
      },
    );

    testWidgets(
      'pause does not restore windows when auto-resize was never used',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();

        expect(client.restoreWindowCommands, isEmpty);
      },
    );

    testWidgets(
      'TERM-LIFE-002..006 inactive restore is delayed and resume cancels it',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          settings: const AppSettings(
            keepScreenOn: false,
            adjustMode: 'autoResize',
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        client.restoreWindowCommands.clear();

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(client.restoreWindowCommands, isEmpty);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(client.restoreWindowCommands, isEmpty);
      },
    );

    testWidgets(
      'G1-7d TERM-LIFE-009..010 reconnect refreshes tree and flushes literal input',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;

        client.setConnected(SshConnectionState.disconnected);
        await tester.tap(find.byType(AnsiTextView));
        await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
        await tester.pump();
        final beforePoll = client.execPersistentCommands.length;

        client.setConnected(SshConnectionState.connected);
        notifier.onReconnectSuccess?.call();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(client.execPersistentCommands.length, greaterThan(beforePoll));
        expect(
          client.sendKeysCommands.any((c) => c.contains('-l -- q')),
          isTrue,
        );
      },
    );

    testWidgets('G1-7d TERM-LIFE-022 dispose detaches reconnect callbacks', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;
      expect(notifier.onReconnectSuccess, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(notifier.onReconnectSuccess, isNull);
      expect(notifier.onDisconnectDetected, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
