import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/special_keys_bar_harness.dart';

void main() {
  group('SpecialKeysBar', () {
    testWidgets(
      'direct input toolbar does not overflow at narrow phone width',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildWidget(directInputEnabled: true, onImagePickRequested: () {}),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        expect(find.text('PgUp'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
      },
    );

    testWidgets('command input label stays compact in non-direct toolbar', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget(directInputEnabled: false));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Cmd'), findsOneWidget);
      expect(find.text('Input...'), findsNothing);
    });

    // Regression: with direct input on, the arrow row gains fixed-width number
    // keys (1-4). The old fixed Row + Spacer overflowed on narrow phones; the
    // row is now wrapped in a horizontal scroll view so it never overflows.
    testWidgets('direct-input arrow row is horizontally scrollable', (
      tester,
    ) async {
      await tester.pumpWidget(harness(directInput: true));
      await tester.pump();

      expect(horizontalScroller(), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets(
      'default arrow row keeps the expanded Input button, no scroller',
      (tester) async {
        await tester.pumpWidget(harness(directInput: false));
        await tester.pump();

        expect(horizontalScroller(), findsNothing);
        expect(find.text('Cmd'), findsOneWidget);
      },
    );
    testWidgets(
      'default bar at 320 with image pick has no overflow and shows pencil',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildWidget(directInputEnabled: false, onImagePickRequested: () {}),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      },
    );
  });
  group('SpecialKeysBar arbitrary layout', () {
    testWidgets('a standard nav token in row0 renders in the top row', (
      tester,
    ) async {
      await tester.pumpWidget(
        customHarness(row0Tokens: const ['pgup'], row2Tokens: const <String>[]),
      );
      await tester.pump();

      expect(find.text('PgUp'), findsOneWidget);
      final pgupY = tester.getTopLeft(find.text('PgUp')).dy;
      final escY = tester.getTopLeft(find.text('ESC')).dy;
      expect(pgupY, lessThan(escY));
    });

    testWidgets('a custom token in row2 still renders there (regression)', (
      tester,
    ) async {
      await tester.pumpWidget(
        customHarness(
          customButtons: [ck('ck_1_a', 'A')],
          row2Tokens: [ckToken('ck_1_a')],
        ),
      );
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      final aY = tester.getTopLeft(find.text('A')).dy;
      final escY = tester.getTopLeft(find.text('ESC')).dy;
      expect(aY, greaterThan(escY));
    });

    testWidgets('reordered row1 without custom tokens honours the order', (
      tester,
    ) async {
      await tester.pumpWidget(
        customHarness(
          row1Tokens: const [
            'tab',
            'esc',
            'ctrl',
            'alt',
            'shift',
            'enter',
            'senter',
            'slash',
            'dash',
          ],
        ),
      );
      await tester.pump();

      final tabX = tester.getTopLeft(find.text('TAB')).dx;
      final escX = tester.getTopLeft(find.text('ESC')).dx;
      expect(tabX, lessThan(escX));
    });

    testWidgets('row1 reduced to a single token renders only that token', (
      tester,
    ) async {
      await tester.pumpWidget(customHarness(row1Tokens: const ['esc']));
      await tester.pump();

      expect(find.text('ESC'), findsOneWidget);
      expect(find.text('TAB'), findsNothing);
      expect(find.text('CTRL'), findsNothing);
      expect(find.text('ALT'), findsNothing);
    });

    testWidgets('empty row1 renders no modifier row and keeps the pencil', (
      tester,
    ) async {
      await tester.pumpWidget(customHarness(row1Tokens: const <String>[]));
      await tester.pump();

      expect(find.text('ESC'), findsNothing);
      expect(find.text('TAB'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('num1 in row1 renders only when direct input is enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        customHarness(
          directInput: true,
          row1Tokens: const ['num1'],
          row2Tokens: const <String>[],
        ),
      );
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      await tester.pumpWidget(
        customHarness(
          directInput: false,
          row1Tokens: const ['num1'],
          row2Tokens: const <String>[],
        ),
      );
      await tester.pump();
      expect(find.text('1'), findsNothing);
    });

    testWidgets('input in row0 renders only when direct input is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        customHarness(
          directInput: false,
          row0Tokens: const ['input'],
          row2Tokens: const <String>[],
        ),
      );
      await tester.pump();
      expect(find.text('Cmd'), findsOneWidget);

      await tester.pumpWidget(
        customHarness(
          directInput: true,
          row0Tokens: const ['input'],
          row2Tokens: const <String>[],
        ),
      );
      await tester.pump();
      expect(find.text('Cmd'), findsNothing);
    });
  });
}
