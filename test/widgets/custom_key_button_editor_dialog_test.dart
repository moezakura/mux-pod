import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/custom_key_button_dialog_open.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'package:flutter_muxpod/widgets/dialogs/custom_key_button_editor_dialog.dart';

void main() {
  group('CustomKeyButtonEditorDialog', () {
    testWidgets(
      'step value field stays full-width and shows typed text at 2x text scale',
      (tester) async {
        // Regression: with a large system font scale the old single-row step
        // layout crushed the value field into a tiny square (dropdown + icons
        // grew and squeezed the Expanded field). The field must keep a usable
        // width so typed text is visible.
        await tester.binding.setSurfaceSize(const Size(411, 891));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(411, 891),
              devicePixelRatio: 1,
              textScaler: TextScaler.linear(2.0),
            ),
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      showDialog<(String, List<CustomKeyStep>)>(
                        context: context,
                        builder: (context) => CustomKeyButtonEditorDialog(
                          initialLabel: 'B',
                          initialSteps: const [
                            CustomKeyStep(
                              type: CustomKeyStepType.text,
                              value: '',
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final field = find.byKey(const Key('step-value-0'));
        expect(field, findsOneWidget);
        // Full-width field, not a crushed square: wider than tall, and wide
        // enough to show typed text at 2x scale.
        final size = tester.getSize(field);
        expect(size.width, greaterThan(200));
        expect(size.width, greaterThan(size.height));

        await tester.enterText(field, 'models');
        await tester.pump();
        final editable = tester.widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        expect(editable.controller.text, 'models');
      },
    );

    testWidgets('step actions are inset from the value field edges', (
      tester,
    ) async {
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
        ],
        onResult: (_) {},
      );

      final field = tester.getRect(find.byKey(const Key('step-value-0')));
      final dropdown = tester.getRect(find.byKey(const Key('step-type-0')));
      final delete = tester.getRect(find.byKey(const Key('step-delete-0')));

      // Trailing icons must not hug the dialog edge, and the type selector
      // lines up with the field's content inset.
      expect(field.right - delete.right, closeTo(8, 0.5));
      expect(dropdown.left - field.left, closeTo(16, 0.5));
      expect(delete.right, lessThan(field.right));
    });

    testWidgets('step actions stay inside the dialog on a narrow screen', (
      tester,
    ) async {
      // 308dp wide (small phone / enlarged display size) at 1.3x text scale:
      // the type selector must shrink instead of the Row overflowing and
      // painting the trailing actions outside the dialog card.
      tester.view.physicalSize = const Size(308 * 3, 700 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<(String, List<CustomKeyStep>)>(
                    context: context,
                    builder: (_) => const CustomKeyButtonEditorDialog(
                      initialLabel: 'My Button',
                      initialSteps: [
                        CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
                      ],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final field = tester.getRect(find.byKey(const Key('step-value-0')));
      final delete = tester.getRect(find.byKey(const Key('step-delete-0')));
      final up = tester.getRect(find.byKey(const Key('step-up-0')));
      expect(field.right - delete.right, closeTo(8, 0.5));
      expect(up.left, greaterThan(field.left));
    });

    testWidgets('type label stays legible on a phone-width dialog', (
      tester,
    ) async {
      // 411dp phone at 2x text scale: the dialog content box (~283px) barely
      // fits the row's fixed parts, so the clamped selector must still keep a
      // readable label instead of collapsing to a bare arrow.
      tester.view.physicalSize = const Size(411 * 3, 891 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<(String, List<CustomKeyStep>)>(
                    context: context,
                    builder: (_) => const CustomKeyButtonEditorDialog(
                      initialLabel: 'My Button',
                      initialSteps: [
                        CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
                      ],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final field = tester.getRect(find.byKey(const Key('step-value-0')));
      final delete = tester.getRect(find.byKey(const Key('step-delete-0')));
      expect(delete.right, lessThan(field.right));
      // Action tap targets are font-independent (40px), so the row's footprint
      // does not grow with the system font.
      expect(delete.width, closeTo(40, 0.5));
      // The selected type stays legible instead of ellipsising to nothing.
      expect(tester.getSize(find.text('Text')).width, greaterThan(30));
    });

    testWidgets('delete, cancel and save share one horizontal row', (
      tester,
    ) async {
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
        ],
        onDelete: () {},
        onResult: (_) {},
      );

      final delete = tester.getRect(find.text('Delete'));
      final cancel = tester.getRect(find.text('Cancel'));
      final save = tester.getRect(find.text('Save'));
      // Same baseline row, left-to-right order, Delete pinned to the left.
      expect(cancel.center.dy, closeTo(delete.center.dy, 1));
      expect(save.center.dy, closeTo(delete.center.dy, 1));
      expect(delete.right, lessThan(cancel.left));
      expect(cancel.right, lessThan(save.left));
      // Labels are shown whole: a shrunk cell used to render "Dele"/"Can"/"S".
      for (final label in ['Delete', 'Cancel', 'Save']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(
          paragraph.size.width,
          closeTo(paragraph.getMaxIntrinsicWidth(double.infinity), 0.5),
          reason: '$label is clipped',
        );
      }
    });

    testWidgets('action labels stay whole on a narrow dialog', (tester) async {
      // 308dp phone at 1.3x text scale: the three buttons must still show full
      // labels side by side instead of clipping to "Dele"/"Can"/"S".
      tester.view.physicalSize = const Size(308 * 3, 700 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<(String, List<CustomKeyStep>)>(
                    context: context,
                    builder: (_) => CustomKeyButtonEditorDialog(
                      initialLabel: 'My Button',
                      initialSteps: const [
                        CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
                      ],
                      onDelete: () {},
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(AlertDialog));
      for (final label in ['Delete', 'Cancel', 'Save']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(
          paragraph.size.width,
          closeTo(paragraph.getMaxIntrinsicWidth(double.infinity), 0.5),
          reason: '$label is clipped',
        );
        expect(tester.getRect(find.text(label)).right, lessThan(card.right));
      }
    });
  });
}
