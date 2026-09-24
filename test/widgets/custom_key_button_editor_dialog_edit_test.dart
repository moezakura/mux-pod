import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/custom_key_button_dialog_open.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'package:flutter_muxpod/widgets/dialogs/custom_key_button_editor_dialog.dart';

void main() {
  group('CustomKeyButtonEditorDialog', () {
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
  });
}
