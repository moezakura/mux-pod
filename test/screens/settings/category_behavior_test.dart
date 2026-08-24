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
    testWidgets('displays Key Overlay toggle', (tester) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

      // 見出し（Key Overlay）+ トグル（Key Overlay）の 2 つが存在する。
      // スクロール対象は一意な 'Modifier Keys'（ゲート内第 1 項目）を使う。
      await scrollUntilFound(tester, find.text('Modifier Keys'));
      expect(find.text('Key Overlay'), findsWidgets);
      expect(find.text('Modifier Keys'), findsOneWidget);
    });

    testWidgets('behavior toggles are interactive', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

      // Behavior は3グループ+フラット1に再編され、既定 ON のキーオーバーレイ
      // ゲート下の 'Modifier Keys' がトグル操作可能であることを確認する。
      await scrollUntilFound(tester, find.text('Modifier Keys'));
      final tile = find.ancestor(
        of: find.text('Modifier Keys'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tile).value, isTrue); // 既定 ON
      expect(tile, findsOneWidget);
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

    // R-T1: キーオーバーレイ ゲート回帰（Display → Behavior 移動後のブロック不壊をロック）
    // inventory: TEST-SETTINGS-V2-RT1
    testWidgets('Key Overlay gate hides child items when OFF (R-T1)', (
      tester,
    ) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'Behavior');

      // 既定 ON → ゲート下 5 項目が表示される
      await scrollUntilFound(tester, find.text('Overlay Position'));
      expect(find.text('Modifier Keys'), findsOneWidget);
      expect(find.text('Overlay Position'), findsOneWidget);

      // OFF にトグル（見出しと同名のため SwitchListTile で特定）
      final koSwitch = find.widgetWithText(SwitchListTile, 'Key Overlay');
      await tester.ensureVisible(koSwitch);
      await tester.pumpAndSettle();
      await tester.tap(koSwitch);
      await tester.pumpAndSettle();

      // 陽性アンカー（入力グループの Custom Buttons）までスクロールした上で
      // ゲート下 5 項目が非表示であることを確認（lazy ビルドの偽陰性回避）
      await scrollUntilFound(tester, find.text('Custom Buttons'));
      expect(find.text('Modifier Keys'), findsNothing);
      expect(find.text('Special Keys'), findsNothing);
      expect(find.text('Arrow Keys'), findsNothing);
      expect(find.text('Shortcut Keys'), findsNothing);
      expect(find.text('Overlay Position'), findsNothing);

      // 再び ON → 表示に戻る
      await scrollUntilFound(
        tester,
        find.widgetWithText(SwitchListTile, 'Key Overlay'),
      );
      await tester.tap(find.widgetWithText(SwitchListTile, 'Key Overlay'));
      await tester.pumpAndSettle();
      await scrollUntilFound(tester, find.text('Overlay Position'));
      expect(find.text('Overlay Position'), findsOneWidget);
    });

    // R-T4: Behavior グループ相対順回帰（build 順 ↔ descriptor の二重管理ロック）
    // inventory: TEST-SETTINGS-V2-RT4
    testWidgets('Behavior group headers are in relative order (R-T4)', (
      tester,
    ) async {
      // 全項目が収まる高さでスクロール不要にする
      await buildSettingsApp(tester, size: const Size(390, 2000));
      await openCategory(tester, 'Behavior');

      final dyKeyOverlay = tester.getTopLeft(find.text('Key Overlay').first).dy;
      final dyInput = tester.getTopLeft(find.text('Input')).dy;
      final dyScrollSend = tester.getTopLeft(find.text('Scroll Send')).dy;
      final dyInvert = tester
          .getTopLeft(find.text('Invert Pane Navigation'))
          .dy;

      expect(dyKeyOverlay, lessThan(dyInput));
      expect(dyInput, lessThan(dyScrollSend));
      // フラットのペイン反転が最後
      expect(dyScrollSend, lessThan(dyInvert));
      expect(find.text('Custom Buttons'), findsOneWidget);
      expect(find.text('Invert Pane Navigation'), findsOneWidget);
    });
  });
}
