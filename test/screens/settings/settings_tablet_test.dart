import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/settings/master_detail_view.dart';
import 'package:flutter_muxpod/screens/settings/settings_category.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  group('Settings tablet two-pane', () {
    Future<void> buildTablet(WidgetTester tester) =>
        buildSettingsApp(tester, size: const Size(1280, 800));

    testWidgets('shows master list and initial Display detail', (tester) async {
      await buildTablet(tester);

      // 左ペイン4カテゴリ + 右ペイン初期 Display（ヘッダ）
      expect(find.text('Display'), findsWidgets); // 左タイル + 右ヘッダ
      expect(find.text('Behavior'), findsOneWidget);
      expect(find.text('Connection & Transfer'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);

      // 右ペインが初期 Display の詳細
      expect(find.text('Adjust Mode'), findsOneWidget);
    });

    testWidgets('left tap switches the right pane without pushing', (
      tester,
    ) async {
      await buildTablet(tester);

      await tester.tap(find.text('Behavior'));
      await tester.pumpAndSettle();

      // 右ペインが Behavior へ切替（左タイル + 右ヘッダ）
      expect(find.text('Behavior'), findsWidgets);
      await scrollUntilFound(tester, find.text('Custom Buttons'));
      expect(find.text('Custom Buttons'), findsOneWidget);

      // push は発生しないため戻るボタンが出ない
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('keeps per-category scroll positions via IndexedStack', (
      tester,
    ) async {
      await buildTablet(tester);

      // 初期 Display を下へスクロール
      final position = tester
          .state<ScrollableState>(settingsScrollable)
          .position;
      await tester.drag(settingsScrollable, const Offset(0, -300));
      await tester.pump();
      final displayOffset = position.pixels;
      expect(displayOffset, greaterThan(0));

      // Behavior へ切替 → 右ペインが切替わる（IndexedStack の表示子が変わる）
      await tester.tap(find.text('Behavior'));
      await tester.pumpAndSettle();
      await scrollUntilFound(tester, find.text('Custom Buttons'));
      expect(find.text('Custom Buttons'), findsOneWidget);

      // Display へ戻る → スクロール位置が保持されている
      await tester.tap(find.text('Display'));
      await tester.pumpAndSettle();
      expect(find.text('Adjust Mode'), findsOneWidget);

      final restored = tester
          .state<ScrollableState>(settingsScrollable)
          .position;
      expect(restored.pixels, displayOffset);
    });

    testWidgets('keeps selected category across language/theme changes', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await buildTablet(tester);
      await tester.tap(find.text('Behavior'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsMasterDetailView)),
      );
      expect(
        container.read(settingsCategoryProvider),
        SettingsCategory.behavior,
      );

      // 言語切替（settingsProvider 更新 → sections が再ビルドされる）
      await container.read(settingsProvider.notifier).setLanguage('ja');
      await tester.pumpAndSettle();
      expect(
        container.read(settingsCategoryProvider),
        SettingsCategory.behavior,
      );

      // テーマ切替（同様に再ビルド）
      await container.read(settingsProvider.notifier).setDarkMode(true);
      await tester.pumpAndSettle();
      expect(
        container.read(settingsCategoryProvider),
        SettingsCategory.behavior,
      );
    });
  });
}
