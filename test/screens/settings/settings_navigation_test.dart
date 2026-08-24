import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  group('Settings navigation', () {
    testWidgets('displays Settings title', (tester) async {
      await buildSettingsApp(tester);

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('displays the four categories', (tester) async {
      await buildSettingsApp(tester);

      expect(find.text('Display'), findsOneWidget);
      expect(find.text('Behavior'), findsOneWidget);
      expect(find.text('Connection & Transfer'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('opens a category detail and returns to the list', (
      tester,
    ) async {
      await buildSettingsApp(tester);

      await openCategory(tester, 'Display');

      // 詳細 AppBar + body ヘッダの2箇所に表示される
      expect(find.text('Display'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // 一覧へ復帰
      expect(find.text('Display'), findsOneWidget);
      expect(find.text('Behavior'), findsOneWidget);
      expect(find.text('Connection & Transfer'), findsOneWidget);
    });

    // inventory: TEST-SETTINGS-SCROLL-POSITION-001（S-6）
    testWidgets('keeps the list scroll position after push and back', (
      tester,
    ) async {
      // 短いビューポートで一覧を強制スクロールさせる
      await buildSettingsApp(tester, size: const Size(390, 350));

      final listScrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(listScrollable).position;
      expect(position.pixels, 0);

      await tester.scrollUntilVisible(
        find.text('About'),
        100,
        scrollable: listScrollable,
      );
      await tester.pump();
      final scrolledPixels = position.pixels;
      expect(scrolledPixels, greaterThan(0));

      // 詳細へ push
      await openCategory(tester, 'About');
      expect(find.text('Version'), findsOneWidget);

      // 戻る → 一覧ルートが生存しているためスクロール位置が保持される
      await tester.pageBack();
      await tester.pumpAndSettle();

      final after = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(after.pixels, scrolledPixels);
    });

    testWidgets('displays ja category names', (tester) async {
      await buildSettingsApp(tester, locale: const Locale('ja'));

      expect(find.text('表示'), findsOneWidget);
      expect(find.text('操作'), findsOneWidget);
      expect(find.text('接続と転送'), findsOneWidget);
      expect(find.text('このアプリについて'), findsOneWidget);
    });
  });
}