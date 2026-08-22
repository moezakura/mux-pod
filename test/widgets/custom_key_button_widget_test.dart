import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'package:flutter_muxpod/widgets/custom_key_button_widget.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  CustomKeyButton makeButton() => CustomKeyButton(
    id: 'ck_1_a1b2',
    label: '/models',
    steps: const [
      CustomKeyStep(type: CustomKeyStepType.text, value: '/models'),
      CustomKeyStep(type: CustomKeyStepType.key, value: 'Enter'),
    ],
  );

  testWidgets('tap executes steps in order via callbacks', (tester) async {
    final sent = <String>[];
    final kinds = <String>[];
    await tester.pumpWidget(
      wrap(
        CustomKeyButtonWidget(
          button: makeButton(),
          onKeyPressed: (t) {
            sent.add(t);
            kinds.add('text');
          },
          onSpecialKeyPressed: (t) {
            sent.add(t);
            kinds.add('key');
          },
          onEdit: (_) {},
          hapticFeedback: false,
        ),
      ),
    );
    await tester.tap(find.text('/models'));
    await tester.pump();
    expect(kinds, ['text', 'key']);
    expect(sent, ['/models', 'Enter']);
  });

  testWidgets('pause delays the following step', (tester) async {
    final order = <String>[];
    await tester.pumpWidget(
      wrap(
        CustomKeyButtonWidget(
          button: CustomKeyButton(
            id: 'ck_2',
            label: 'P',
            steps: const [
              CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
              CustomKeyStep(type: CustomKeyStepType.pause, value: '300'),
              CustomKeyStep(type: CustomKeyStepType.text, value: 'b'),
            ],
          ),
          onKeyPressed: (t) => order.add(t),
          onSpecialKeyPressed: (_) {},
          onEdit: (_) {},
          hapticFeedback: false,
        ),
      ),
    );
    await tester.tap(find.text('P'));
    await tester.pump();
    expect(order, ['a']);
    await tester.pump(const Duration(milliseconds: 350));
    expect(order, ['a', 'b']);
  });

  testWidgets('pause value with trailing space still delays', (tester) async {
    final order = <String>[];
    await tester.pumpWidget(
      wrap(
        CustomKeyButtonWidget(
          button: CustomKeyButton(
            id: 'ck_5',
            label: 'T',
            steps: const [
              CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
              CustomKeyStep(type: CustomKeyStepType.pause, value: '300 '),
              CustomKeyStep(type: CustomKeyStepType.text, value: 'b'),
            ],
          ),
          onKeyPressed: (t) => order.add(t),
          onSpecialKeyPressed: (_) {},
          onEdit: (_) {},
          hapticFeedback: false,
        ),
      ),
    );
    await tester.tap(find.text('T'));
    await tester.pump();
    expect(order, ['a']);
    await tester.pump(const Duration(milliseconds: 350));
    expect(order, ['a', 'b']);
  });

  testWidgets('long-press fires onEdit with the button', (tester) async {
    CustomKeyButton? edited;
    final b = makeButton();
    await tester.pumpWidget(
      wrap(
        CustomKeyButtonWidget(
          button: b,
          onKeyPressed: (_) {},
          onSpecialKeyPressed: (_) {},
          onEdit: (btn) => edited = btn,
          hapticFeedback: false,
        ),
      ),
    );
    await tester.longPress(find.text('/models'));
    expect(edited?.id, b.id);
  });

  testWidgets('re-entry guard ignores taps while executing', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(
      wrap(
        CustomKeyButtonWidget(
          button: CustomKeyButton(
            id: 'ck_3',
            label: 'Slow',
            steps: const [
              CustomKeyStep(type: CustomKeyStepType.pause, value: '500'),
              CustomKeyStep(type: CustomKeyStepType.text, value: 'x'),
            ],
          ),
          onKeyPressed: (_) => tapCount++,
          onSpecialKeyPressed: (_) {},
          onEdit: (_) {},
          hapticFeedback: false,
        ),
      ),
    );
    await tester.tap(find.text('Slow'));
    await tester.pump();
    await tester.tap(find.text('Slow'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tapCount, 1);
  });

  testWidgets('invalid pause value is skipped, sequence continues', (
    tester,
  ) async {
    final order = <String>[];
    await tester.pumpWidget(
      wrap(
        CustomKeyButtonWidget(
          button: CustomKeyButton(
            id: 'ck_4',
            label: 'Q',
            steps: const [
              CustomKeyStep(type: CustomKeyStepType.text, value: 'a'),
              CustomKeyStep(type: CustomKeyStepType.pause, value: 'zzz'),
              CustomKeyStep(type: CustomKeyStepType.text, value: 'b'),
            ],
          ),
          onKeyPressed: (t) => order.add(t),
          onSpecialKeyPressed: (_) {},
          onEdit: (_) {},
          hapticFeedback: false,
        ),
      ),
    );
    await tester.tap(find.text('Q'));
    await tester.pump();
    expect(order, ['a', 'b']);
  });
}
