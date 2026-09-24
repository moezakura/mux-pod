// P5: カスタムキー provider テスト（分割・責務: ボタン CRUD・永続化・ロード時検証）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/providers/custom_keys_provider.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults when keys absent', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // wait for the async load
    await Future<void>.delayed(Duration.zero);
    final s = container.read(customKeysProvider);
    expect(s.buttons, isEmpty);
    expect(s.rows[1], CustomKeyRows.standardRow1);
    expect(s.rows[2], CustomKeyRows.standardRow2);
  });

  test('add/update/delete persist', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);

    final b = notifier.addButton('/models', [
      CustomKeyStep(type: CustomKeyStepType.text, value: '/models'),
      CustomKeyStep(type: CustomKeyStepType.key, value: 'Enter'),
    ]);
    expect(b.steps.length, 2);
    expect(container.read(customKeysProvider).buttons.single.id, b.id);

    notifier.updateButton(
      b.id,
      label: '/models v2',
      steps: [CustomKeyStep(type: CustomKeyStepType.text, value: '/x')],
    );
    expect(
      container.read(customKeysProvider).buttons.single.label,
      '/models v2',
    );

    notifier.deleteButton(b.id);
    expect(container.read(customKeysProvider).buttons, isEmpty);
  });

  test('deleteButton removes row tokens', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);
    final b = notifier.addButton('X', [
      CustomKeyStep(type: CustomKeyStepType.text, value: 'x'),
    ]);
    notifier.setRowTokens(1, [
      ...CustomKeyRows.standardRow1,
      'ck:${b.id.substring(3)}',
    ]);

    notifier.deleteButton(b.id);
    final s = container.read(customKeysProvider);
    expect(s.rows[1], CustomKeyRows.standardRow1);
  });

  test('setRowTokens drops unknown and duplicate tokens', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);
    final b = notifier.addButton('X', [
      CustomKeyStep(type: CustomKeyStepType.text, value: 'x'),
    ]);
    final ck = 'ck:${b.id.substring(3)}';
    notifier.setRowTokens(2, ['bogus', 'pgup', ck, ck, 'left']);
    expect(container.read(customKeysProvider).rows[2], ['pgup', ck, 'left']);
  });

  test('corrupt stored JSON falls back to defaults', () async {
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.buttonsKey: 'not json',
      CustomKeysNotifier.legacyRow1Key: 'also not json',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final s = container.read(customKeysProvider);
    expect(s.buttons, isEmpty);
    expect(s.rows[1], CustomKeyRows.standardRow1);
  });

  test('load skips invalid button entries and keeps valid ones', () async {
    final valid = {
      'id': 'ck_1',
      'label': 'Good',
      'steps': [
        {'type': 'text', 'value': 'a'},
      ],
    };
    final invalid = {
      'id': 'ck_2',
      'label': 'Bad',
      'steps': [
        {'type': 'text', 'value': '   '},
      ],
    };
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.buttonsKey: jsonEncode([valid, invalid]),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);
    final s = container.read(customKeysProvider);
    expect(s.buttons.length, 1);
    expect(s.buttons.single.id, 'ck_1');
  });
}
