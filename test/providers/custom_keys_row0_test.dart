// P5: カスタムキー provider テスト（分割・責務: row0 カスタム行の配置・persist・未知トークン破棄）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/providers/custom_keys_provider.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('row0 defaults to empty', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);
    expect(container.read(customKeysProvider).rows[0], isEmpty);
  });

  test('legacy layout migrates custom tokens into the custom row', () async {
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.buttonsKey: jsonEncode([
        {
          'id': 'ck_1_a',
          'label': 'A',
          'steps': [
            {'type': 'text', 'value': 'a'},
          ],
        },
        {
          'id': 'ck_2_b',
          'label': 'B',
          'steps': [
            {'type': 'text', 'value': 'b'},
          ],
        },
      ]),
      CustomKeysNotifier.legacyRow1Key: jsonEncode(['esc', 'ck:1_a', 'tab']),
      CustomKeysNotifier.legacyRow2Key: jsonEncode(['left', 'ck:2_b']),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);

    final state = container.read(customKeysProvider);
    expect(state.rows[0], ['ck:1_a', 'ck:2_b']);
    expect(state.rows[1], ['esc', 'tab']);
    expect(state.rows[2], ['left', ...CustomKeyRows.directInputExtras]);
  });

  test('an existing custom row is left alone on load', () async {
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.buttonsKey: jsonEncode([
        {
          'id': 'ck_1_a',
          'label': 'A',
          'steps': [
            {'type': 'text', 'value': 'a'},
          ],
        },
      ]),
      CustomKeysNotifier.legacyRow0Key: jsonEncode(<String>[]),
      CustomKeysNotifier.legacyRow1Key: jsonEncode(['esc', 'ck:1_a']),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);

    final state = container.read(customKeysProvider);
    expect(state.rows[0], isEmpty);
    expect(state.rows[1], ['esc', 'ck:1_a']);
  });

  test('setRowTokens row0 persists and survives recreation', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);
    final b = notifier.addButton('X', [
      CustomKeyStep(type: CustomKeyStepType.text, value: 'x'),
    ]);
    final ck = 'ck:${b.id.substring(3)}';

    notifier.setRowTokens(0, [ck]);
    expect(container.read(customKeysProvider).rows[0], [ck]);

    // Persistence is async; give _persist a chance to flush.
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(CustomKeysNotifier.rowsKey)!)[0], [ck]);

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    container2.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);
    final s = container2.read(customKeysProvider);
    expect(s.rows[0], [ck]);
    expect(s.rows[1], CustomKeyRows.standardRow1);
    expect(s.rows[2], CustomKeyRows.standardRow2);
  });

  test('button only in row0 is not reported unplaced', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);
    final b = notifier.addButton('X', [
      CustomKeyStep(type: CustomKeyStepType.text, value: 'x'),
    ]);
    notifier.setRowTokens(0, ['ck:${b.id.substring(3)}']);

    expect(container.read(customKeysProvider).unplacedButtons(), isEmpty);
  });

  test('deleteButton removes token from row0', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);
    final b = notifier.addButton('X', [
      CustomKeyStep(type: CustomKeyStepType.text, value: 'x'),
    ]);
    notifier.setRowTokens(0, ['ck:${b.id.substring(3)}']);

    notifier.deleteButton(b.id);
    expect(container.read(customKeysProvider).rows[0], isEmpty);
  });

  test('unknown tokens in stored row0 JSON are dropped', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);
    final b = notifier.addButton('X', [
      CustomKeyStep(type: CustomKeyStepType.text, value: 'x'),
    ]);
    final ck = 'ck:${b.id.substring(3)}';

    notifier.setRowTokens(0, ['bogus', ck, ck]);

    expect(container.read(customKeysProvider).rows[0], [ck]);

    // The sanitised row is what gets persisted inside the rows key.
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(CustomKeysNotifier.rowsKey)!)[0], [ck]);
  });
}
