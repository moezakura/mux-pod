// P5: カスタムキー provider テスト（分割・責務: placeToken/unusedTokens/shelf 移動・backspace 自動挿入・recreation 生存）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/providers/custom_keys_provider.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unusedTokens contains only num tokens in canonical order by default',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(customKeysProvider);
      await Future<void>.delayed(Duration.zero);

      final s = container.read(customKeysProvider);
      expect(s.unusedTokens(), CustomKeyRows.directInputExtras);
      expect(
        s.unusedTokens(),
        CustomKeyRows.allLayoutTokens
            .where(CustomKeyRows.directInputExtras.contains)
            .toList(),
      );
    },
  );

  test(
    'unplaced custom button appears in unusedTokens after standard tokens',
    () async {
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

      expect(container.read(customKeysProvider).unusedTokens(), [
        ...CustomKeyRows.directInputExtras,
        ck,
      ]);
    },
  );

  test('placeToken moves a standard token to row0 head', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);

    notifier.placeToken('esc', toRow: 0, toIndex: 0);

    final s = container.read(customKeysProvider);
    expect(s.rows[0], ['esc']);
    expect(s.rows[1].contains('esc'), isFalse);
    expect(s.rows[1].first, 'tab');
  });

  test(
    'backspace is inserted next to dash in a layout saved without it',
    () async {
      // The real upgrade path: the app was already opened, so a layout without
      // 'bspace' is persisted. Without the migration the bar would keep no way
      // to erase, since the key only ships in the defaults.
      SharedPreferences.setMockInitialValues({
        CustomKeysNotifier.rowsKey: jsonEncode([
          <String>[],
          ['esc', 'tab', 'slash', 'dash'],
          ['left', 'right'],
        ]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(customKeysProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(customKeysProvider).rows[1], [
        'esc',
        'tab',
        'slash',
        'dash',
        'bspace',
      ]);
    },
  );

  test('a layout without dash is left untouched', () async {
    // Rearranged by hand: inserting into it would be presumptuous, and the key
    // is still reachable from the customizer shelf.
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.rowsKey: jsonEncode([
        <String>[],
        ['esc', 'tab'],
        ['left', 'right'],
      ]),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);

    final rows = container.read(customKeysProvider).rows;
    expect(rows.any((row) => row.contains('bspace')), isFalse);
  });

  test(
    'placeToken same-row move to higher index adjusts for removal',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(customKeysProvider);
      await Future<void>.delayed(Duration.zero);
      final notifier = container.read(customKeysProvider.notifier);

      // row1 default:
      // [esc, tab, ctrl, alt, shift, enter, senter, slash, dash, bspace]
      notifier.placeToken('esc', toRow: 1, toIndex: 2);

      expect(container.read(customKeysProvider).rows[1], [
        'tab',
        'esc',
        'ctrl',
        'alt',
        'shift',
        'enter',
        'senter',
        'slash',
        'dash',
        'bspace',
      ]);
    },
  );

  test(
    'placeToken to shelf removes token from rows into unusedTokens',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(customKeysProvider);
      await Future<void>.delayed(Duration.zero);
      final notifier = container.read(customKeysProvider.notifier);

      notifier.placeToken('esc', toRow: CustomKeyRows.shelfRow, toIndex: 0);

      final s = container.read(customKeysProvider);
      expect(s.rows[1].contains('esc'), isFalse);
      expect(s.unusedTokens(), contains('esc'));
    },
  );

  test('placeToken with unknown token is a no-op', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);
    final before = container.read(customKeysProvider);

    notifier.placeToken('bogus', toRow: 0, toIndex: 0);
    notifier.placeToken('ck:missing', toRow: 1, toIndex: 0);

    final s = container.read(customKeysProvider);
    expect(s.rows[0], before.rows[0]);
    expect(s.rows[1], before.rows[1]);
    expect(s.rows[2], before.rows[2]);
  });

  test('placeToken state survives provider recreation', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(customKeysProvider.notifier);
    notifier.placeToken('esc', toRow: 0, toIndex: 0);
    await Future<void>.delayed(Duration.zero);

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    container2.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);
    final s = container2.read(customKeysProvider);
    expect(s.rows[0], ['esc']);
    expect(s.rows[1].contains('esc'), isFalse);
  });
}
