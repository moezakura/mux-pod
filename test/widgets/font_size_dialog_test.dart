import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/widgets/dialogs/font_size_dialog.dart';

void main() {
  group('FontSizeDialog', () {
    testWidgets('displays all font size options', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FontSizeDialog(currentSize: 14.0),
          ),
        ),
      );

      expect(find.text('Font Size'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('16'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('current size is selected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FontSizeDialog(currentSize: 16.0),
          ),
        ),
      );

      // Find the selected radio button
      final radio16 = find.byWidgetPredicate(
        (widget) =>
            widget is RadioListTile<double> && widget.value == 16.0 && widget.groupValue == 16.0,
      );
      expect(radio16, findsOneWidget);
    });

    testWidgets('selecting a size returns the value', (tester) async {
      double? selectedSize;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedSize = await showDialog<double>(
                    context: context,
                    builder: (context) => const FontSizeDialog(currentSize: 14.0),
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

      await tester.tap(find.text('18'));
      await tester.pumpAndSettle();

      expect(selectedSize, 18.0);
    });

    testWidgets('cancel returns null', (tester) async {
      double? selectedSize = 14.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedSize = await showDialog<double>(
                    context: context,
                    builder: (context) => const FontSizeDialog(currentSize: 14.0),
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

      expect(selectedSize, isNull);
    });
  });
}
