import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  group('Settings breakpoints', () {
    testWidgets('599 logical width shows the compact category list', (
      tester,
    ) async {
      await buildSettingsApp(tester, size: const Size(599, 844));

      // 一覧ビューのみ: 各カテゴリが1つずつ・詳細項目は表示されない
      expect(find.text('Display'), findsOneWidget);
      expect(find.text('Behavior'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Adjust Mode'), findsNothing);
      // ルートルートのため戻るボタンなし
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('600 logical width switches to the two-pane layout', (
      tester,
    ) async {
      await buildSettingsApp(tester, size: const Size(600, 844));

      // 左ペインタイル + 右ペイン初期 Display ヘッダ
      expect(find.text('Display'), findsWidgets);
      // 右ペインに Display の詳細項目（一覧ビューには存在しない）
      expect(find.text('Adjust Mode'), findsOneWidget);
      // 2ペインでも root ルートのため戻るボタンなし
      expect(find.byType(BackButton), findsNothing);
    });
  });
}