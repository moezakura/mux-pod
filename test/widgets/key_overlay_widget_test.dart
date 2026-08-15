import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/widgets/key_overlay_widget.dart';
import 'package:flutter_muxpod/services/terminal/tmux_key_display.dart';

void main() {
  group('KeyOverlayState', () {
    late KeyOverlayState state;

    setUp(() {
      state = KeyOverlayState();
    });

    tearDown(() {
      state.dispose();
    });

    test('initial state is null and no pulse', () {
      expect(state.text, isNull);
      expect(state.pulse, isFalse);
    });

    test('show sets text', () {
      state.show('Ctrl+C');
      expect(state.text, 'Ctrl+C');
      expect(state.pulse, isFalse);
    });

    test('show same key sets pulse true', () {
      state.show('ESC');
      state.show('ESC');
      expect(state.text, 'ESC');
      expect(state.pulse, isTrue);
    });

    test('show different key sets pulse false', () {
      state.show('ESC');
      state.show('TAB');
      expect(state.text, 'TAB');
      expect(state.pulse, isFalse);
    });

    test('hide clears text and pulse', () {
      state.show('↑');
      state.hide();
      expect(state.text, isNull);
      expect(state.pulse, isFalse);
    });

    test('notifies listeners on show', () {
      int count = 0;
      state.addListener(() => count++);
      state.show('ESC');
      expect(count, 1);
    });

    test('notifies listeners on same value show (for pulse)', () {
      int count = 0;
      state.show('ESC');
      state.addListener(() => count++);
      state.show('ESC');
      expect(count, 1);
    });
  });

  group('KeyOverlayWidget', () {
    late KeyOverlayState overlayState;

    setUp(() {
      overlayState = KeyOverlayState();
    });

    tearDown(() {
      overlayState.dispose();
    });

    Widget buildWidget({
      KeyOverlayPosition position = KeyOverlayPosition.aboveKeyboard,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              KeyOverlayWidget(overlayState: overlayState, position: position),
            ],
          ),
        ),
      );
    }

    testWidgets('initially hidden when state text is null', (tester) async {
      await tester.pumpWidget(buildWidget());
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0.0);
    });

    testWidgets('shows text when state has value', (tester) async {
      await tester.pumpWidget(buildWidget());
      overlayState.show('Ctrl+C');
      await tester.pump();
      expect(find.text('Ctrl+C'), findsOneWidget);
    });

    testWidgets('hides text when state is hidden', (tester) async {
      await tester.pumpWidget(buildWidget());
      overlayState.show('ESC');
      await tester.pump();
      expect(find.text('ESC'), findsOneWidget);

      overlayState.hide();
      await tester.pump();
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0.0);
    });

    testWidgets('rapid updates show latest key only', (tester) async {
      await tester.pumpWidget(buildWidget());
      overlayState.show('↑');
      await tester.pump();
      overlayState.show('↓');
      await tester.pump();
      overlayState.show('←');
      await tester.pump();
      expect(find.text('←'), findsOneWidget);
    });

    testWidgets('position aboveKeyboard uses bottom alignment', (tester) async {
      await tester.pumpWidget(
        buildWidget(position: KeyOverlayPosition.aboveKeyboard),
      );
      overlayState.show('ESC');
      await tester.pump();
      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.bottom, 8);
      expect(positioned.top, isNull);
    });

    testWidgets('position belowHeader uses top alignment', (tester) async {
      await tester.pumpWidget(
        buildWidget(position: KeyOverlayPosition.belowHeader),
      );
      overlayState.show('ESC');
      await tester.pump();
      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.top, 8);
      expect(positioned.bottom, isNull);
    });
  });
}
