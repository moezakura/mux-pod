import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/widgets/dialogs/theme_dialog.dart';

void main() {
  group('ThemeDialog', () {
    testWidgets('displays all theme options', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThemeDialog(isDarkMode: true),
          ),
        ),
      );

      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
    });

    testWidgets('dark mode is selected when isDarkMode is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThemeDialog(isDarkMode: true),
          ),
        ),
      );

      final darkRadio = find.byWidgetPredicate(
        (widget) =>
            widget is RadioListTile<bool> && widget.value == true && widget.groupValue == true,
      );
      expect(darkRadio, findsOneWidget);
    });

    testWidgets('light mode is selected when isDarkMode is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThemeDialog(isDarkMode: false),
          ),
        ),
      );

      final lightRadio = find.byWidgetPredicate(
        (widget) =>
            widget is RadioListTile<bool> && widget.value == false && widget.groupValue == false,
      );
      expect(lightRadio, findsOneWidget);
    });

    testWidgets('selecting light returns false', (tester) async {
      bool? selectedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedTheme = await showDialog<bool>(
                    context: context,
                    builder: (context) => const ThemeDialog(isDarkMode: true),
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

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(selectedTheme, false);
    });

    testWidgets('cancel returns null', (tester) async {
      bool? selectedTheme = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedTheme = await showDialog<bool>(
                    context: context,
                    builder: (context) => const ThemeDialog(isDarkMode: true),
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

      expect(selectedTheme, isNull);
    });
  });
}
