import 'package:flutter/material.dart';
import 'package:flutter_muxpod/screens/settings/widgets/settings_section_header.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  group('Display category', () {
    testWidgets('displays Adjust Mode setting', (tester) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Display');

      await scrollUntilFound(tester, find.text('Adjust Mode'));
      expect(find.text('Adjust Mode'), findsOneWidget);
      expect(find.text('Auto Fit'), findsOneWidget);
    });

    testWidgets('displays Language setting and opens the picker', (
      tester,
    ) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Display');

      await scrollUntilFound(tester, find.text('Language'));
      expect(find.text('Language'), findsOneWidget);
      // 初期値は 'system' なので説明付き表記が表示される
      expect(find.text('System (follow device)'), findsOneWidget);

      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();

      // 3択ダイアログ
      expect(find.text('System'), findsOneWidget);
      expect(find.text('日本語'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('displays Keep Screen On toggle', (tester) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Display');

      await scrollUntilFound(tester, find.text('Keep Screen On'));
      expect(find.text('Keep Screen On'), findsOneWidget);
    });

    testWidgets('Keep Screen On toggle is interactive', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await buildSettingsApp(tester);
      await openCategory(tester, 'Display');

      await scrollUntilFound(tester, find.text('Keep Screen On'));
      final tile = find.ancestor(
        of: find.text('Keep Screen On'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tile).value, isTrue); // 既定 ON

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    });

    testWidgets('displays Screen Orientation setting and opens picker', (
      tester,
    ) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Display');

      await scrollUntilFound(tester, find.text('Screen Orientation'));
      expect(find.text('Screen Orientation'), findsOneWidget);

      await tester.tap(find.text('Screen Orientation'));
      await tester.pumpAndSettle();
      // 背景の現在値サブタイトルとダイアログ内の両方に現れ得るため findsWidgets
      expect(find.text('Portrait'), findsWidgets);
      expect(find.text('Landscape'), findsOneWidget);
      expect(find.text('Auto (follow device)'), findsWidgets);
      expect(find.byType(RadioListTile<String>), findsNWidgets(3));
    });

    testWidgets('displays Max Refresh Rate setting and opens picker', (
      tester,
    ) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Display');

      await scrollUntilFound(tester, find.text('Max Refresh Rate'));
      expect(find.text('Max Refresh Rate'), findsOneWidget);

      await tester.tap(find.text('Max Refresh Rate'));
      await tester.pumpAndSettle();
      // 背景の現在値サブタイトルとダイアログ内の両方に現れ得るため findsWidgets
      expect(find.text('Auto (highest)'), findsWidgets);
      expect(find.text('120 Hz'), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNWidgets(4));
    });

    // R-T2: Display「画面」グループの存在 + 相対順回帰
    // inventory: TEST-SETTINGS-V2-RT2
    testWidgets('Screen group exists after Appearance/Terminal (R-T2)', (
      tester,
    ) async {
      // 全項目が収まる高さでスクロール不要にする
      await buildSettingsApp(tester, size: const Size(390, 1600));
      await openCategory(tester, 'Display');

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Screen'), findsOneWidget);

      final dyAppearance = tester.getTopLeft(find.text('Appearance')).dy;
      final dyTerminal = tester.getTopLeft(find.text('Terminal')).dy;
      final dyScreen = tester.getTopLeft(find.text('Screen')).dy;
      expect(dyAppearance, lessThan(dyTerminal));
      expect(dyTerminal, lessThan(dyScreen));

      expect(find.text('Keep Screen On'), findsOneWidget);
      expect(find.text('Screen Orientation'), findsOneWidget);
      expect(find.text('Max Refresh Rate'), findsOneWidget);
    });

    // R-T3: 新グループ見出しが Semantics isHeader (SettingsSectionHeader) で描画される
    // inventory: TEST-SETTINGS-V2-RT3
    testWidgets('Screen group header is a semantics header (R-T3)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await buildSettingsApp(tester, size: const Size(390, 1600));
      await openCategory(tester, 'Display');

      final heading = find.descendant(
        of: find.byType(SettingsSectionHeader),
        matching: find.text('Screen'),
      );
      expect(tester.getSemantics(heading).flagsCollection.isHeader, isTrue);
      handle.dispose();
    });
  });
}
