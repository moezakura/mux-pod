import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/providers/custom_keys_provider.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'helpers/custom_keys_screen_pump.dart';

void main() {
  group('CustomKeysScreen', () {
    testWidgets('empty state shows headers and default layout chips', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      expect(find.text('Custom Buttons'), findsOneWidget);
      expect(find.text('Buttons'), findsOneWidget);
      expect(find.text('Layout — Row 1'), findsOneWidget);
      expect(find.text('Layout — Row 2'), findsOneWidget);
      expect(find.text('Layout — Row 3'), findsOneWidget);
      expect(find.text('Unused'), findsOneWidget);
      expect(
        find.text('Drag buttons here to hide them from the bar.'),
        findsOneWidget,
      );

      // Default row 1 standard chips (tokenLabel casing).
      expect(find.text('ESC'), findsOneWidget);
      expect(find.text('TAB'), findsOneWidget);
      expect(find.text('ENTER'), findsOneWidget);
      // Default row 2 standard chips.
      expect(find.text('PgUp'), findsOneWidget);
      expect(find.text('Right'), findsOneWidget);
      // The direct-input extras default onto the unused shelf.
      expect(find.byKey(const Key('chip-shelf-num1')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // Each row header offers "new button in this row" and "delete row".
      expect(find.byKey(const Key('row-0-add')), findsOneWidget);
      expect(find.byKey(const Key('row-2-delete')), findsOneWidget);
      // An empty row says why it is invisible in the bar.
      expect(find.text('Empty — hidden in the bar'), findsOneWidget);
    });
    testWidgets('custom row section renders its chips', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      expect(find.text('Layout — Row 1'), findsOneWidget);

      await addButton(tester, 'Top Chip', 't');
      final token = tokenOf(container, 'Top Chip');
      expect(find.byKey(Key('chip-0-$token')), findsOneWidget);
    });
    testWidgets('add button appears in list and row 0', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await addButton(tester, 'My Button', 'hello');

      // '+ Add button' now auto-places the button on the custom (top) row.
      final token = tokenOf(container, 'My Button');
      final s = container.read(customKeysProvider);
      expect(s.buttons.single.label, 'My Button');
      expect(s.rows[0], contains(token));
      expect(s.unplacedButtons(), isEmpty);

      // Appears in the library list and in the row 0 chip.
      expect(find.text('My Button'), findsNWidgets(2));
      expect(find.text("'hello'"), findsOneWidget);
    });
    testWidgets('add button lands at the head of the custom row', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await addButton(tester, 'First', '1');
      await addButton(tester, 'Second', '2');

      final first = tokenOf(container, 'First');
      final second = tokenOf(container, 'Second');
      final s = container.read(customKeysProvider);
      expect(s.rows[0].first, second);
      expect(s.rows[0][1], first);
      expect(s.unplacedButtons(), isEmpty);
    });
    testWidgets('edit button pre-filled then save updates', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await addButton(tester, 'Original', 'first');
      // Open the editor from the library list tile (the chip shares the label).
      await tester.tap(find.widgetWithText(ListTile, 'Original'));
      await tester.pumpAndSettle();

      final labelField = tester.widget<TextField>(
        find.byKey(const Key('label-field')),
      );
      expect(labelField.controller!.text, 'Original');
      final valueField = tester.widget<TextField>(
        find.byKey(const Key('step-value-0')),
      );
      expect(valueField.controller!.text, 'first');

      await tester.enterText(find.byKey(const Key('label-field')), 'Renamed');
      await tester.enterText(find.byKey(const Key('step-value-0')), 'second');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Renamed'), findsNWidgets(2));
      expect(find.text('Original'), findsNothing);
      expect(
        container.read(customKeysProvider).buttons.single.label,
        'Renamed',
      );
      expect(
        container.read(customKeysProvider).buttons.single.steps.single.value,
        'second',
      );
    });
    testWidgets('delete removes from list and from layout tokens', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await addButton(tester, 'Doomed', 'x');
      // '+ Add button' auto-places it on the custom (top) row.
      final token = tokenOf(container, 'Doomed');
      expect(container.read(customKeysProvider).rows[0], contains(token));

      final id = container.read(customKeysProvider).buttons.single.id;
      await tester.tap(find.byKey(Key('delete-$id')));
      await tester.pumpAndSettle();

      expect(find.text('Doomed'), findsNothing);
      expect(container.read(customKeysProvider).buttons, isEmpty);
      expect(container.read(customKeysProvider).rows[0], <String>[]);
    });
    testWidgets('persists across provider recreation', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await addButton(tester, 'Persist Me', 'abc');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );

      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      fresh.read(customKeysProvider); // triggers async load
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );

      final s = fresh.read(customKeysProvider);
      expect(s.buttons.single.label, 'Persist Me');
    });
    testWidgets('edit placed button save unchanged keeps it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await addButton(tester, 'Keep', 'same');
      final token = tokenOf(container, 'Keep');

      // Open the editor from the library list tile (the chip shares the label).
      await tester.tap(find.widgetWithText(ListTile, 'Keep'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final s = container.read(customKeysProvider);
      expect(s.buttons.single.label, 'Keep');
      expect(s.buttons.single.steps.single.value, 'same');
      expect(s.rows[0], contains(token));
      expect(find.text('Keep'), findsNWidgets(2));
    });
    testWidgets('delete from edit dialog removes button and tokens', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      await addButton(tester, 'Gone', 'g');
      final token = tokenOf(container, 'Gone');
      expect(container.read(customKeysProvider).rows[0], contains(token));

      // Open the editor from the library list tile.
      await tester.tap(find.widgetWithText(ListTile, 'Gone'));
      await tester.pumpAndSettle();

      // Delete → confirmation dialog → confirm.
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

      final s = container.read(customKeysProvider);
      expect(s.buttons, isEmpty);
      expect(s.rows[0], <String>[]);
      expect(s.rows[1], CustomKeyRows.standardRow1);
      expect(s.rows[2], CustomKeyRows.standardRow2);
      expect(find.text('Gone'), findsNothing);
    });

    // Defends the add-row contract: a new empty strip appears at the bottom and
  });
}
