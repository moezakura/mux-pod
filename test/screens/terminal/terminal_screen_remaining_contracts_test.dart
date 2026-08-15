import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/image_transfer_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/widgets/multiplexer_tiles.dart';

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
      await tester.tap(find.text('Close'));
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

    group('TerminalScreen common selector sheets (T2 / 選択即閉じ)', () {
      testWidgets(
        'session selector lists all sessions and closes on selection',
        (tester) async {
          final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

          // session セグメントタップ → Select Session シート（M-6: タイトル統一）
          await tester.tap(find.text('mysession'));
          await tester.pumpAndSettle();
          expect(find.text('Select Session'), findsOneWidget);
          expect(find.text('mysession'), findsWidgets);
          expect(find.text('other'), findsOneWidget);

          // session タップ → 選択確定 + シート即閉じ（元 tmux 挙動）
          await tester.tap(find.text('other'));
          await tester.pumpAndSettle();
          expect(find.text('Select Session'), findsNothing);
          expect(find.text('Select Window'), findsNothing);
          final container = ProviderScope.containerOf(
            tester.element(find.byType(TerminalScreen)),
          );
          expect(container.read(tmuxProvider).activeSessionName, 'other');
          expect(
            client.execCommands.any((c) => c.contains('select-pane')),
            isTrue,
          );
        },
      );

      testWidgets(
        'window selector shows the current session windows and closes '
        'on selection',
        (tester) async {
          final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

          // window セグメントタップ → Select Window シート
          await tester.tap(find.text('shell'));
          await tester.pumpAndSettle();
          expect(find.text('Select Window'), findsOneWidget);
          expect(find.text('0: shell'), findsOneWidget);

          // window タップ → select-window 発行 + シート即閉じ
          await tester.tap(find.text('0: shell'));
          await tester.pumpAndSettle();
          expect(find.text('Select Window'), findsNothing);
          expect(find.text('Select Pane'), findsNothing);
          expect(
            client.execCommands.any(
              (c) => c.contains('select-window') && c.contains('mysession'),
            ),
            isTrue,
          );
        },
      );

      testWidgets('pane selector shows the active window panes and closes on '
          'selection', (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

        // pane セグメントタップ → Select Pane シート
        await tester.tap(find.text('Pane 0'));
        await tester.pumpAndSettle();
        expect(find.text('Select Pane'), findsOneWidget);
        expect(find.text('bash'), findsOneWidget);
        expect(find.text('vim'), findsOneWidget);

        // pane タップ → select-pane 発行 + シート即閉じ
        await tester.tap(find.text('vim'));
        await tester.pumpAndSettle();
        expect(find.text('Select Pane'), findsNothing);
        expect(
          client.execCommands.any(
            (c) => c.contains('select-pane') && c.contains('%1'),
          ),
          isTrue,
        );
      });

      testWidgets('H-1 highlight follows the active session/window/pane', (
        tester,
      ) async {
        await TerminalTestScaffold.pumpTerminalScreen(tester);

        // session セレクタ: アクティブ session（mysession）が強調される
        await tester.tap(find.text('mysession'));
        await tester.pumpAndSettle();
        final sessions = tester
            .widgetList<MultiplexerSessionTile>(
              find.byType(MultiplexerSessionTile),
            )
            .toList();
        expect(sessions, hasLength(2));
        expect(sessions[0].session.name, 'mysession');
        expect(sessions[0].isActive, isTrue);
        expect(sessions[1].session.name, 'other');
        expect(sessions[1].isActive, isFalse);

        // シートを閉じてから window セレクタを開く
        await tester.tapAt(const Offset(20, 100));
        await tester.pumpAndSettle();
        await tester.tap(find.text('shell'));
        await tester.pumpAndSettle();
        final windows = tester
            .widgetList<MultiplexerWindowTile>(
              find.byType(MultiplexerWindowTile),
            )
            .toList();
        expect(windows, hasLength(1));
        expect(windows[0].window.index, 0);
        expect(windows[0].isActive, isTrue);

        // シートを閉じてから pane セレクタを開く
        await tester.tapAt(const Offset(20, 100));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pane 0'));
        await tester.pumpAndSettle();
        final panes = tester
            .widgetList<MultiplexerPaneTile>(find.byType(MultiplexerPaneTile))
            .toList();
        expect(panes, hasLength(2));
        expect(panes[0].pane.id, '%0');
        expect(panes[0].isActive, isTrue);
        expect(panes[1].pane.id, '%1');
        expect(panes[1].isActive, isFalse);
      });

      testWidgets('mutation UI is available when mutations enabled (tmux)', (
        tester,
      ) async {
        await TerminalTestScaffold.pumpTerminalScreen(tester);

        // window シート: New Window / Resize Window ヘッダーボタン + PopupMenu
        await tester.tap(find.text('shell'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('New Window'), findsOneWidget);
        expect(find.byTooltip('Resize Window'), findsOneWidget);
        expect(find.byType(PopupMenuButton<String>), findsOneWidget);

        // シートを閉じて pane シートを開く: Resize Pane ヘッダーボタン
        await tester.tapAt(const Offset(20, 100));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pane 0'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Resize Pane'), findsOneWidget);
      });

      testWidgets('selection wires session/window/pane selectors', (
        tester,
      ) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

        // session 選択: シート即閉じ + session 切替
        await tester.tap(find.text('mysession'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('other'));
        await tester.pumpAndSettle();
        expect(find.text('Select Session'), findsNothing);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        expect(container.read(tmuxProvider).activeSessionName, 'other');
        expect(
          client.execCommands.any((c) => c.contains('select-pane')),
          isTrue,
        );

        // パンくずが更新され、window セグメント（logs）から window 選択
        await tester.tap(find.text('logs'));
        await tester.pumpAndSettle();
        expect(find.text('Select Window'), findsOneWidget);
        await tester.tap(find.text('0: logs'));
        await tester.pumpAndSettle();
        expect(find.text('Select Window'), findsNothing);
        expect(
          client.execCommands.any(
            (c) => c.contains('select-window') && c.contains('other'),
          ),
          isTrue,
        );

        // pane セグメントから pane 選択: tail で確定しシートが閉じる
        await tester.tap(find.text('Pane 0'));
        await tester.pumpAndSettle();
        expect(find.text('Select Pane'), findsOneWidget);
        await tester.tap(find.text('tail'));
        await tester.pumpAndSettle();
        expect(
          client.execCommands.any(
            (c) => c.contains('select-pane') && c.contains('%10'),
          ),
          isTrue,
        );
        expect(find.text('Select Pane'), findsNothing);
        // ポーリング/フェードタイマーを破棄してテストを終了する
        // （TERM-NAV-003/007 と同じライフサイクルパターン）。
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(milliseconds: 200));
      });
    });
  });
}
