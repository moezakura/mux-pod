import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/widgets/dialogs/font_family_dialog.dart';

void main() {
  group('FontFamilyDialog', () {
    testWidgets('displays all font family options', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FontFamilyDialog(currentFamily: 'JetBrains Mono'),
          ),
        ),
      );

      expect(find.text('Font Family'), findsOneWidget);
      expect(find.text('JetBrains Mono'), findsOneWidget);
      expect(find.text('Fira Code'), findsOneWidget);
      expect(find.text('Source Code Pro'), findsOneWidget);
      expect(find.text('Roboto Mono'), findsOneWidget);
    });

    testWidgets('current family is selected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FontFamilyDialog(currentFamily: 'Fira Code'),
          ),
        ),
      );

      // Find the selected radio button
      final radioFira = find.byWidgetPredicate(
        (widget) =>
            widget is RadioListTile<String> &&
            widget.value == 'Fira Code' &&
            widget.groupValue == 'Fira Code',
      );
      expect(radioFira, findsOneWidget);
    });

    testWidgets('selecting a family returns the value', (tester) async {
      String? selectedFamily;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedFamily = await showDialog<String>(
                    context: context,
                    builder: (context) =>
                        const FontFamilyDialog(currentFamily: 'JetBrains Mono'),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Source Code Pro'));
      await tester.pumpAndSettle();

      expect(selectedFamily, 'Source Code Pro');
    });

    testWidgets('cancel returns null', (tester) async {
      String? selectedFamily = 'JetBrains Mono';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedFamily = await showDialog<String>(
                    context: context,
                    builder: (context) =>
                        const FontFamilyDialog(currentFamily: 'JetBrains Mono'),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(selectedFamily, isNull);
    });
  });
}
