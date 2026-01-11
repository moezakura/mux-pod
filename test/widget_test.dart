// Basic Flutter widget test for MuxPod app.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/main.dart';

void main() {
  testWidgets('MyApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: MyApp()));

    // Pump a few frames to allow initial build
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify the app builds without errors
    expect(find.byType(MyApp), findsOneWidget);
  });
}
