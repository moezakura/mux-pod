import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'package:flutter_muxpod/widgets/dialogs/custom_key_button_editor_dialog.dart';

// P5: CustomKeyButtonEditorDialog の openDialog pump ヘルパー（main() なし）。
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
              final result = await showDialog<(String, List<CustomKeyStep>)>(
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
