import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/settings/settings_screen.dart';

Widget _buildApp() {
  return const ProviderScope(
    child: MaterialApp(home: SettingsScreen()),
  );
}

/// Scrolls until [finder] is visible in the first Scrollable of the tree.
Future<void> scrollUntilFound(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
}

void main() {
  group('SettingsScreen', () {
    testWidgets('displays Settings title', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('displays Adjust Mode setting', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Adjust Mode'), findsOneWidget);
      expect(find.text('Auto Fit'), findsOneWidget);
    });

    testWidgets('displays Haptic Feedback toggle', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Haptic Feedback is in the Behavior section - may need scroll
      await scrollUntilFound(tester, find.text('Haptic Feedback'));
      expect(find.text('Haptic Feedback'), findsOneWidget);
    });

    testWidgets('displays Keep Screen On toggle', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Keep Screen On'));
      expect(find.text('Keep Screen On'), findsOneWidget);
    });

    testWidgets('behavior toggles are interactive', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Haptic Feedback'));
      final hapticSwitch = find.ancestor(
        of: find.text('Haptic Feedback'),
        matching: find.byType(SwitchListTile),
      );
      expect(hapticSwitch, findsOneWidget);

      await scrollUntilFound(tester, find.text('Keep Screen On'));
      final keepScreenSwitch = find.ancestor(
        of: find.text('Keep Screen On'),
        matching: find.byType(SwitchListTile),
      );
      expect(keepScreenSwitch, findsOneWidget);
    });

    testWidgets('displays Source Code link', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Source Code'));
      expect(find.text('Source Code'), findsOneWidget);
      expect(find.text('github.com/moezakura/mux-pod'), findsOneWidget);
    });

    testWidgets('displays Image Transfer settings', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Image Transfer section header (rendered in uppercase by _SectionHeader)
      await scrollUntilFound(tester, find.text('IMAGE TRANSFER'));
      expect(find.text('IMAGE TRANSFER'), findsOneWidget);

      // Individual settings
      await scrollUntilFound(tester, find.text('Remote Path'));
      expect(find.text('Remote Path'), findsOneWidget);

      await scrollUntilFound(tester, find.text('Output Format'));
      expect(find.text('Output Format'), findsOneWidget);

      await scrollUntilFound(tester, find.text('Path Format'));
      expect(find.text('Path Format'), findsOneWidget);

      await scrollUntilFound(tester, find.text('Auto Enter'));
      expect(find.text('Auto Enter'), findsOneWidget);

      await scrollUntilFound(tester, find.text('Bracketed Paste'));
      expect(find.text('Bracketed Paste'), findsOneWidget);
    });
  });
}
