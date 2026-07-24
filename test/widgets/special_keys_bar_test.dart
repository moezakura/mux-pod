import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

void main() {
  Widget buildWidget({
    required bool directInputEnabled,
    VoidCallback? onImagePickRequested,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 320,
            child: SpecialKeysBar(
              onKeyPressed: (_) {},
              onSpecialKeyPressed: (_) {},
              onInputTap: () {},
              directInputEnabled: directInputEnabled,
              onDirectInputToggle: () {},
              onImagePickRequested: onImagePickRequested,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('direct input toolbar does not overflow at narrow phone width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      buildWidget(directInputEnabled: true, onImagePickRequested: () {}),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('PgUp'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('command input label stays compact in non-direct toolbar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildWidget(directInputEnabled: false));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Cmd'), findsOneWidget);
    expect(find.text('Input...'), findsNothing);
  });
}
