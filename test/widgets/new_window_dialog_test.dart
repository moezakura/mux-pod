import 'package:flutter/material.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/widgets/dialogs/new_window_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NewWindowDialog', () {
    Future<void> openDialog(
      WidgetTester tester, {
      required void Function(NewWindowRequest?) onResult,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  final result = await showDialog<NewWindowRequest>(
                    context: context,
                    builder: (_) => const NewWindowDialog(
                      existingWindowNames: ['logs', 'build'],
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

    testWidgets('renders name and command fields only', (tester) async {
      await openDialog(tester, onResult: (_) {});

      expect(find.text('Window Name'), findsOneWidget);
      expect(find.text('Command'), findsOneWidget);
      expect(find.text('Start Directory'), findsNothing);
    });

    testWidgets('blank form pops a request with both fields null', (
      tester,
    ) async {
      NewWindowRequest? result;
      var completed = false;
      await openDialog(
        tester,
        onResult: (r) {
          result = r;
          completed = true;
        },
      );

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.byType(NewWindowDialog), findsNothing);
      expect(completed, isTrue);
      expect(result, isNotNull);
      expect(result!.name, isNull);
      expect(result!.command, isNull);
    });

    testWidgets('carries both values and trims whitespace', (tester) async {
      NewWindowRequest? result;
      await openDialog(tester, onResult: (r) => result = r);

      await tester.enterText(find.byType(TextFormField).at(0), 'editor');
      await tester.enterText(find.byType(TextFormField).at(1), ' make test ');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.byType(NewWindowDialog), findsNothing);
      expect(result, isNotNull);
      expect(result!.name, 'editor');
      expect(result!.command, 'make test');
    });

    testWidgets('empty command becomes null', (tester) async {
      NewWindowRequest? result;
      await openDialog(tester, onResult: (r) => result = r);

      await tester.enterText(find.byType(TextFormField).at(0), 'build2');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.byType(NewWindowDialog), findsNothing);
      expect(result, isNotNull);
      expect(result!.name, 'build2');
      expect(result!.command, isNull);
    });

    testWidgets('invalid name shows error and keeps dialog open', (
      tester,
    ) async {
      NewWindowRequest? result;
      var completed = false;
      await openDialog(
        tester,
        onResult: (r) {
          result = r;
          completed = true;
        },
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'bad name');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(
        find.text('Only letters, numbers, - and _ allowed'),
        findsOneWidget,
      );
      expect(find.byType(NewWindowDialog), findsOneWidget);
      expect(completed, isFalse);
      expect(result, isNull);
    });

    testWidgets('duplicate name shows already exists error', (tester) async {
      var completed = false;
      await openDialog(tester, onResult: (_) => completed = true);

      await tester.enterText(find.byType(TextFormField).at(0), 'logs');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Window "logs" already exists'), findsOneWidget);
      expect(find.byType(NewWindowDialog), findsOneWidget);
      expect(completed, isFalse);
    });

    testWidgets('cancel pops null', (tester) async {
      NewWindowRequest? result;
      var completed = false;
      await openDialog(
        tester,
        onResult: (r) {
          result = r;
          completed = true;
        },
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'editor');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(NewWindowDialog), findsNothing);
      expect(completed, isTrue);
      expect(result, isNull);
    });
  });
}
