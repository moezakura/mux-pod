import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  group('Behavior category', () {
    testWidgets('displays Haptic Feedback toggle', (tester) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

      await scrollUntilFound(tester, find.text('Haptic Feedback'));
      expect(find.text('Haptic Feedback'), findsOneWidget);
    });

    testWidgets('displays Keep Screen On toggle', (tester) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

      await scrollUntilFound(tester, find.text('Keep Screen On'));
      expect(find.text('Keep Screen On'), findsOneWidget);
    });

    testWidgets('behavior toggles are interactive', (tester) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

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

    // inventory: TEST-SETTINGS-UI-001
    testWidgets('displays Scroll Send Input setting', (tester) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

      await scrollUntilFound(tester, find.text('Scroll Send Input'));
      expect(find.text('Scroll Send Input'), findsOneWidget);
      expect(find.text('Wheel (mouse scroll)'), findsOneWidget);
    });

    // inventory: TEST-SETTINGS-UI-002
    testWidgets('Scroll Send Input picker selects Key', (tester) async {
      // setter が _saveSetting で SharedPreferences へ書き込むためモックする
      SharedPreferences.setMockInitialValues({});
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

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
    testWidgets('hides fallback note by default (wheel verified)', (
      tester,
    ) async {
      // wheelSendVerifiedProvider はデフォルト true（Phase 0 実測 B1/B2 PASS 済み）
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

      await scrollUntilFound(tester, find.text('Scroll Send Input'));
      expect(
        find.text('Wheel send is unverified; falling back to key send.'),
        findsNothing,
      );
    });

    // inventory: TEST-SETTINGS-UI-004
    testWidgets('displays fallback note when wheel is unverified', (
      tester,
    ) async {
      // riverpod 3.x では Override 型は公開 export されないため、
      // テスト側で ProviderScope を直接構築して override する。
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [wheelSendVerifiedProvider.overrideWith((ref) => false)],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openCategory(tester, 'Behavior');

      await scrollUntilFound(
        tester,
        find.text('Wheel send is unverified; falling back to key send.'),
      );
      expect(
        find.text('Wheel send is unverified; falling back to key send.'),
        findsOneWidget,
      );
    });

    // inventory: TEST-SETTINGS-UI-005
    testWidgets('displays Invert Scroll Send Direction toggle', (tester) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

      await scrollUntilFound(tester, find.text('Invert Scroll Send Direction'));
      expect(find.text('Invert Scroll Send Direction'), findsOneWidget);

      final tile = find.ancestor(
        of: find.text('Invert Scroll Send Direction'),
        matching: find.byType(SwitchListTile),
      );
      expect(tile, findsOneWidget);
    });

    // inventory: TEST-SETTINGS-UI-007
    testWidgets('displays Fit terminal on Scroll Send toggle', (tester) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

      await scrollUntilFound(tester, find.text('Fit terminal on Scroll Send'));
      expect(find.text('Fit terminal on Scroll Send'), findsOneWidget);

      final tile = find.ancestor(
        of: find.text('Fit terminal on Scroll Send'),
        matching: find.byType(SwitchListTile),
      );
      expect(tile, findsOneWidget);
    });

    // inventory: TEST-SETTINGS-UI-008
    testWidgets('fit toggle is interactive', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

      await scrollUntilFound(tester, find.text('Fit terminal on Scroll Send'));
      final tile = find.ancestor(
        of: find.text('Fit terminal on Scroll Send'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      // タップ中心が画面内に収まるよう完全に画面内へスクロール
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    });

    // inventory: TEST-SETTINGS-UI-006
    testWidgets('invert toggle is interactive', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

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

    testWidgets('CJK Mode toggle is hidden on non-iOS platforms', (
      tester,
    ) async {
      await buildSettingsApp(tester, platform: TargetPlatform.android);
      await openCategory(tester, 'Behavior');

      // Behavior 末尾の項目までスクロールしても CJK Mode が現れないこと
      await scrollUntilFound(tester, find.text('Fit terminal on Scroll Send'));
      expect(find.text('CJK Mode'), findsNothing);
    });

    testWidgets('CJK Mode toggle is shown and interactive on iOS', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await buildSettingsApp(tester, platform: TargetPlatform.iOS);
      await openCategory(tester, 'Behavior');

      await scrollUntilFound(tester, find.text('CJK Mode'));
      final tile = find.ancestor(
        of: find.text('CJK Mode'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_cjk_mode'), isTrue);
    });

    testWidgets(
      'Keep Keyboard on Enter toggle is shown and interactive (Android)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await buildSettingsApp(tester);
        await openCategory(tester, 'Behavior');

        // 全プラットフォーム表示（ソフトキーボードはiOS/Android双方にある問題）
        await scrollUntilFound(
          tester,
          find.text('Keep Keyboard Open on Enter'),
        );
        final tile = find.ancestor(
          of: find.text('Keep Keyboard Open on Enter'),
          matching: find.byType(SwitchListTile),
        );
        expect(tile, findsOneWidget);
        // デフォルトは OFF
        expect(tester.widget<SwitchListTile>(tile).value, isFalse);

        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();

        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(tester.widget<SwitchListTile>(tile).value, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('settings_keep_keyboard_on_enter'), isTrue);
      },
    );

    testWidgets(
      'Keep Keyboard on Enter toggle is shown and interactive (iOS)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await buildSettingsApp(tester, platform: TargetPlatform.iOS);
        await openCategory(tester, 'Behavior');

        await scrollUntilFound(
          tester,
          find.text('Keep Keyboard Open on Enter'),
        );
        final tile = find.ancestor(
          of: find.text('Keep Keyboard Open on Enter'),
          matching: find.byType(SwitchListTile),
        );
        expect(tile, findsOneWidget);
        expect(tester.widget<SwitchListTile>(tile).value, isFalse);

        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();

        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(tester.widget<SwitchListTile>(tile).value, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('settings_keep_keyboard_on_enter'), isTrue);
      },
    );
  });
}
