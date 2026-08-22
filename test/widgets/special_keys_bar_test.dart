import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'package:flutter_muxpod/widgets/custom_key_button_widget.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

void main() {
  // Narrow-phone harness (#63): assert the toolbar does not overflow at a real
  // phone width and that page-navigation keys are present.
  Widget buildWidget({
    required bool directInputEnabled,
    VoidCallback? onImagePickRequested,
    List<String> row0Tokens = const <String>[],
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 320,
            child: SpecialKeysBar(
              onKeyPressed: (_) {},
              onSpecialKeyPressed: (_) {},
              onInputTap: () {},
              directInputEnabled: directInputEnabled,
              onDirectInputToggle: () {},
              onImagePickRequested: onImagePickRequested,
              rows: [
                row0Tokens,
                CustomKeyRows.standardRow1,
                CustomKeyRows.standardRow2,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Wide surface: assert the structural contract (a horizontal scroll view
  // wraps the direct-input arrow row) rather than pixel overflow. A narrow
  // width would trip an unrelated font-fallback overflow in the modifier row
  // under the test's default (non-monospace) font, which does not occur
  // on-device.
  Widget harness({
    required bool directInput,
    double width = 720,
    List<String> row0Tokens = const <String>[],
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
            child: SpecialKeysBar(
              onKeyPressed: (_) {},
              onSpecialKeyPressed: (_) {},
              onInputTap: () {},
              onImagePickRequested: () {},
              onDirectInputToggle: () {},
              directInputEnabled: directInput,
              hapticFeedback: false,
              rows: [
                row0Tokens,
                CustomKeyRows.standardRow1,
                CustomKeyRows.standardRow2,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Finder horizontalScroller() => find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
  );

  CustomKeyButton ck(String id, String label) => CustomKeyButton(
    id: id,
    label: label,
    steps: const [CustomKeyStep(type: CustomKeyStepType.text, value: 'x')],
  );

  String ckToken(String id) => 'ck:${id.substring(3)}';

  Widget customHarness({
    bool directInput = false,
    double width = 720,
    List<CustomKeyButton> customButtons = const [],
    List<String> row0Tokens = const <String>[],
    List<String>? row1Tokens,
    List<String>? row2Tokens,
    List<List<String>>? rows,
    void Function(CustomKeyButton)? onCustomButtonEdit,
    VoidCallback? onManageButtons,
    void Function(String)? onKeyPressed,
    void Function(String)? onSpecialKeyPressed,
    VoidCallback? onImagePickRequested,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
            child: SpecialKeysBar(
              onKeyPressed: onKeyPressed ?? (_) {},
              onSpecialKeyPressed: onSpecialKeyPressed ?? (_) {},
              onInputTap: () {},
              onImagePickRequested: onImagePickRequested,
              onDirectInputToggle: () {},
              directInputEnabled: directInput,
              hapticFeedback: false,
              customButtons: customButtons,
              rows:
                  rows ??
                  [
                    row0Tokens,
                    row1Tokens ?? CustomKeyRows.standardRow1,
                    row2Tokens ?? CustomKeyRows.standardRow2,
                  ],
              onCustomButtonEdit: onCustomButtonEdit,
              onManageButtons: onManageButtons,
            ),
          ),
        ),
      ),
    );
  }

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

  group('SpecialKeysBar direct input field', () {
    Finder directInputField() => find.byType(TextField);

    String visibleText(WidgetTester tester) {
      final field = tester.widget<TextField>(directInputField());
      return field.controller!.text.replaceAll('\u200B', '');
    }

    testWidgets('typed text stays visible and is sent exactly once', (
      tester,
    ) async {
      final keys = <String>[];
      await tester.pumpWidget(
        customHarness(directInput: true, onKeyPressed: keys.add),
      );
      await tester.pump();

      await tester.enterText(directInputField(), 'models');
      await tester.pump();

      // The field keeps the typed text visible (not cleared to the sentinel).
      expect(visibleText(tester), 'models');
      expect(keys, ['models']);
    });

    testWidgets('deleting text sends BSpace for each removed char', (
      tester,
    ) async {
      final keys = <String>[];
      final specials = <String>[];
      await tester.pumpWidget(
        customHarness(
          directInput: true,
          onKeyPressed: keys.add,
          onSpecialKeyPressed: specials.add,
        ),
      );
      await tester.pump();

      await tester.enterText(directInputField(), 'models');
      await tester.pump();
      expect(keys, ['models']);

      await tester.enterText(directInputField(), 'mode');
      await tester.pump();

      expect(specials.where((k) => k == 'BSpace').length, 2);
      expect(visibleText(tester), 'mode');
    });

    testWidgets('submit sends Enter and clears the field', (tester) async {
      final specials = <String>[];
      await tester.pumpWidget(
        customHarness(directInput: true, onSpecialKeyPressed: specials.add),
      );
      await tester.pump();

      await tester.enterText(directInputField(), 'models');
      await tester.pump();
      expect(visibleText(tester), 'models');

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(specials, contains('Enter'));
      expect(visibleText(tester), isEmpty);
    });
  });

  group('SpecialKeysBar row auto-scroll', () {
    testWidgets('row 1 scrolls to the end when a custom button is appended', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final a = ck('ck_1_a', 'A');
      final b = ck('ck_2_b', 'B');
      final standards = [
        'esc',
        'tab',
        'ctrl',
        'alt',
        'shift',
        'enter',
        'senter',
        'slash',
        'dash',
      ];
      final tokens = [...standards, ckToken('ck_1_a')];
      final tokensPlus = [...tokens, ckToken('ck_2_b')];

      Widget build(List<String> row1) =>
          customHarness(width: 320, customButtons: [a, b], row1Tokens: row1);

      await tester.pumpWidget(build(tokens));
      await tester.pump();

      // No scroll yet: the row starts at the left edge.
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(build(tokensPlus));
      await tester.pumpAndSettle();

      // The row-1 horizontal scroller auto-scrolled to reveal the new button.
      final scrolled = tester
          .widgetList<SingleChildScrollView>(horizontalScroller())
          .where((s) => s.controller != null && s.controller!.hasClients)
          .where((s) => s.controller!.offset > 0);
      expect(scrolled, isNotEmpty);
    });

    testWidgets('row 1 scrolls back to the start when a button is prepended', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final a = ck('ck_1_a', 'A');
      final b = ck('ck_2_b', 'B');
      final standards = [
        'esc',
        'tab',
        'ctrl',
        'alt',
        'shift',
        'enter',
        'senter',
        'slash',
        'dash',
      ];
      final tokens = [...standards, ckToken('ck_1_a')];
      final prepended = [ckToken('ck_2_b'), ...tokens];

      Widget build(List<String> row1) =>
          customHarness(width: 320, customButtons: [a, b], row1Tokens: row1);

      await tester.pumpWidget(build(tokens));
      await tester.pump();

      // Park the row away from the left edge first.
      final controller = tester
          .widgetList<SingleChildScrollView>(horizontalScroller())
          .map((s) => s.controller)
          .firstWhere((c) => c != null && c.hasClients)!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(controller.offset, greaterThan(0));

      await tester.pumpWidget(build(prepended));
      await tester.pumpAndSettle();

      // The new leading button is revealed instead of the row's tail.
      expect(controller.offset, 0);
    });
    testWidgets('row 0 scrolls back to the start when a button is prepended', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final buttons = [
        for (var i = 0; i < 8; i++) ck('ck_${i + 1}_c${i + 1}', 'K$i'),
      ];
      final extra = ck('ck_9_c9', 'K8');
      final allButtons = [...buttons, extra];
      final tokens = buttons.map((b) => ckToken(b.id)).toList();
      final prepended = [ckToken(extra.id), ...tokens];

      Widget build(List<String> row0) => customHarness(
        width: 320,
        customButtons: allButtons,
        row0Tokens: row0,
      );

      await tester.pumpWidget(build(tokens));
      await tester.pump();

      // Park the row away from the left edge first.
      final controller = tester
          .widgetList<SingleChildScrollView>(horizontalScroller())
          .map((s) => s.controller)
          .firstWhere((c) => c != null && c.hasClients)!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(controller.offset, greaterThan(0));

      await tester.pumpWidget(build(prepended));
      await tester.pumpAndSettle();

      // The new leading button is revealed instead of the row's tail.
      expect(controller.offset, 0);
    });
  });

  group('SpecialKeysBar dynamic rows', () {
    // Defends the rows contract: a user-created fourth row renders below the
    // third and its buttons work.
    testWidgets('a fourth row renders at the bottom and its token sends', (
      tester,
    ) async {
      final sent = <String>[];
      final a = ck('ck_9_z', 'Z');
      await tester.pumpWidget(
        customHarness(
          customButtons: [a],
          rows: [
            const <String>[],
            CustomKeyRows.standardRow1,
            CustomKeyRows.standardRow2,
            [ckToken(a.id)],
          ],
          onKeyPressed: sent.add,
        ),
      );
      await tester.pump();

      expect(find.text('Z'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Z')).dy,
        greaterThan(tester.getTopLeft(find.text('PgUp')).dy),
      );

      await tester.tap(find.text('Z'));
      await tester.pump();
      expect(sent, ['x']);
    });

    // Defends reachability: with no rows at all the editor entry point stays.
    testWidgets('an empty layout still shows exactly one pencil', (
      tester,
    ) async {
      var managed = 0;
      await tester.pumpWidget(
        customHarness(
          rows: const <List<String>>[],
          onManageButtons: () => managed++,
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.text('ESC'), findsNothing);
      expect(find.text('PgUp'), findsNothing);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump();
      expect(managed, 1);
    });
    // Defends that the legacy fast paths are keyed on row CONTENT, not on row
    // index: a default nav row keeps its stretched Input button at index 1,
    // where the nav row never used to be. (It cannot be tested at index 0
    // because the first rendering row hosts the pencil, which the legacy nav
    // layout has no slot for.)
    testWidgets('a default nav row keeps the legacy layout at any index', (
      tester,
    ) async {
      await tester.pumpWidget(
        customHarness(
          rows: [CustomKeyRows.standardRow1, CustomKeyRows.standardRow2],
        ),
      );
      await tester.pump();

      expect(find.text('Cmd'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('ESC')).dy,
        lessThan(tester.getTopLeft(find.text('PgUp')).dy),
      );
      // Both rows are on legacy paths, so no row needs a horizontal scroller.
      expect(horizontalScroller(), findsNothing);
    });
  });
}
