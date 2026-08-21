import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/providers/custom_keys_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

import '../../helpers/terminal_test_scaffold.dart';

void main() {
  // 単一カスタムボタン + row1 トークンのシード（長押し削除・ダイアログ入力用）。
  Map<String, Object> singleSeedPrefs() => {
    'custom_key_buttons_v1': jsonEncode([
      {
        'id': 'ck_0001_dead',
        'label': 'Del Me',
        'steps': [
          {'type': 'text', 'value': 'hi'},
        ],
      },
    ]),
    'custom_key_row1_v1': jsonEncode(['ck:0001_dead']),
  };

  // 標準 row1 + 多数のカスタムボタンで行を溢れさせ、末尾への自動スクロールを
  // 検証するシード。行がビューポート（1080px）を超えると、新規ボタンはスクロール
  // しない限り画面外になる。
  Map<String, Object> crowdedSeedPrefs() {
    final buttons = <Map<String, Object>>[];
    final row1 = <String>[
      'esc',
      'tab',
      'ctrl',
      'alt',
      'shift',
      'enter',
      'senter',
      'slash',
      'dash',
    ];
    for (var i = 1; i <= 20; i++) {
      final suffix = 'seed${i.toString().padLeft(2, '0')}_aaaa';
      buttons.add({
        'id': 'ck_$suffix',
        'label': 'Seed $i',
        'steps': [
          {'type': 'text', 'value': 's$i'},
        ],
      });
      row1.add('ck:$suffix');
    }
    return {
      'custom_key_buttons_v1': jsonEncode(buttons),
      'custom_key_row1_v1': jsonEncode(row1),
    };
  }

  // pumpTerminalScreen は SharedPreferences を空にリセットしてから pump するため、
  // 再シードして notifier を invalidate し、シードを再読み込みさせる。
  Future<ProviderContainer> seedAndReload(
    WidgetTester tester,
    Map<String, Object> prefs,
  ) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalScreen)),
    );
    container.invalidate(customKeysProvider);
    await tester.pumpAndSettle();
    return container;
  }

  group('TerminalScreen custom key buttons E2E', () {
    testWidgets('add → auto-place → visible on the top bar row', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      final container = await seedAndReload(tester, crowdedSeedPrefs());

      // 鉛筆（管理）ボタンで CustomKeysScreen を開く。
      await tester.tap(
        find.descendant(
          of: find.byType(SpecialKeysBar),
          matching: find.byIcon(Icons.edit_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Custom Buttons'), findsOneWidget);

      // エディタダイアログで新規ボタンを追加。
      await tester.tap(find.text('+ Add button'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('label-field')),
        'Fresh Button',
      );
      await tester.enterText(find.byKey(const Key('step-value-0')), 'hello');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // ボタン一覧と Layout Custom Row チップの両方に出現し、row0 先頭に配置される。
      final state = container.read(customKeysProvider);
      final added = state.buttons.firstWhere((b) => b.label == 'Fresh Button');
      final token = 'ck:${added.id.substring(3)}';
      expect(state.row0, contains(token));
      expect(state.row0.first, token);
      expect(find.widgetWithText(ListTile, 'Fresh Button'), findsOneWidget);
      // Contract: the added button lands as a draggable chip in the Layout —
      // Custom Row strip (Key('chip-$row-$token')), not the removed `+` ActionChip.
      expect(find.byKey(Key('chip-0-$token')), findsOneWidget);

      // ターミナルへ戻る。
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 新規ボタンがトップバー行に可視・ヒット可能（自動スクロールで先頭が出現）。
      final inBar = find.descendant(
        of: find.byType(SpecialKeysBar),
        matching: find.text('Fresh Button'),
      );
      expect(inBar, findsOneWidget);
      expect(inBar.hitTestable(), findsOneWidget);
    });

    testWidgets('direct input shows typed text and sends it exactly once', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: const AppSettings(
          keepScreenOn: false,
          directInputEnabled: true,
        ),
      );

      final inputField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Type here...',
      );
      expect(inputField, findsOneWidget);

      await tester.tap(inputField);
      await tester.pump();
      await tester.enterText(inputField, 'models');
      await tester.pump();

      // (a) 入力したテキストが欄に残って可視（クリアされない）。
      final editable = tester.widget<EditableText>(
        find.descendant(of: inputField, matching: find.byType(EditableText)),
      );
      expect(editable.controller.text, contains('models'));

      // (b) 'models' がターミナルへちょうど1回だけ送信される（リテラル送信）。
      final sent = client.sendKeysCommands
          .where((c) => c.contains('models'))
          .toList();
      expect(sent.length, 1);
      expect(sent.single, contains('-l -- models'));
    });

    testWidgets('long-press delete removes button and its row tokens', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      final container = await seedAndReload(tester, singleSeedPrefs());

      expect(find.text('Del Me'), findsOneWidget);

      await tester.longPress(find.text('Del Me'));
      await tester.pumpAndSettle();

      // エディタダイアログ: 削除 → 確認。
      expect(find.byKey(const Key('dialog-delete')), findsOneWidget);
      await tester.tap(find.byKey(const Key('dialog-delete')));
      await tester.pumpAndSettle();

      expect(find.text('Delete button?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(AlertDialog, 'Delete button?'),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();

      final state = container.read(customKeysProvider);
      expect(state.buttons, isEmpty);
      expect(state.row0.contains('ck:0001_dead'), isFalse);
      expect(state.row1.contains('ck:0001_dead'), isFalse);
      expect(state.row2.contains('ck:0001_dead'), isFalse);
    });

    testWidgets('editor dialog input text is visible (onSurface) and present', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      await seedAndReload(tester, singleSeedPrefs());

      // バーのカスタムボタン長押しでエディタダイアログを開く。
      await tester.longPress(find.text('Del Me'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('label-field')), 'Edited');
      await tester.enterText(find.byKey(const Key('step-value-0')), 'typed');
      await tester.pump();

      // テーマの onSurface（ライト/ダーク両対応）と比較し、可視テキスト色を検証。
      final onSurface = Theme.of(
        tester.element(find.byKey(const Key('label-field'))),
      ).colorScheme.onSurface;

      final labelEditable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('label-field')),
          matching: find.byType(EditableText),
        ),
      );
      expect(labelEditable.controller.text, 'Edited');
      expect(labelEditable.style.color, onSurface);

      final stepEditable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('step-value-0')),
          matching: find.byType(EditableText),
        ),
      );
      expect(stepEditable.controller.text, 'typed');
      expect(stepEditable.style.color, onSurface);
    });
    testWidgets(
      'custom button seeded into row1 is tappable and sends its steps once',
      (tester) async {
        // Defends Bar contract: custom ck: tokens render in any row (row1 here)
        // and execute their steps exactly once per tap through the terminal.
        final client = await TerminalTestScaffold.pumpTerminalScreen(tester);
        await seedAndReload(tester, {
          'custom_key_buttons_v1': jsonEncode([
            {
              'id': 'ck_0001_dead',
              'label': 'Del Me',
              'steps': [
                {'type': 'text', 'value': 'unique_step_42'},
              ],
            },
          ]),
          'custom_key_row0_v1': jsonEncode(<String>[]),
          'custom_key_row1_v1': jsonEncode(['ck:0001_dead']),
          'custom_key_row2_v1': jsonEncode(<String>[]),
        });

        expect(find.text('Del Me'), findsOneWidget);

        await tester.tap(find.text('Del Me'));
        await tester.pumpAndSettle();

        final sent = client.sendKeysCommands
            .where((c) => c.contains('unique_step_42'))
            .toList();
        expect(sent.length, 1);
        expect(sent.single, contains('-l -- unique_step_42'));
      },
    );
  });
}
