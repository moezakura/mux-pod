import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/custom_keys_provider.dart';
import 'package:flutter_muxpod/screens/custom_keys/custom_keys_screen.dart';

// P5: CustomKeysScreen テストの pump ヘルパー（main() なし）。

Future<void> pumpScreen(
  WidgetTester tester,
  ProviderContainer container,
) async {
  // Tall viewport so every strip (including the bottom shelf) is laid out
  // and hittable without scrolling.
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CustomKeysScreen()),
    ),
  );
  // Flush the async SharedPreferences load.
  await tester.pump();
}

Future<void> addButton(
  WidgetTester tester,
  String label,
  String stepValue,
) async {
  await tester.tap(find.text('+ Add button'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('label-field')), label);
  await tester.enterText(find.byKey(const Key('step-value-0')), stepValue);
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

/// Long-press a chip to start the drag, move to [to]'s centre and release.
Future<void> dragChip(WidgetTester tester, Finder from, Finder to) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(tester.getCenter(to));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

String tokenOf(ProviderContainer container, String label) {
  final s = container.read(customKeysProvider);
  final b = s.buttons.firstWhere((b) => b.label == label);
  return 'ck:${b.id.substring(3)}';
}
