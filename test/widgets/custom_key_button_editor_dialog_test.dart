import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'package:flutter_muxpod/widgets/dialogs/custom_key_button_editor_dialog.dart';

void main() {
  group('CustomKeyButtonEditorDialog', () {
    Future<void> openDialog(
      WidgetTester tester, {
      required String initialLabel,
      required List<CustomKeyStep> initialSteps,
      required void Function((String, List<CustomKeyStep>)? result) onResult,
      VoidCallback? onDelete,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  final result =
                      await showDialog<(String, List<CustomKeyStep>)>(
                        context: context,
                        builder: (_) => CustomKeyButtonEditorDialog(
                          initialLabel: initialLabel,
                          initialSteps: initialSteps,
                          onDelete: onDelete,
                        ),
                      );
                  onResult(result);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('empty label shows error and keeps dialog open', (
      tester,
    ) async {
      (String, List<CustomKeyStep>)? result;
      var completed = false;
      await openDialog(
        tester,
        initialLabel: '',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.text, value: 'hello'),
        ],
        onResult: (r) {
          result = r;
          completed = true;
        },
      );

      await tester.enterText(find.byKey(const Key('label-field')), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Label is required'), findsOneWidget);
      expect(find.byType(CustomKeyButtonEditorDialog), findsOneWidget);
      expect(completed, isFalse);
      expect(result, isNull);
    });

    testWidgets('zero steps shows error and keeps dialog open', (tester) async {
      (String, List<CustomKeyStep>)? result;
      var completed = false;
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [],
        onResult: (r) {
          result = r;
          completed = true;
        },
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('At least one step'), findsOneWidget);
      expect(find.byType(CustomKeyButtonEditorDialog), findsOneWidget);
      expect(completed, isFalse);
      expect(result, isNull);
    });

    testWidgets('invalid pause shows error and keeps dialog open', (
      tester,
    ) async {
      (String, List<CustomKeyStep>)? result;
      var completed = false;
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.pause, value: 'abc'),
        ],
        onResult: (r) {
          result = r;
          completed = true;
        },
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid pause value'), findsOneWidget);
      expect(find.byType(CustomKeyButtonEditorDialog), findsOneWidget);
      expect(completed, isFalse);
      expect(result, isNull);
    });

    testWidgets('empty text step value shows error and keeps dialog open', (
      tester,
    ) async {
      (String, List<CustomKeyStep>)? result;
      var completed = false;
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.text, value: 'hello'),
        ],
        onResult: (r) {
          result = r;
          completed = true;
        },
      );

      await tester.enterText(find.byKey(const Key('step-value-0')), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Step value is required'), findsOneWidget);
      expect(find.byType(CustomKeyButtonEditorDialog), findsOneWidget);
      expect(completed, isFalse);
      expect(result, isNull);
    });

    testWidgets('empty key step value shows error and keeps dialog open', (
      tester,
    ) async {
      (String, List<CustomKeyStep>)? result;
      var completed = false;
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.key, value: 'Enter'),
        ],
        onResult: (r) {
          result = r;
          completed = true;
        },
      );

      await tester.enterText(find.byKey(const Key('step-value-0')), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Step value is required'), findsOneWidget);
      expect(find.byType(CustomKeyButtonEditorDialog), findsOneWidget);
      expect(completed, isFalse);
      expect(result, isNull);
    });

    testWidgets('adds, reorders, and deletes steps then pops valid record', (
      tester,
    ) async {
      (String, List<CustomKeyStep>)? result;
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
          CustomKeyStep(type: CustomKeyStepType.text, value: 'b'),
        ],
        onResult: (r) => result = r,
      );

      // Pre-filled label.
      final labelField = tester.widget<TextField>(
        find.byKey(const Key('label-field')),
      );
      expect(labelField.controller!.text, 'My Button');

      // Add a pause step.
      await tester.tap(find.text('+ Add step'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('step-type-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('step-value-2')), '500');

      // Add a key step.
      await tester.tap(find.text('+ Add step'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('step-type-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Key').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('step-value-3')), 'C-c');

      // Reorder: move the pause step (index 2) up.
      await tester.tap(find.byKey(const Key('step-up-2')));
      await tester.pumpAndSettle();

      // Delete the 'b' step (now at index 2).
      await tester.tap(find.byKey(const Key('step-delete-2')));
      await tester.pumpAndSettle();

      // Save.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomKeyButtonEditorDialog), findsNothing);
      expect(result, isNotNull);
      expect(result!.$1, 'My Button');
      expect(result!.$2.length, 3);
      expect(result!.$2[0].type, CustomKeyStepType.text);
      expect(result!.$2[0].value, 'a');
      expect(result!.$2[1].type, CustomKeyStepType.pause);
      expect(result!.$2[1].value, '500');
      expect(result!.$2[2].type, CustomKeyStepType.key);
      expect(result!.$2[2].value, 'C-c');
    });

    testWidgets('cancel pops null', (tester) async {
      (String, List<CustomKeyStep>)? result;
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
        ],
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomKeyButtonEditorDialog), findsNothing);
      expect(result, isNull);
    });

    testWidgets('text fields render typed text with onSurface color', (
      tester,
    ) async {
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.text, value: 'hello'),
        ],
        onResult: (_) {},
      );

      final harnessContext = tester.element(find.text('Open'));
      final onSurface = Theme.of(harnessContext).colorScheme.onSurface;

      await tester.enterText(
        find.byKey(const Key('label-field')),
        'Visible text',
      );
      await tester.enterText(find.byKey(const Key('step-value-0')), 'typed');
      await tester.pump();

      EditableText editableText(Finder field) => tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );

      expect(
        editableText(find.byKey(const Key('label-field'))).style.color,
        onSurface,
      );
      expect(
        editableText(find.byKey(const Key('step-value-0'))).style.color,
        onSurface,
      );
    });

    testWidgets('delete button confirms and fires onDelete once', (
      tester,
    ) async {
      var deleteCount = 0;
      (String, List<CustomKeyStep>)? result;
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
        ],
        onDelete: () => deleteCount++,
        onResult: (r) => result = r,
      );

      expect(find.byKey(const Key('dialog-delete')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dialog-delete')));
      await tester.pumpAndSettle();

      expect(find.text('Delete button?'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog).last,
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CustomKeyButtonEditorDialog), findsNothing);
      expect(deleteCount, 1);
      expect(result, isNull);
    });

    testWidgets('cancel on delete confirm keeps dialog open', (tester) async {
      var deleteCount = 0;
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
        ],
        onDelete: () => deleteCount++,
        onResult: (_) {},
      );

      await tester.tap(find.byKey(const Key('dialog-delete')));
      await tester.pumpAndSettle();

      expect(find.text('Delete button?'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog).last,
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CustomKeyButtonEditorDialog), findsOneWidget);
      expect(find.text('Delete button?'), findsNothing);
      expect(deleteCount, 0);
    });

    testWidgets('no delete button without onDelete', (tester) async {
      await openDialog(
        tester,
        initialLabel: 'My Button',
        initialSteps: const [
          CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
        ],
        onResult: (_) {},
      );

      expect(find.byKey(const Key('dialog-delete')), findsNothing);
    });

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
