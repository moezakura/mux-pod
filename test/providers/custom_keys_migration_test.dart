// P5: カスタムキー provider テスト（分割・責務: row2 num 補完・legacy row keys→rows 統合・corrupt rows フォールバック）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/providers/custom_keys_provider.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('customized row2 without num tokens gains num1..num4 once', () async {
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.legacyRow2Key: jsonEncode(['left']),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(customKeysProvider).rows[2], [
      'left',
      ...CustomKeyRows.directInputExtras,
    ]);

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    container2.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container2.read(customKeysProvider).rows[2], [
      'left',
      ...CustomKeyRows.directInputExtras,
    ]);
  });

  test('default row2 is not touched by the num migration', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(customKeysProvider).rows[2],
      CustomKeyRows.standardRow2,
    );
  });

  test('persisted default row2 is not touched by the num migration', () async {
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.legacyRow2Key: jsonEncode(CustomKeyRows.standardRow2),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(customKeysProvider).rows[2],
      CustomKeyRows.standardRow2,
    );
    expect(
      container.read(customKeysProvider).unusedTokens(),
      CustomKeyRows.directInputExtras,
    );
  });

  test('legacy row keys migrate into the rows key and are removed', () async {
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.legacyRow0Key: jsonEncode(<String>[]),
      CustomKeysNotifier.legacyRow1Key: jsonEncode(['esc', 'tab']),
      CustomKeysNotifier.legacyRow2Key: jsonEncode(CustomKeyRows.standardRow2),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(customKeysProvider).rows, [
      <String>[],
      ['esc', 'tab'],
      CustomKeyRows.standardRow2,
    ]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(CustomKeysNotifier.rowsKey), isNotNull);
    expect(prefs.getString(CustomKeysNotifier.legacyRow0Key), isNull);
    expect(prefs.getString(CustomKeysNotifier.legacyRow1Key), isNull);
    expect(prefs.getString(CustomKeysNotifier.legacyRow2Key), isNull);
  });

  test('corrupt rows value falls back to the default layout', () async {
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.rowsKey: 'not json at all',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(customKeysProvider).rows, CustomKeyRows.defaultRows);
  });
}
