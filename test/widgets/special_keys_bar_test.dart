import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

void main() {
  // Narrow-phone harness (#63): assert the toolbar does not overflow at a real
  // phone width and that page-navigation keys are present.
  Widget buildWidget({
    required bool directInputEnabled,
    VoidCallback? onImagePickRequested,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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

  // Wide surface: assert the structural contract (a horizontal scroll view
  // wraps the direct-input arrow row) rather than pixel overflow. A narrow
  // width would trip an unrelated font-fallback overflow in the modifier row
  // under the test's default (non-monospace) font, which does not occur
  // on-device.
  Widget harness({required bool directInput, double width = 720}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
            child: SpecialKeysBar(
              onKeyPressed: (_) {},
              onSpecialKeyPressed: (_) {},
              onInputTap: () {},
              onImagePickRequested: () {},
              onDirectInputToggle: () {},
              directInputEnabled: directInput,
              hapticFeedback: false,
            ),
          ),
        ),
      ),
    );
  }

  Finder horizontalScroller() => find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
  );

  group('SpecialKeysBar', () {
    testWidgets(
      'direct input toolbar does not overflow at narrow phone width',
      (tester) async {
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
      },
    );

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

    // Regression: with direct input on, the arrow row gains fixed-width number
    // keys (1-4). The old fixed Row + Spacer overflowed on narrow phones; the
    // row is now wrapped in a horizontal scroll view so it never overflows.
    testWidgets('direct-input arrow row is horizontally scrollable', (
      tester,
    ) async {
      await tester.pumpWidget(harness(directInput: true));
      await tester.pump();

      expect(horizontalScroller(), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets(
      'default arrow row keeps the expanded Input button, no scroller',
      (tester) async {
        await tester.pumpWidget(harness(directInput: false));
        await tester.pump();

        expect(horizontalScroller(), findsNothing);
        expect(find.text('Cmd'), findsOneWidget);
      },
    );
  });
}
