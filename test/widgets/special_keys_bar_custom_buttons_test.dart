import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/special_keys_bar_harness.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'package:flutter_muxpod/widgets/custom_key_button_widget.dart';

void main() {
  group('SpecialKeysBar custom buttons', () {
    testWidgets('custom buttons render at token positions in order', (
      tester,
    ) async {
      final a = ck('ck_1_a', 'A');
      final b = ck('ck_2_b', 'B');
      await tester.pumpWidget(
        customHarness(
          customButtons: [a, b],
          row1Tokens: ['esc', ckToken('ck_1_a'), 'tab', ckToken('ck_2_b')],
        ),
      );
      await tester.pump();

      final customA = find.byWidgetPredicate(
        (w) => w is CustomKeyButtonWidget && w.button.id == 'ck_1_a',
      );
      final customB = find.byWidgetPredicate(
        (w) => w is CustomKeyButtonWidget && w.button.id == 'ck_2_b',
      );
      expect(customA, findsOneWidget);
      expect(customB, findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);

      final aX = tester.getTopLeft(find.text('A')).dx;
      final bX = tester.getTopLeft(find.text('B')).dx;
      expect(aX, lessThan(bX));
    });

    testWidgets('tapping a custom button fires onKeyPressed with text step', (
      tester,
    ) async {
      final pressed = <String>[];
      await tester.pumpWidget(
        customHarness(
          customButtons: [ck('ck_1_a', 'A')],
          row1Tokens: ['esc', ckToken('ck_1_a')],
          onKeyPressed: pressed.add,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('A'));
      await tester.pump();

      expect(pressed, ['x']);
    });

    testWidgets('long-pressing a custom button fires onCustomButtonEdit', (
      tester,
    ) async {
      CustomKeyButton? edited;
      await tester.pumpWidget(
        customHarness(
          customButtons: [ck('ck_1_a', 'A')],
          row1Tokens: ['esc', ckToken('ck_1_a')],
          onCustomButtonEdit: (b) => edited = b,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('A'));
      await tester.pump();

      expect(edited?.id, 'ck_1_a');
    });

    testWidgets(
      'pencil hosts on row 1 while the custom row is empty and fires onManageButtons',
      (tester) async {
        var managed = 0;
        await tester.pumpWidget(
          customHarness(onManageButtons: () => managed++),
        );
        await tester.pump();

        final pencil = find.byIcon(Icons.edit_outlined);
        expect(pencil, findsOneWidget);

        // Pencil button matches the row-1 button height (32) and is pinned
        // above row 2. Measure the button container, not the icon glyph.
        final pencilButton = find
            .ancestor(of: pencil, matching: find.byType(GestureDetector))
            .first;
        expect(tester.getSize(pencilButton).height, 32);
        expect(tester.getSize(pencilButton).width, 32);

        // Pencil is the trailing fixed element of row 1 (modifier row), so it
        // sits above row 2's navigation controls.
        final pencilY = tester.getTopLeft(pencil).dy;
        final row2Y = tester.getTopLeft(find.text('PgUp')).dy;
        expect(pencilY, lessThan(row2Y));

        await tester.tap(pencil);
        await tester.pump();

        expect(managed, 1);
      },
    );

    testWidgets('pencil moves to the custom row once that row has tokens', (
      tester,
    ) async {
      final a = ck('ck_1_a', 'A');
      await tester.pumpWidget(
        customHarness(customButtons: [a], row0Tokens: [ckToken(a.id)]),
      );
      await tester.pump();

      final pencil = find.byIcon(Icons.edit_outlined);
      // Exactly one: the legacy row-1 layout must drop its own pencil instead
      // of rendering a second one.
      expect(pencil, findsOneWidget);

      // Same row as the custom button, above the untouched modifier row.
      expect(
        tester.getTopLeft(pencil).dy,
        closeTo(tester.getTopLeft(find.text('A')).dy, 6),
      );
      expect(
        tester.getTopLeft(pencil).dy,
        lessThan(tester.getTopLeft(find.text('ESC')).dy),
      );
      // Row 1 keeps its default stretched layout.
      expect(find.text('ESC'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
    });

    testWidgets(
      'customized direct-input row renders only the tokens it holds',
      (tester) async {
        await tester.pumpWidget(
          customHarness(
            directInput: true,
            customButtons: [ck('ck_1_a', 'A')],
            row2Tokens: [ckToken('ck_1_a')],
          ),
        );
        await tester.pump();

        expect(find.text('A'), findsOneWidget);
        // Numbers are no longer auto-appended: rows render exactly what they
        // hold, subject to the mode skips.
        expect(find.text('1'), findsNothing);
        expect(find.text('2'), findsNothing);
        expect(find.text('3'), findsNothing);
        expect(find.text('4'), findsNothing);
      },
    );

    // Rows are interchangeable, so custom buttons are one height everywhere
    // (32); only the fixed nav glyph buttons keep their own 36x36 box.
    testWidgets('custom buttons render at 32px height in any row', (
      tester,
    ) async {
      await tester.pumpWidget(
        customHarness(
          customButtons: [ck('ck_1_a', 'A')],
          row2Tokens: [ckToken('ck_1_a')],
        ),
      );
      await tester.pump();

      final finder = find.byWidgetPredicate(
        (w) => w is CustomKeyButtonWidget && w.button.id == 'ck_1_a',
      );
      expect(finder, findsOneWidget);
      expect(tester.getSize(finder).height, 32);
    });

    testWidgets(
      'custom row-1 tokens render in a horizontal scroller without overflow',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          customHarness(
            width: 320,
            customButtons: [ck('ck_1_a', 'A')],
            row1Tokens: ['esc', ckToken('ck_1_a'), 'tab'],
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(horizontalScroller(), findsAtLeastNWidgets(1));
        expect(find.text('A'), findsOneWidget);
      },
    );

    testWidgets('custom button tap resets software modifiers', (tester) async {
      final keys = <String>[];
      final specials = <String>[];
      await tester.pumpWidget(
        customHarness(
          customButtons: [ck('ck_1_a', 'A')],
          row1Tokens: ['ctrl', 'slash', ckToken('ck_1_a')],
          onKeyPressed: keys.add,
          onSpecialKeyPressed: specials.add,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('CTRL'));
      await tester.pump();

      await tester.tap(find.text('A'));
      await tester.pump();
      expect(keys, ['x']);
      expect(specials, isEmpty);

      await tester.tap(find.text('/'));
      await tester.pump();
      expect(keys, contains('/'));
      expect(specials, isNot(contains('C-/')));
    });

    testWidgets('custom button key step dispatches onSpecialKeyPressed', (
      tester,
    ) async {
      final keys = <String>[];
      final specials = <String>[];
      final enterButton = CustomKeyButton(
        id: 'ck_1_enter',
        label: 'Enter',
        steps: const [
          CustomKeyStep(type: CustomKeyStepType.key, value: 'Enter'),
        ],
      );
      await tester.pumpWidget(
        customHarness(
          customButtons: [enterButton],
          row1Tokens: [ckToken(enterButton.id)],
          onKeyPressed: keys.add,
          onSpecialKeyPressed: specials.add,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Enter'));
      await tester.pump();

      expect(specials, ['Enter']);
      expect(keys, isEmpty);
    });
    testWidgets('row-0 custom button renders above the modifier row', (
      tester,
    ) async {
      await tester.pumpWidget(
        customHarness(
          customButtons: [ck('ck_1_a', 'A')],
          row0Tokens: [ckToken('ck_1_a')],
        ),
      );
      await tester.pump();

      final customY = tester.getTopLeft(find.text('A')).dy;
      final escY = tester.getTopLeft(find.text('ESC')).dy;
      expect(customY, lessThan(escY));
    });

    testWidgets('empty row-0 renders no extra top row', (tester) async {
      await tester.pumpWidget(customHarness());
      await tester.pump();

      expect(horizontalScroller(), findsNothing);
      expect(find.text('ESC'), findsOneWidget);
    });

    testWidgets(
      'tapping a row-0 custom button fires onKeyPressed with text step',
      (tester) async {
        final pressed = <String>[];
        await tester.pumpWidget(
          customHarness(
            customButtons: [ck('ck_1_a', 'A')],
            row0Tokens: [ckToken('ck_1_a')],
            onKeyPressed: pressed.add,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('A'));
        await tester.pump();

        expect(pressed, ['x']);
      },
    );
  });
}
