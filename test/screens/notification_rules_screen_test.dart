import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/notifications/notification_rules_screen.dart';

void main() {
  group('NotificationRulesScreen', () {
    testWidgets('displays empty state when no rules', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NotificationRulesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Notification Rules'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('FAB opens rule creation dialog', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NotificationRulesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('New Rule'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Pattern'), findsOneWidget);
    });

    testWidgets('rule form validates empty fields', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NotificationRulesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a name'), findsOneWidget);
      expect(find.text('Please enter a pattern'), findsOneWidget);
    });
  });
}
