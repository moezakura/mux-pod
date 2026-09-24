import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/custom_key_button_dialog_open.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'package:flutter_muxpod/widgets/dialogs/custom_key_button_editor_dialog.dart';

void main() {
  group('CustomKeyButtonEditorDialog', () {
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
  });
}
