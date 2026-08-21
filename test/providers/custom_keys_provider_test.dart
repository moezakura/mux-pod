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
    expect(s.row1, CustomKeyRows.standardRow1);
    expect(s.row2, CustomKeyRows.standardRow2);
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
    expect(s.row1, CustomKeyRows.standardRow1);
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
    expect(container.read(customKeysProvider).row2, ['pgup', ck, 'left']);
  });

  test('corrupt stored JSON falls back to defaults', () async {
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.buttonsKey: 'not json',
      CustomKeysNotifier.row1Key: 'also not json',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final s = container.read(customKeysProvider);
    expect(s.buttons, isEmpty);
    expect(s.row1, CustomKeyRows.standardRow1);
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

  test('row0 defaults to empty', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);
    expect(container.read(customKeysProvider).row0, isEmpty);
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
      CustomKeysNotifier.row1Key: jsonEncode(['esc', 'ck:1_a', 'tab']),
      CustomKeysNotifier.row2Key: jsonEncode(['left', 'ck:2_b']),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);

    final state = container.read(customKeysProvider);
    expect(state.row0, ['ck:1_a', 'ck:2_b']);
    expect(state.row1, ['esc', 'tab']);
    expect(state.row2, ['left', ...CustomKeyRows.directInputExtras]);
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
      CustomKeysNotifier.row0Key: jsonEncode(<String>[]),
      CustomKeysNotifier.row1Key: jsonEncode(['esc', 'ck:1_a']),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);

    final state = container.read(customKeysProvider);
    expect(state.row0, isEmpty);
    expect(state.row1, ['esc', 'ck:1_a']);
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
    expect(container.read(customKeysProvider).row0, [ck]);

    // Persistence is async; give _persist a chance to flush.
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(CustomKeysNotifier.row0Key)!), [ck]);

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    container2.read(customKeysProvider); // trigger build + async _load
    await Future<void>.delayed(Duration.zero);
    final s = container2.read(customKeysProvider);
    expect(s.row0, [ck]);
    expect(s.row1, CustomKeyRows.standardRow1);
    expect(s.row2, CustomKeyRows.standardRow2);
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
    expect(container.read(customKeysProvider).row0, isEmpty);
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

    expect(container.read(customKeysProvider).row0, [ck]);

    // The sanitised row is what gets persisted under row0Key.
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(CustomKeysNotifier.row0Key)!), [ck]);
  });

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
    expect(s.row0, ['esc']);
    expect(s.row1.contains('esc'), isFalse);
    expect(s.row1.first, 'tab');
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

      // row1 default: [esc, tab, ctrl, alt, shift, enter, senter, slash, dash]
      notifier.placeToken('esc', toRow: 1, toIndex: 2);

      expect(container.read(customKeysProvider).row1, [
        'tab',
        'esc',
        'ctrl',
        'alt',
        'shift',
        'enter',
        'senter',
        'slash',
        'dash',
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
      expect(s.row1.contains('esc'), isFalse);
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
    expect(s.row0, before.row0);
    expect(s.row1, before.row1);
    expect(s.row2, before.row2);
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
    expect(s.row0, ['esc']);
    expect(s.row1.contains('esc'), isFalse);
  });

  test('customized row2 without num tokens gains num1..num4 once', () async {
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.row2Key: jsonEncode(['left']),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(customKeysProvider).row2, [
      'left',
      ...CustomKeyRows.directInputExtras,
    ]);

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    container2.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container2.read(customKeysProvider).row2, [
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

    expect(container.read(customKeysProvider).row2, CustomKeyRows.standardRow2);
  });

  // _persist() writes every row key on every load, so "key present" never means
  // "user customized it": a persisted default row2 must stay default, otherwise
  // the bar loses its legacy layout for everyone who never edited a row.
  test('persisted default row2 is not touched by the num migration', () async {
    SharedPreferences.setMockInitialValues({
      CustomKeysNotifier.row2Key: jsonEncode(CustomKeyRows.standardRow2),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(customKeysProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(customKeysProvider).row2, CustomKeyRows.standardRow2);
    expect(
      container.read(customKeysProvider).unusedTokens(),
      CustomKeyRows.directInputExtras,
    );
  });
}
