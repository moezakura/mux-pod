// P5: カスタムキー provider テスト（分割・責務: addRow/removeRow/maxRows 制限・truncation・新行への placeToken）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/providers/custom_keys_provider.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('addRow appends an empty bottom row and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);

    container.read(customKeysProvider.notifier).addRow();
    expect(container.read(customKeysProvider).rows.length, 4);
    expect(container.read(customKeysProvider).rows.last, isEmpty);

    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(
      (jsonDecode(prefs.getString(CustomKeysNotifier.rowsKey)!) as List).length,
      4,
    );
  });

  test('addRow is a no-op at maxRows', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);

    for (var i = 0; i < CustomKeyRows.maxRows + 2; i++) {
      notifier.addRow();
    }
    expect(
      container.read(customKeysProvider).rows.length,
      CustomKeyRows.maxRows,
    );
  });

  test('removeRow drops the row and its tokens become unused', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);
    final b = notifier.addButton('X', [
      CustomKeyStep(type: CustomKeyStepType.text, value: 'x'),
    ]);
    final ck = 'ck:${b.id.substring(3)}';
    notifier.setRowTokens(0, [ck, 'esc']);

    notifier.removeRow(0);

    final s = container.read(customKeysProvider);
    expect(s.rows.length, 2);
    expect(s.rows.first, CustomKeyRows.standardRow1);
    expect(s.buttons.single.id, b.id);
    expect(s.unusedTokens(), contains(ck));
  });

  test('removeRow can empty the layout entirely', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);

    notifier.removeRow(2);
    notifier.removeRow(1);
    notifier.removeRow(0);

    expect(container.read(customKeysProvider).rows, isEmpty);
    expect(
      container.read(customKeysProvider).unusedTokens(),
      CustomKeyRows.allLayoutTokens,
    );
  });

  test('placeToken lands in a freshly added row', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);

    notifier.addRow();
    notifier.placeToken('esc', toRow: 3, toIndex: 0);

    final s = container.read(customKeysProvider);
    expect(s.rows[3], ['esc']);
    expect(s.rows[1].contains('esc'), isFalse);
  });

  test('stored rows beyond maxRows are truncated on load', () async {
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.rowsKey: jsonEncode([
        for (var i = 0; i < CustomKeyRows.maxRows + 2; i++) <String>['esc'],
      ]),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(customKeysProvider).rows.length,
      CustomKeyRows.maxRows,
    );
  });
}
