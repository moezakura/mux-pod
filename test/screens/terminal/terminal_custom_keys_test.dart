import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/providers/custom_keys_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

import '../../helpers/terminal_test_scaffold.dart';

void main() {
  Map<String, Object> seedPrefs() => {
    'custom_key_buttons_v1': jsonEncode([
      {
        'id': 'ck_0001_dead',
        'label': 'Del Me',
        'steps': [
          {'type': 'text', 'value': 'hi'},
        ],
      },
    ]),
    'custom_key_rows_v1': jsonEncode([
      <String>[],
      ['ck:0001_dead'],
      CustomKeyRows.standardRow2,
    ]),
  };

  // pumpTerminalScreen resets SharedPreferences to empty before pumping, so
  // re-seed and invalidate the notifier to reload the rows from prefs.
  Future<ProviderContainer> seedAndReload(
    WidgetTester tester,
    Map<String, Object> prefs,
  ) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalScreen)),
    );
    container.invalidate(customKeysProvider);
    await tester.pumpAndSettle();
    return container;
  }

  group('TerminalScreen custom key buttons', () {
    testWidgets('long-press → editor delete removes the button', (
      tester,
    ) async {
      // Seed the prefs the real CustomKeysNotifier reads on load.
      SharedPreferences.setMockInitialValues(seedPrefs());

      await TerminalTestScaffold.pumpTerminalScreen(tester);

      // pumpTerminalScreen resets SharedPreferences to empty before pumping, so
      // re-seed and invalidate the notifier to reload the button from prefs.
      SharedPreferences.setMockInitialValues(seedPrefs());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      container.invalidate(customKeysProvider);
      await tester.pumpAndSettle();

      // The custom button shows in the top row of the special keys bar.
      expect(find.text('Del Me'), findsOneWidget);

      await tester.longPress(find.text('Del Me'));
      await tester.pumpAndSettle();

      // Editor dialog: delete → confirm.
      expect(find.byKey(const Key('dialog-delete')), findsOneWidget);
      await tester.tap(find.byKey(const Key('dialog-delete')));
      await tester.pumpAndSettle();

      expect(find.text('Delete button?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(AlertDialog, 'Delete button?'),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();

      final state = container.read(customKeysProvider);
      expect(state.buttons, isEmpty);
      expect(state.rows[0].contains('ck:0001_dead'), isFalse);
      expect(state.rows[1].contains('ck:0001_dead'), isFalse);
      expect(state.rows[2].contains('ck:0001_dead'), isFalse);
    });
    testWidgets('standard token seeded into row0 renders in the terminal bar', (
      tester,
    ) async {
      // Defends Bar contract: rows are authoritative end to end — a standard
      // token may live in any row ('esc', normally row 1, is placed in row 0).
      final prefs = <String, Object>{
        'custom_key_rows_v1': jsonEncode([
          ['esc'],
          <String>[],
          <String>[],
        ]),
      };
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      await seedAndReload(tester, prefs);

      expect(
        find.descendant(
          of: find.byType(SpecialKeysBar),
          matching: find.text('ESC'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'empty row1 renders no modifier row while the pencil stays reachable',
      (tester) async {
        // Defends Bar contract: an empty rendered row renders nothing, and the
        // manage (pencil) button pins to the first row that renders (row 2 here).
        final prefs = <String, Object>{
          'custom_key_rows_v1': jsonEncode([
            <String>[],
            <String>[],
            CustomKeyRows.standardRow2,
          ]),
        };
        await TerminalTestScaffold.pumpTerminalScreen(tester);
        await seedAndReload(tester, prefs);

        // Row 1 is the modifier row: its tokens (ESC/TAB) must not render.
        expect(
          find.descendant(
            of: find.byType(SpecialKeysBar),
            matching: find.text('ESC'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(SpecialKeysBar),
            matching: find.text('TAB'),
          ),
          findsNothing,
        );
        // Row 2 still renders, and the pencil is pinned to it.
        expect(
          find.descendant(
            of: find.byType(SpecialKeysBar),
            matching: find.text('PgUp'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(SpecialKeysBar),
            matching: find.byIcon(Icons.edit_outlined),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a fourth user-created row renders and sends in the terminal', (
      tester,
    ) async {
      // Defends the dynamic-rows contract end to end: a layout the user built
      // with "+ Add row" reaches the bar, and its button sends its steps.
      final prefs = <String, Object>{
        'custom_key_buttons_v1': jsonEncode([
          {
            'id': 'ck_0042_row4',
            'label': 'Row4',
            'steps': [
              {'type': 'text', 'value': 'from_row_four'},
            ],
          },
        ]),
        'custom_key_rows_v1': jsonEncode([
          <String>[],
          CustomKeyRows.standardRow1,
          CustomKeyRows.standardRow2,
          ['ck:0042_row4'],
        ]),
      };
      final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
      await seedAndReload(tester, prefs);

      final button = find.descendant(
        of: find.byType(SpecialKeysBar),
        matching: find.text('Row4'),
      );
      expect(button, findsOneWidget);
      // Below the navigation row, i.e. it really is a fourth row.
      expect(
        tester.getTopLeft(button).dy,
        greaterThan(
          tester
              .getTopLeft(
                find.descendant(
                  of: find.byType(SpecialKeysBar),
                  matching: find.text('PgUp'),
                ),
              )
              .dy,
        ),
      );

      await tester.tap(button);
      await tester.pumpAndSettle();

      final sent = client.sendKeysCommands
          .where((c) => c.contains('from_row_four'))
          .toList();
      expect(sent.length, 1);
    });
  });
}
