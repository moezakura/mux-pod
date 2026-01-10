import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muxpod/app.dart';

void main() {
  group('MuxPodApp', () {
    testWidgets('should render without error', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MuxPodApp(),
        ),
      );

      // アプリがレンダリングされることを確認
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('should use Material theme', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MuxPodApp(),
        ),
      );

      // MaterialApp が使用されていることを確認
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.title, 'MuxPod');
    });
  });
}
