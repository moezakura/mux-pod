import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/widgets/dialogs/rename_window_dialog.dart';

void main() {
  group('RenameWindowDialog', () {
    Future<void> openDialog(
      WidgetTester tester, {
      required void Function(String?) onResult,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  final result = await showDialog<String>(
                    context: context,
                    builder: (_) => const RenameWindowDialog(
                      currentName: 'main',
                      otherWindowNames: ['logs', 'build'],
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

    testWidgets('is pre-filled with the current name', (tester) async {
      await openDialog(tester, onResult: (_) {});

      expect(find.text('main'), findsOneWidget);
    });

    testWidgets('empty name shows error and keeps dialog open', (tester) async {
      String? result;
      var completed = false;
      await openDialog(tester, onResult: (r) {
        result = r;
        completed = true;
      });

      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Window name cannot be empty'), findsOneWidget);
      expect(find.byType(RenameWindowDialog), findsOneWidget);
      expect(completed, isFalse);
      expect(result, isNull);
    });

    testWidgets('duplicate name shows already exists error', (tester) async {
      await openDialog(tester, onResult: (_) {});

      await tester.enterText(find.byType(TextFormField), 'logs');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Window "logs" already exists'), findsOneWidget);
    });

    testWidgets('valid name pops with the new name', (tester) async {
      String? result;
      await openDialog(tester, onResult: (r) => result = r);

      await tester.enterText(find.byType(TextFormField), 'new-name');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.byType(RenameWindowDialog), findsNothing);
      expect(result, 'new-name');
    });

    testWidgets('current name is allowed', (tester) async {
      String? result;
      await openDialog(tester, onResult: (r) => result = r);

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.byType(RenameWindowDialog), findsNothing);
      expect(result, 'main');
    });
  });
}
