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

  // _persist() writes every row key on every load, so "key present" never means
  // "user customized it": a persisted default row2 must stay default, otherwise
  // the bar loses its legacy layout for everyone who never edited a row.
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

  // addRow appends an empty row at the bottom and persists it.
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

  // The bar has finite height: addRow stops at CustomKeyRows.maxRows.
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

  // removeRow must not destroy buttons: its tokens fall back to the shelf.
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

  // Deleting every row is allowed; the bar falls back to a pencil-only strip.
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

  // A token can be dropped into a row that did not exist a moment ago.
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

  // Hand-edited or future data must not grow the bar past the cap.
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

  // The three legacy row keys collapse into the new single key exactly once.
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

  // A corrupt layout must not brick the bar.
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
