import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/providers/custom_keys_provider.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'helpers/custom_keys_screen_pump.dart';

void main() {
  group('CustomKeysScreen', () {
    testWidgets('standard token drags from row 1 to row 0 index 0', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      // Drag ESC out of row 1 into the leading slot of the custom row.
      await dragChip(
        tester,
        find.byKey(const Key('chip-1-esc')),
        find.byKey(const Key('slot-0-0')),
      );

      final s = container.read(customKeysProvider);
      expect(s.rows[0].first, 'esc');
      expect(s.rows[1], isNot(contains('esc')));
      expect(s.rows[1].first, 'tab');
    });
    testWidgets('custom chip drags from row 0 to row 2 trailing slot', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await addButton(tester, 'Wanderer', 'w');
      final token = tokenOf(container, 'Wanderer');

      // Row 2 keeps its 9 default standard tokens, so its trailing slot is 9.
      await dragChip(
        tester,
        find.byKey(Key('chip-0-$token')),
        find.byKey(const Key('slot-2-9')),
      );

      final s = container.read(customKeysProvider);
      expect(s.rows[0], <String>[]);
      expect(s.rows[2].last, token);
      expect(s.rows[2].length, 10);
    });
    testWidgets('within-row drag to a later slot reorders', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await addButton(tester, 'A', 'a');
      await addButton(tester, 'B', 'b');
      await addButton(tester, 'C', 'c');
      final a = tokenOf(container, 'A');
      final b = tokenOf(container, 'B');
      final c = tokenOf(container, 'C');
      var s = container.read(customKeysProvider);
      expect(s.rows[0], [c, b, a]);

      // Drag C (the leading chip) to the trailing slot (index 3).
      await dragChip(
        tester,
        find.byKey(Key('chip-0-$c')),
        find.byKey(const Key('slot-0-3')),
      );

      s = container.read(customKeysProvider);
      expect(s.rows[0], [b, a, c]);
    });
    testWidgets('chip drags onto shelf and becomes unused', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      // Drag a standard row-1 chip onto the shelf.
      await dragChip(
        tester,
        find.byKey(const Key('chip-1-esc')),
        find.byKey(const Key('slot-shelf')),
      );

      final s = container.read(customKeysProvider);
      expect(s.rows[1], isNot(contains('esc')));
      expect(s.unusedTokens(), contains('esc'));
      expect(find.byKey(const Key('chip-shelf-esc')), findsOneWidget);
    });
    testWidgets('chip drags out of the shelf into a row', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      // num1 starts unused on the shelf; drag it into row 0's leading slot.
      await dragChip(
        tester,
        find.byKey(const Key('chip-shelf-num1')),
        find.byKey(const Key('slot-0-0')),
      );

      final s = container.read(customKeysProvider);
      expect(s.rows[0].first, 'num1');
      expect(s.unusedTokens(), isNot(contains('num1')));
    });
    testWidgets('tapping a custom chip opens the editor', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await addButton(tester, 'Chip Edit', 'x');
      final token = tokenOf(container, 'Chip Edit');

      await tester.tap(find.byKey(Key('chip-0-$token')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('label-field')), findsOneWidget);
      // The old move sheet and insert picker are gone; dragging replaces them.
      expect(find.text('Move Left'), findsNothing);
      expect(find.text('Move Right'), findsNothing);
      expect(find.text('Move to Row 1'), findsNothing);
    });
    testWidgets('+ Add row appends a strip that accepts a chip', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await tester.tap(find.byKey(const Key('add-row')));
      await tester.pumpAndSettle();

      expect(find.text('Layout — Row 4'), findsOneWidget);
      expect(container.read(customKeysProvider).rows.length, 4);

      await dragChip(
        tester,
        find.byKey(const Key('chip-1-esc')),
        find.byKey(const Key('slot-3-0')),
      );

      expect(container.read(customKeysProvider).rows[3], ['esc']);
      expect(
        container.read(customKeysProvider).rows[1].contains('esc'),
        isFalse,
      );
    });

    testWidgets('the add-row tile is disabled at maxRows', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      for (
        var i = container.read(customKeysProvider).rows.length;
        i < CustomKeyRows.maxRows;
        i++
      ) {
        await tester.tap(find.byKey(const Key('add-row')));
        await tester.pumpAndSettle();
      }

      expect(
        container.read(customKeysProvider).rows.length,
        CustomKeyRows.maxRows,
      );
      // At maxRows the tile can sit below the fold; scroll it in before reading.
      await tester.scrollUntilVisible(
        find.byKey(const Key('add-row')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final button = tester.widget<TextButton>(
        find.byKey(const Key('add-row')),
      );
      expect(button.onPressed, isNull);
    });

    // Defends the delete-row contract: the strip goes, the chips come back as
    testWidgets('deleting a row frees its chips and renumbers headers', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      // Row 2 (index 1) is the modifier row.
      await tester.tap(find.byKey(const Key('row-1-delete')));
      await tester.pumpAndSettle();

      expect(container.read(customKeysProvider).rows.length, 2);
      expect(find.text('Layout — Row 3'), findsNothing);
      expect(
        container.read(customKeysProvider).unusedTokens(),
        containsAll(CustomKeyRows.standardRow1),
      );
      // The freed chip is reachable on the shelf.
      expect(find.byKey(const Key('chip-shelf-esc')), findsOneWidget);
    });

    // Defends the empty-layout edge: every row can be deleted and a row can be
    testWidgets('all rows can be deleted and one added back', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('row-0-delete')));
        await tester.pumpAndSettle();
      }
      expect(container.read(customKeysProvider).rows, isEmpty);
      expect(find.text('Layout — Row 1'), findsNothing);

      await tester.tap(find.byKey(const Key('add-row')));
      await tester.pumpAndSettle();
      expect(container.read(customKeysProvider).rows, [<String>[]]);
      expect(find.text('Layout — Row 1'), findsOneWidget);
    });

    // The reported bug: a button created while looking at row N must land in
    // row N, not in the top row (an empty new row renders nothing in the bar,
    testWidgets('the row header + creates the button in that row', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await tester.tap(find.byKey(const Key('add-row')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('row-3-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('label-field')), 'InRow4');
      await tester.enterText(find.byKey(const Key('step-value-0')), 'x');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final s = container.read(customKeysProvider);
      final token = tokenOf(container, 'InRow4');
      expect(s.rows[3], [token]);
      expect(s.rows[0], isEmpty);
      expect(s.unplacedButtons(), isEmpty);
    });

    testWidgets('+ Add button still lands at the head of the top row', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await addButton(tester, 'TopOne', 'a');
      await addButton(tester, 'TopTwo', 'b');

      final s = container.read(customKeysProvider);
      expect(s.rows[0], [
        tokenOf(container, 'TopTwo'),
        tokenOf(container, 'TopOne'),
      ]);
    });
  });
}
