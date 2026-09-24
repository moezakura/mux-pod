import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('Q-05: herdr tab セレクタの tab CRUD 配線', () {
    testWidgets('ヘッダーの New Tab ボタンでラベル入力ダイアログが開き、空欄 Create で '
        'tab create --focus を発行し、新タブの表示へ自動切替わる', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {'herdr pane read': 'hello\n'},
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotWithLayoutFixture, // 接続時: w1:t1（単一 pane）
            kHerdrNewTabActiveSnapshotFixture, // create --focus 後: 新タブ focused
          ],
        },
        settle: false,
      );

      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Window'), findsOneWidget);

      expect(find.byTooltip('New Tab'), findsOneWidget);
      await tester.tap(find.byTooltip('New Tab'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));

      // ラベル入力ダイアログ（空欄許容・確認ボタン 'Create'）。
      expect(find.text('New Tab'), findsOneWidget);
      await tester.tap(find.text('Create'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // 空欄確定 = デフォルト名（--label なし）+ --focus（従来の即時作成 +
      // フォーカス移動・L-3）。
      expect(
        client.execCommands.any(
          (c) => c == 'herdr tab create --workspace w1 --focus',
        ),
        isTrue,
        reason: 'New Tab は空欄確定で --label なし + --focus の tab create を発行すること',
      );
      // アプリ契約（作成後自動切替）: 旧 pane（w1:p1）が残存しても新タブの
      // focused pane（w1:p2）が表示される。
      expect(
        find.text('Pane 2'),
        findsOneWidget,
        reason: 'New Tab 作成後は新タブへ表示が自動切替わること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('New Tab で空白のみのラベルはデフォルト作成（--label なし + --focus）', (
      tester,
    ) async {
      final client = await pumpHerdrAndOpenTabSelector(tester);

      await tester.tap(find.byTooltip('New Tab'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Create'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        client.execCommands.any(
          (c) => c == 'herdr tab create --workspace w1 --focus',
        ),
        isTrue,
        reason: '空白のみラベルは trim 正規化で null になり --label なしで作成される',
      );
      expect(
        client.execCommands
            .where((c) => c.startsWith('herdr tab create'))
            .any((c) => c.contains('--label')),
        isFalse,
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('New Tab でラベルを入力すると --label \'<label>\' --focus で作成される', (
      tester,
    ) async {
      final client = await pumpHerdrAndOpenTabSelector(tester);

      await tester.tap(find.byTooltip('New Tab'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('New Tab'), findsOneWidget);

      // 実ラベル入力（trim 後も非 null になる経路）。
      await tester.enterText(find.byType(TextField), 'logs');
      await tester.tap(find.text('Create'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        client.execCommands.any(
          (c) => c == "herdr tab create --workspace w1 --label 'logs' --focus",
        ),
        isTrue,
        reason:
            'ラベル入力ありは trim 後も非 null のため --label \'<label>\' + --focus を発行すること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('New Tab ダイアログのキャンセルはコマンドを発行しない', (tester) async {
      final client = await pumpHerdrAndOpenTabSelector(tester);

      await tester.tap(find.byTooltip('New Tab'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('New Tab'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        client.execCommands.where((c) => c.startsWith('herdr tab create')),
        isEmpty,
        reason: 'キャンセルは mounted ガードでコマンド未発行になること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('タイル ⋮ → Rename Window で tab rename コマンドを発行する', (tester) async {
      final client = await pumpHerdrAndOpenTabSelector(tester);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Rename Window'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // 入力ダイアログ（初期値 = 現在ラベル '1'）→ 変更して確定。
      expect(find.text('Rename Tab'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'work');
      await tester.tap(find.text('Rename'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        client.execCommands.any((c) => c == "herdr tab rename w1:t1 'work'"),
        isTrue,
        reason: 'Rename Tab UI は PaneWriter.renameTab（herdr tab rename）を発行すること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('タイル ⋮ → Close Window で連鎖 close 確認後に tab close を発行する', (
      tester,
    ) async {
      final client = await pumpHerdrAndOpenTabSelector(tester);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Close Window'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // 最後の tab（単一 tab fixture）→ workspace 連鎖終了の確認文言。
      expect(find.text('Close Tab?'), findsOneWidget);
      expect(
        find.textContaining('last tab in this workspace'),
        findsOneWidget,
        reason: '最後の tab を閉じる場合は workspace 連鎖 close を確認する（R2）',
      );

      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        client.execCommands.any((c) => c == 'herdr tab close w1:t1'),
        isTrue,
        reason: 'Close Tab UI は PaneWriter.closeTab（herdr tab close）を発行すること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
