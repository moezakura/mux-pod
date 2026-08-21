import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/providers/custom_keys_provider.dart';
import 'package:flutter_muxpod/screens/custom_keys/custom_keys_screen.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    // Tall viewport so every strip (including the bottom shelf) is laid out
    // and hittable without scrolling.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CustomKeysScreen()),
      ),
    );
    // Flush the async SharedPreferences load.
    await tester.pump();
  }

  Future<void> addButton(
    WidgetTester tester,
    String label,
    String stepValue,
  ) async {
    await tester.tap(find.text('+ Add button'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('label-field')), label);
    await tester.enterText(find.byKey(const Key('step-value-0')), stepValue);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  /// Long-press a chip to start the drag, move to [to]'s centre and release.
  Future<void> dragChip(WidgetTester tester, Finder from, Finder to) async {
    final gesture = await tester.startGesture(tester.getCenter(from));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(to));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  String tokenOf(ProviderContainer container, String label) {
    final s = container.read(customKeysProvider);
    final b = s.buttons.firstWhere((b) => b.label == label);
    return 'ck:${b.id.substring(3)}';
  }

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
      expect(find.text('Layout — Custom Row'), findsOneWidget);
      expect(find.text('Layout — Row 1'), findsOneWidget);
      expect(find.text('Layout — Row 2'), findsOneWidget);
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

      // The per-row '+' pickers are gone; dragging replaces them.
      expect(find.byKey(const Key('row-0-add')), findsNothing);
      expect(find.byKey(const Key('row-1-add')), findsNothing);
      expect(find.byKey(const Key('row-2-add')), findsNothing);
    });

    testWidgets('custom row section renders its chips', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpScreen(tester, container);

      expect(find.text('Layout — Custom Row'), findsOneWidget);

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
      expect(s.row0, contains(token));
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
      expect(s.row0.first, second);
      expect(s.row0[1], first);
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
      expect(container.read(customKeysProvider).row0, contains(token));

      final id = container.read(customKeysProvider).buttons.single.id;
      await tester.tap(find.byKey(Key('delete-$id')));
      await tester.pumpAndSettle();

      expect(find.text('Doomed'), findsNothing);
      expect(container.read(customKeysProvider).buttons, isEmpty);
      expect(
        container.read(customKeysProvider).row0,
        CustomKeyRows.standardRow0,
      );
    });

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
      expect(s.row0.first, 'esc');
      expect(s.row1, isNot(contains('esc')));
      expect(s.row1.first, 'tab');
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
      expect(s.row0, CustomKeyRows.standardRow0);
      expect(s.row2.last, token);
      expect(s.row2.length, 10);
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
      expect(s.row0, [c, b, a]);

      // Drag C (the leading chip) to the trailing slot (index 3).
      await dragChip(
        tester,
        find.byKey(Key('chip-0-$c')),
        find.byKey(const Key('slot-0-3')),
      );

      s = container.read(customKeysProvider);
      expect(s.row0, [b, a, c]);
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
      expect(s.row1, isNot(contains('esc')));
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
      expect(s.row0.first, 'num1');
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
      // The old move sheet and per-row '+' picker are gone.
      expect(find.text('Move Left'), findsNothing);
      expect(find.text('Move Right'), findsNothing);
      expect(find.text('Move to Row 1'), findsNothing);
      expect(find.byKey(const Key('row-1-add')), findsNothing);
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
      expect(s.row0, contains(token));
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
      expect(container.read(customKeysProvider).row0, contains(token));

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
      expect(s.row0, CustomKeyRows.standardRow0);
      expect(s.row1, CustomKeyRows.standardRow1);
      expect(s.row2, CustomKeyRows.standardRow2);
      expect(find.text('Gone'), findsNothing);
    });
  });
}
