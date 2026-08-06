import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/file_browser/file_browser_screen.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';

import '../../helpers/terminal_test_scaffold.dart';

void main() {
  group('TerminalScreen public contracts', () {
    test('TERM-ENUM-001 exposes all scroll-mode sources', () {
      expect(ScrollModeSource.values, [
        ScrollModeSource.none,
        ScrollModeSource.manual,
        ScrollModeSource.tmux,
      ]);
    });

    test('TERM-SCREEN-002..003 keeps restoration and deep-link inputs', () {
      const screen = TerminalScreen(
        connectionId: 'c',
        sessionName: 's',
        lastWindowIndex: 2,
        lastPaneId: '%3',
        deepLinkWindowName: 'editor',
        deepLinkPaneIndex: 1,
      );
      expect(screen.connectionId, 'c');
      expect(screen.sessionName, 's');
      expect(screen.lastWindowIndex, 2);
      expect(screen.lastPaneId, '%3');
      expect(screen.deepLinkWindowName, 'editor');
      expect(screen.deepLinkPaneIndex, 1);
    });

    testWidgets('TERM-FILE-001 opens the file browser for the active pane', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.byTooltip('File Browser'));
      await tester.pumpAndSettle();

      expect(find.byType(FileBrowserScreen), findsOneWidget);
    });

    testWidgets(
      'TERM-SCREEN-002 polling view data reaches the terminal consumer',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          execOutputs: const {'capture-pane': 'screen-contract\n3,4,91,31\n'},
        );
        await tester.pump(const Duration(milliseconds: 150));

        final view = tester.widget<AnsiTextView>(find.byType(AnsiTextView));
        expect(view.text, contains('screen-contract'));
        expect(view.paneWidth, 91);
        expect(view.paneHeight, 31);
      },
    );

    testWidgets(
      'TERM-FILE-002..004 image action exposes gallery and camera sources',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(tester);

        await tester.tap(find.byIcon(Icons.image_outlined));
        await tester.pumpAndSettle();

        expect(find.text('Gallery'), findsOneWidget);
        expect(find.text('Camera'), findsOneWidget);
      },
    );

    testWidgets('TERM-DIALOG-002..006 navigation dialogs are reachable', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);

      await tester.tap(find.text('mysession'));
      await tester.pumpAndSettle();
      expect(find.text('Select Session'), findsOneWidget);
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();

      await tester.tap(find.text('shell'));
      await tester.pumpAndSettle();
      expect(find.text('Select Window'), findsOneWidget);
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pane 0'));
      await tester.pumpAndSettle();
      expect(find.text('Select Pane'), findsOneWidget);
    });
  });
}
