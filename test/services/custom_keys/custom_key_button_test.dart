import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';

void main() {
  group('CustomKeyStep', () {
    test('round-trips all step types', () {
      for (final type in CustomKeyStepType.values) {
        final value = switch (type) {
          CustomKeyStepType.text => '/models',
          CustomKeyStepType.key => 'Enter',
          CustomKeyStepType.pause => '300',
        };
        final step = CustomKeyStep(type: type, value: value);
        expect(CustomKeyStep.fromJson(step.toJson()), isNotNull);
        expect(CustomKeyStep.fromJson(step.toJson())!.type, type);
        expect(CustomKeyStep.fromJson(step.toJson())!.value, value);
      }
    });

    test('rejects invalid values', () {
      expect(CustomKeyStep.isValid(CustomKeyStepType.text, ''), isFalse);
      expect(CustomKeyStep.isValid(CustomKeyStepType.text, '  '), isFalse);
      expect(CustomKeyStep.isValid(CustomKeyStepType.key, ''), isFalse);
      expect(CustomKeyStep.isValid(CustomKeyStepType.pause, 'abc'), isFalse);
      expect(CustomKeyStep.isValid(CustomKeyStepType.pause, '-5'), isFalse);
      expect(CustomKeyStep.isValid(CustomKeyStepType.pause, '0'), isFalse);
      expect(CustomKeyStep.isValid(CustomKeyStepType.pause, '300'), isTrue);
      expect(CustomKeyStep.fromJson({'type': 'nope', 'value': 'x'}), isNull);
    });
  });

  group('CustomKeyButton', () {
    test('round-trips', () {
      final b = CustomKeyButton(
        id: 'ck_1_a1b2',
        label: '/models',
        steps: [CustomKeyStep(type: CustomKeyStepType.text, value: '/models')],
      );
      final parsed = CustomKeyButton.fromJson(b.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.id, 'ck_1_a1b2');
      expect(parsed.label, '/models');
      expect(parsed.steps.single.value, '/models');
    });

    test('rejects missing id / empty label / empty steps', () {
      expect(CustomKeyButton.fromJson({'label': 'x', 'steps': []}), isNull);
      expect(
        CustomKeyButton.fromJson({'id': 'ck_1', 'label': '', 'steps': []}),
        isNull,
      );
    });

    test('newId has ck_ prefix and unique suffixes', () {
      expect(CustomKeyButton.newId(), startsWith('ck_'));
      expect(CustomKeyButton.newId(), isNot(CustomKeyButton.newId()));
    });
  });

  group('CustomKeyRows', () {
    test('token helpers', () {
      expect(CustomKeyRows.isStandardToken('esc'), isTrue);
      expect(CustomKeyRows.isStandardToken('num3'), isTrue);
      expect(CustomKeyRows.isCustomToken('ck:1'), isTrue);
      expect(CustomKeyRows.isCustomToken('esc'), isFalse);
      expect(CustomKeyRows.isKnownToken('enter', const {}), isTrue);
      expect(CustomKeyRows.isKnownToken('ck:1', const {'ck:1'}), isTrue);
      expect(CustomKeyRows.isKnownToken('ck:9', const {'ck:1'}), isFalse);
    });

    test(
      'tokenLabel maps every standard token and null for custom/unknown',
      () {
        expect(CustomKeyRows.tokenLabel('esc'), 'ESC');
        expect(CustomKeyRows.tokenLabel('tab'), 'TAB');
        expect(CustomKeyRows.tokenLabel('ctrl'), 'CTRL');
        expect(CustomKeyRows.tokenLabel('alt'), 'ALT');
        expect(CustomKeyRows.tokenLabel('shift'), 'SHIFT');
        expect(CustomKeyRows.tokenLabel('enter'), 'ENTER');
        expect(CustomKeyRows.tokenLabel('senter'), 'S-RET');
        expect(CustomKeyRows.tokenLabel('slash'), '/');
        expect(CustomKeyRows.tokenLabel('dash'), '-');
        expect(CustomKeyRows.tokenLabel('pgup'), 'PgUp');
        expect(CustomKeyRows.tokenLabel('pgdn'), 'PgDn');
        expect(CustomKeyRows.tokenLabel('left'), 'Left');
        expect(CustomKeyRows.tokenLabel('up'), 'Up');
        expect(CustomKeyRows.tokenLabel('down'), 'Down');
        expect(CustomKeyRows.tokenLabel('right'), 'Right');
        expect(CustomKeyRows.tokenLabel('image'), 'Image');
        expect(CustomKeyRows.tokenLabel('di_toggle'), 'Direct Input');
        expect(CustomKeyRows.tokenLabel('input'), 'Input');
        expect(CustomKeyRows.tokenLabel('num1'), '1');
        expect(CustomKeyRows.tokenLabel('num2'), '2');
        expect(CustomKeyRows.tokenLabel('num3'), '3');
        expect(CustomKeyRows.tokenLabel('num4'), '4');
        expect(CustomKeyRows.tokenLabel('ck:1'), isNull);
        expect(CustomKeyRows.tokenLabel('bogus'), isNull);
      },
    );

    test('allLayoutTokens composes the three rows in canonical order', () {
      expect(CustomKeyRows.allLayoutTokens, [
        ...CustomKeyRows.standardRow1,
        ...CustomKeyRows.standardRow2,
        ...CustomKeyRows.directInputExtras,
      ]);
    });

    test('shelfRow is the unused-bucket sentinel', () {
      expect(CustomKeyRows.shelfRow, -1);
    });
  });
}
