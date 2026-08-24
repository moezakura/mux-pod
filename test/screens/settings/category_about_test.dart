import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  group('About category', () {
    testWidgets('displays Source Code link', (tester) async {
      await buildSettingsApp(tester);
      await openCategory(tester, 'About');

      await scrollUntilFound(tester, find.text('Source Code'));
      expect(find.text('Source Code'), findsOneWidget);
      expect(find.text('github.com/moezakura/mux-pod'), findsOneWidget);
    });
  });
}