import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildApp() {
  return const ProviderScope(
    child: MaterialApp(home: SettingsScreen()),
  );
}

/// Scrolls until [finder] is visible in the first Scrollable of the tree.
///
/// 探索前にスクロール位置を先頭へ戻すことで、直前の `scrollUntilVisible` が
/// 最後に呼ぶ `Scrollable.ensureVisible` による位置ずれ（探索対象が画面上方へ
/// 通り過ぎてレイジービルドから外れる）に依存しない検証にする。
Future<void> scrollUntilFound(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  if (position.pixels > 0) {
    position.jumpTo(0);
    await tester.pump();
  }
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

    // inventory: TEST-SETTINGS-UI-001
    testWidgets('displays Scroll Send Input setting', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Scroll Send Input'));
      expect(find.text('Scroll Send Input'), findsOneWidget);
      expect(find.text('Wheel (mouse scroll)'), findsOneWidget);
    });

    // inventory: TEST-SETTINGS-UI-002
    testWidgets('Scroll Send Input picker selects Key', (tester) async {
      // setter が _saveSetting で SharedPreferences へ書き込むため、このテストのみモックする
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Scroll Send Input'));
      await tester.tap(find.text('Scroll Send Input'));
      await tester.pumpAndSettle();

      // SimpleDialog 内の選択肢（RadioListTile は不使用・ListTile 方式）
      expect(find.text('Wheel'), findsOneWidget);
      expect(find.text('Key'), findsOneWidget);

      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      expect(find.text('Key (Page Up / Page Down)'), findsOneWidget);
    });

    // inventory: TEST-SETTINGS-UI-003
    testWidgets('hides fallback note by default (wheel verified)', (tester) async {
      // wheelSendVerifiedProvider はデフォルト true（Phase 0 実測 B1/B2 PASS 済み）
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Scroll Send Input'));
      expect(
        find.text('ホイール送信は未検証のため、現在はキー送信にフォールバックします。'),
        findsNothing,
      );
    });

    // inventory: TEST-SETTINGS-UI-004
    testWidgets('displays fallback note when wheel is unverified', (tester) async {
      // riverpod 3.x では Override 型は公開 export されないため、
      // テスト側で ProviderScope を直接構築して override する
      await tester.pumpWidget(
        ProviderScope(
          overrides: [wheelSendVerifiedProvider.overrideWith((ref) => false)],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Scroll Send Input'));
      expect(
        find.text('ホイール送信は未検証のため、現在はキー送信にフォールバックします。'),
        findsOneWidget,
      );
    });

    // inventory: TEST-SETTINGS-UI-005
    testWidgets('displays Invert Scroll Send Direction toggle', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Invert Scroll Send Direction'));
      expect(find.text('Invert Scroll Send Direction'), findsOneWidget);

      final tile = find.ancestor(
        of: find.text('Invert Scroll Send Direction'),
        matching: find.byType(SwitchListTile),
      );
      expect(tile, findsOneWidget);
    });

    // inventory: TEST-SETTINGS-UI-006
    testWidgets('invert toggle is interactive', (tester) async {
      // setter が _saveSetting で SharedPreferences へ書き込むため、このテストのみモックする
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await scrollUntilFound(tester, find.text('Invert Scroll Send Direction'));
      final tile = find.ancestor(
        of: find.text('Invert Scroll Send Direction'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    });
  });
}
