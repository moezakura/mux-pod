import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/special_keys_bar_harness.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';

void main() {
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
