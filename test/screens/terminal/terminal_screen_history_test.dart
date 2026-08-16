import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';

import '../../helpers/terminal_test_scaffold.dart';

String _pollSnapshot(String prefix, int lines, {int cursorY = 0}) =>
    '${List.generate(lines, (index) => '$prefix-$index').join('\n')}'
    '\n0,$cursorY,80,24\n';

Finder _verticalTerminalScrollable() => find.descendant(
  of: find.byType(AnsiTextView),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

void main() {
  group('TerminalScreen history (G1-7a)', () {
    testWidgets('TERM-SCROLL-001 terminal scrolling reveals bottom button', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        execOutputs: {
          'capture-pane': _pollSnapshot('scroll', 300, cursorY: 20),
        },
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      final scrollable = _verticalTerminalScrollable();
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0),
      );

      await tester.drag(scrollable, const Offset(0, -250));
      await tester.pump();
      expect(find.byIcon(Icons.keyboard_double_arrow_down), findsOneWidget);
    });

    testWidgets(
      'TERM-SCROLL-002/003 top overscroll loads deep history and enters scroll mode',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
        client.execOutputs = {
          '-S -100000': '${List.generate(160, (i) => 'deep-$i').join('\n')}\n',
          'capture-pane': _pollSnapshot('live', 100),
        };
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        final scrollable = _verticalTerminalScrollable();
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        client.execCommands.clear();
        await tester.drag(scrollable, const Offset(0, 300));
        await tester.pumpAndSettle();

        expect(
          client.execCommands.any(
            (command) =>
                command.contains('capture-pane') &&
                command.contains('-S -100000'),
          ),
          isTrue,
        );
        final terminal = tester.widget<AnsiTextView>(find.byType(AnsiTextView));
        expect(terminal.mode, TerminalMode.select);
        expect(terminal.text, contains('deep-0'));
        expect(terminal.text, contains('deep-159'));
      },
    );

    testWidgets('TERM-SCROLL-004 first content scrolls toward the caret', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        execOutputs: {'capture-pane': _pollSnapshot('caret', 120, cursorY: 20)},
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      final position = tester
          .state<ScrollableState>(_verticalTerminalScrollable())
          .position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, greaterThan(0));
    });

    testWidgets('scroll mode loads deep history with capture-pane -S', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Switch from Normal Mode to Select Mode.
      await tester.tap(find.text('Select Mode'));
      await tester.pumpAndSettle();

      expect(
        client.sendKeysCommands.any((c) => c.contains('copy-mode')),
        isTrue,
      );
      expect(
        client.execCommands.any(
          (c) => c.contains('capture-pane') && c.contains('-S -100000'),
        ),
        isTrue,
      );
    });

    testWidgets('TERM-COPY-001..002 exits copy mode with tmux cancel', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select Mode'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      // 3 ListTile UI: 'Select Mode' が選択モードとして表示される。
      expect(find.text('Select Mode'), findsOneWidget);
      // select から normal へ戻す（copy-mode cancel を検証）。
      await tester.tap(find.text('Normal Mode'));
      await tester.pumpAndSettle();

      expect(
        client.sendKeysCommands.any((c) => c.contains('-X cancel')),
        isTrue,
      );
    });

    testWidgets(
      'G1-7a poll updates cursor and tmux mode transitions automatically',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
        client.execOutputQueues['capture-pane'] = [
          'copy body\n11,12,100,40\ncopy-mode',
        ];

        await tester.tap(find.text('ESC'));
        await tester.pump(const Duration(milliseconds: 60));
        var container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        expect(container.read(tmuxProvider).activePane?.cursorX, 11);
        expect(container.read(tmuxProvider).activePane?.cursorY, 12);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();

        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();
        expect(find.text('Select Mode'), findsOneWidget);
        await tester.tapAt(const Offset(20, 100));
        await tester.pumpAndSettle();

        client.execOutputQueues['capture-pane'] = [
          'normal body\n13,14,101,41\n',
        ];
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 60));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();
        // 3 ListTile UI では 'Normal Mode' は常時表示のため、モード状態で検証する。
        expect(find.text('Normal Mode'), findsOneWidget);
        expect(
          tester.widget<AnsiTextView>(find.byType(AnsiTextView)).mode,
          TerminalMode.normal,
        );
        container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        expect(container.read(tmuxProvider).activePane?.cursorX, 13);
      },
    );

    testWidgets(
      'settings menu is reachable but copy-mode is skipped when disconnected',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
        client.setConnected(SshConnectionState.disconnected);

        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Select Mode'));
        await tester.pumpAndSettle();

        expect(
          client.sendKeysCommands.any((c) => c.contains('copy-mode')),
          isFalse,
        );
      },
    );
  });
}
