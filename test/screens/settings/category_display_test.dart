import 'package:flutter_test/flutter_test.dart';

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
  });
}
