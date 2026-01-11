import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/settings/settings_screen.dart';

void main() {
  group('SettingsScreen', () {
    testWidgets('displays settings sections', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Behavior'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);

      // Scroll down to see About section
      await tester.scrollUntilVisible(find.text('About'), 100);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('displays Haptic Feedback toggle', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Haptic Feedback'), findsOneWidget);
      expect(find.text('Vibrate on key press'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsWidgets);
    });

    testWidgets('displays Keep Screen On toggle', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Keep Screen On'), findsOneWidget);
      expect(find.text('Prevent screen from sleeping'), findsOneWidget);
    });

    testWidgets('behavior toggles are interactive', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the Haptic Feedback switch
      final hapticSwitch = find.ancestor(
        of: find.text('Haptic Feedback'),
        matching: find.byType(SwitchListTile),
      );
      expect(hapticSwitch, findsOneWidget);

      // Find the Keep Screen On switch
      final keepScreenSwitch = find.ancestor(
        of: find.text('Keep Screen On'),
        matching: find.byType(SwitchListTile),
      );
      expect(keepScreenSwitch, findsOneWidget);
    });

    testWidgets('displays Source Code link', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll down to see Source Code link in About section
      await tester.scrollUntilVisible(find.text('Source Code'), 100);
      expect(find.text('Source Code'), findsOneWidget);
      expect(find.text('github.com/muxpod'), findsOneWidget);
    });
  });
}
