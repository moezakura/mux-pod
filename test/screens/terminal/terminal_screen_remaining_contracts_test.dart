import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/image_transfer_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';

import '../../fixtures/tmux/tmux_parser_fixtures.dart';
import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen remaining contracts', () {
    testWidgets('TERM-CRUD-003 split-pane uses the selected visual pane', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      await tester.tap(find.text('Pane 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('terminal-pane-layout-%0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('terminal-split-right-%0')));
      await tester.pumpAndSettle();
      expect(
        client.execCommands.any(
          (c) => c.contains('split-window') && c.contains('%0'),
        ),
        isTrue,
      );
    });

    testWidgets('TERM-INPUT-005 long-press swipe sends an arrow key', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      final center = tester.getCenter(
        find.byKey(const ValueKey('terminal-input-gesture')),
      );
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        client.sendKeysCommands.any((c) => c.contains('-- Right')),
        isTrue,
      );
    });

    testWidgets('TERM-NAV-003/007 two-pointer gesture selects adjacent pane', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      final target = find.byKey(const ValueKey('terminal-two-finger-gesture'));
      final center = tester.getCenter(target);
      final first = await tester.startGesture(
        center - const Offset(200, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(200, 0),
        pointer: 2,
      );
      await tester.pump();
      for (var step = 0; step < 8; step++) {
        await first.moveBy(const Offset(10, 0));
        await second.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      await first.up();
      await second.up();
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
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('TERM-RESIZE-004/006 pane chooser opens dialog and resizes', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      await tester.tap(find.text('Pane 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Resize Pane'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.text('Selected: Pane 0 (80x24)'), findsOneWidget);
      await tester.tap(find.text('Resize'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resize'));
      await tester.pumpAndSettle();
      expect(
        client.execCommands.any(
          (c) => c.contains('resize-pane') && c.contains('%0'),
        ),
        isTrue,
      );
    });

    testWidgets('TERM-RESIZE-005/007 window chooser opens dialog and resizes', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      await tester.tap(find.text('shell'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Resize Window'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.textContaining('Selected: shell'), findsOneWidget);
      await tester.tap(find.text('Resize'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resize'));
      await tester.pumpAndSettle();
      expect(
        client.execCommands.any(
          (c) => c.contains('resize-window') && c.contains('mysession:0'),
        ),
        isTrue,
      );
    });

    testWidgets('TERM-DIALOG-008..010 shows latency and reconnect status', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      expect(find.text('0ms'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;
      notifier.state = notifier.state.copyWith(
        isReconnecting: true,
        reconnectAttempt: 2,
      );
      await tester.pump();
      expect(find.text('Reconnecting (2)'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('TERM-DIALOG-011 confirms disconnect before closing SSH', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(find.text('Disconnect?'), findsOneWidget);
      expect(notifier.client, isNotNull);
      await tester.tap(find.text('Disconnect').last);
      await tester.pumpAndSettle();
      expect(notifier.client, isNull);
    });

    testWidgets('TERM-DIALOG-012 last pane termination disconnects', (
      tester,
    ) async {
      final onePaneTree = '${kFullTreeOutput.split('\x1e').first}\x1e';
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        execOutputs: {'list-panes -a': onePaneTree, 'list-sessions': ''},
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;
      await tester.tap(find.text('Pane 0'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('bash').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(notifier.client, isNull);
    });

    testWidgets('TERM-FILE-003 completed upload injects bracketed path', (
      tester,
    ) async {
      final image = FakeImageTransferNotifier()
        ..uploadResult = '/tmp/upload.png';
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        imageTransferNotifier: image,
        settings: const AppSettings(
          keepScreenOn: false,
          imageBracketedPaste: true,
        ),
      );
      await tester.tap(find.byIcon(Icons.image_outlined));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();
      image.emit(const ImageTransferState(phase: ImageTransferPhase.picking));
      await tester.pump();
      image.emit(
        ImageTransferState(
          phase: ImageTransferPhase.confirming,
          pickedImageBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
          pickedImageName: 'pixel.png',
          pendingRemotePath: '/tmp/pixel.png',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Upload Image'), findsOneWidget);
      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();
      expect(client.writtenData, contains('\x1b[200~/tmp/upload.png\x1b[201~'));
    });
  });
}
