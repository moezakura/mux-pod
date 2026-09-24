import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('T14: herdr resize 2段階フロー（選択モーダル→絶対値ダイアログ・Q-04）', () {
    testWidgets('ヘッダー Resize → 選択モーダルが開き、1 pane でも常に表示される（条件3）', (
      tester,
    ) async {
      await pumpHerdrAndOpenPaneSelector(tester);

      // ヘッダーの Resize → 選択モーダル表示。
      await tapHeaderResizeAndOpenChooser(tester);

      // 1 pane でも選択モーダルが開く（条件3・C-1解消・スキップしない）。
      expect(find.text('Resize Pane'), findsOneWidget);
      // 初期選択は現在表示中の pane（currentPaneId = w1:p1・cwd /tmp ラベル）。
      expect(find.text('Selected: /tmp (80x24)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('terminal-resize-pane-w1:p1')),
        findsOneWidget,
      );

      // `_scrollToCaret` の 100ms 遅延タイマーを消化してクリーンに終了。
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('選択モーダル → ダイアログ: 絶対値 Cols/Rows 入力・絶対値プリセット'
        '（旧 UI 要素は削除済み）', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tapHeaderResizeAndOpenChooser(tester);
      await tapChooserResize(tester);

      // 絶対値 UI（tmux と同構造）: 概算プレビュー・Cols/Rows 入力・プリセット。
      expect(find.text('Estimated'), findsOneWidget);
      expect(find.text('Cols'), findsOneWidget);
      expect(find.text('Rows'), findsOneWidget);
      expect(find.text('80x24 (Standard)'), findsOneWidget);
      expect(find.text('120x40 (Wide)'), findsOneWidget);
      // 旧 UI 要素は削除（ユーザー決定）: Current 表示・方向パッド・相対量チップ。
      expect(find.text('Current: 80 x 24'), findsNothing);
      expect(find.byTooltip('Right'), findsNothing);
      expect(find.text('+20%'), findsNothing);
      expect(find.text('Direction'), findsNothing);
      expect(find.text('Amount'), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('絶対値入力: Cols を +4 セル変更 → 相対換算 right コマンドを発行する', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tapHeaderResizeAndOpenChooser(tester);
      await tapChooserResize(tester);

      // Cols を +4 セル（100 → 104）に変更して確定。
      await tapResizeDialogAndConfirm(tester, colsPlus: 4);

      // 相対換算: delta = 4 / コンテナ幅(200) = 0.02 → 成長方向は right（右隣）。
      expect(
        hasResizeCommand(
          client.execCommands,
          direction: 'right',
          paneId: 'w1:p1',
          expectedAmount: 4 / 200,
        ),
        isTrue,
        reason: '絶対値 Cols 変更が相対量（4/コンテナ幅）に換算されて送信される',
      );
      // Rows は変更なし（delta 0）→ 送信は 1 回のみ。
      expect(
        client.execCommands.where((c) => c.startsWith('herdr pane resize')),
        hasLength(1),
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('縮小入力: Cols を -4 セル → 隣接 pane（w1:p2）への成長コマンド（方向反転）', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tapHeaderResizeAndOpenChooser(tester);
      await tapChooserResize(tester);

      // Cols を -4 セル（100 → 96）に変更して確定。
      await tapResizeDialogAndConfirm(tester, colsMinus: 4);

      // 縮小は隣接 pane を成長させる（ユーザー決定5）:
      // 対象 w1:p1 の縮小側（right）= w1:p2 を、w1:p2 から見て対象側（left）へ成長。
      expect(
        hasResizeCommand(
          client.execCommands,
          direction: 'left',
          paneId: 'w1:p2',
          expectedAmount: 4 / 200,
        ),
        isTrue,
        reason: '縮小は隣接 pane への成長として実現される（--pane が w1:p2 に変わる）',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('プリセット 80x24 → Cols 縮小を隣接成長で送信（Rows は縦隣接なしで送信なし）', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tapHeaderResizeAndOpenChooser(tester);
      await tapChooserResize(tester);

      // 絶対値プリセット 80x24 → Cols 100→80（-20）・Rows 70→24（-46）。
      await tapResizeDialogAndConfirm(tester, presetLabel: '80x24 (Standard)');

      // Cols: delta = -20/コンテナ幅(200) = -0.1 → 縮小 → 隣接 w1:p2 を left で成長。
      expect(
        hasResizeCommand(
          client.execCommands,
          direction: 'left',
          paneId: 'w1:p2',
          expectedAmount: 20 / 200,
        ),
        isTrue,
      );
      // Rows: 縮小だが縦方向に隣接が無い → 送信されない（コマンドは 1 回のみ）。
      expect(
        client.execCommands.where((c) => c.startsWith('herdr pane resize')),
        hasLength(1),
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('2 pane: 選択モーダルで w1:p2 を選択 → 警告表示・--pane w1:p2・成長方向 left', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tapHeaderResizeAndOpenChooser(tester);

      // 初期選択は現在表示中の pane（w1:p1・cwd /a ラベル・条件10）。
      expect(find.text('Selected: /a (100x70)'), findsOneWidget);

      // 選択モーダルで w1:p2 を選択 → 実行前再検証（条件11）で引当成功。
      await tester.tap(
        find.byKey(const ValueKey('terminal-resize-pane-w1:p2')),
      );
      await tester.pump();
      expect(find.text('Selected: /b (100x70)'), findsOneWidget);
      await tapChooserResize(tester);

      // pane 2 枚以上 → 警告表示（条件4・tmux と同レベル）。
      expect(find.text('Other pane sizes may also change.'), findsOneWidget);

      // Cols +4 → w1:p2 は左隣（w1:p1）のみ → 成長方向は left。
      await tapResizeDialogAndConfirm(tester, colsPlus: 4);

      expect(
        hasResizeCommand(
          client.execCommands,
          direction: 'left',
          paneId: 'w1:p2',
          expectedAmount: 4 / 200,
        ),
        isTrue,
        reason: '選択モーダルで選んだ pane（w1:p2）が --pane に反映・方向は左隣',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('タイル⋮ Resize も選択モーダル経由・初期選択は現在表示中 pane（条件10）', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // タイル w1:p2 の ⋮ → Resize Pane（タイル ⋮ 導線）。
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('mux-sel-pane-w1:p2')),
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      // PopupMenu の表示アニメーションを消化する。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Resize Pane'));
      // `_closeSelectorThen` の 200ms 遅延後に選択モーダルが開く。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));

      // タップしたタイル（w1:p2）ではなく現在表示中 pane（w1:p1）が初期選択
      // （ユーザー決定①・条件10）。
      expect(find.text('Selected: /a (100x70)'), findsOneWidget);
      expect(find.text('Selected: /b (100x70)'), findsNothing);

      // そのまま確定 → 現在表示中 pane が対象になる（Cols +4 → right 成長）。
      await tapChooserResize(tester);
      await tapResizeDialogAndConfirm(tester, colsPlus: 4);

      expect(
        hasResizeCommand(
          client.execCommands,
          direction: 'right',
          paneId: 'w1:p1',
          expectedAmount: 4 / 200,
        ),
        isTrue,
        reason: 'タイル ⋮ 導線も選択モーダル経由・初期選択=currentPaneId に統一',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('changed:false（分割境界外）は情報 SnackBar を表示する', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'hello\n',
          // resize が分割境界外で changed:false を返す。
          'herdr pane resize': kHerdrResizeUnchangedFixture,
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tapHeaderResizeAndOpenChooser(tester);
      await tapChooserResize(tester);
      await tapResizeDialogAndConfirm(tester, colsPlus: 4);

      expect(
        find.text('No change at the split boundary'),
        findsOneWidget,
        reason: 'changed:false は soft 失敗として情報通知されること',
      );

      // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets('単一 pane では隣接が無く resize コマンドを送信しない', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tapHeaderResizeAndOpenChooser(tester);
      await tapChooserResize(tester);

      // Cols を +4 セル変更しても、隣接 pane が無く方向解決に失敗 → 送信しない。
      await tapResizeDialogAndConfirm(tester, colsPlus: 4);

      expect(
        client.execCommands.where((c) => c.startsWith('herdr pane resize')),
        isEmpty,
        reason: '隣接 pane が無い場合は方向解決に失敗し送信しない',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('3 pane: プリセット 120x40 → Cols/Rows 両方変更 → Cols→Rows 順に 2 回送信', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrThreePaneLayoutSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tapHeaderResizeAndOpenChooser(tester);
      await tapChooserResize(tester);

      // プリセット 120x40 → Cols 100→120（+20）・Rows 35→40（+5）。
      // w1:p1 は右隣（p2）と下隣（p3）の両方を持つ。
      await tapResizeDialogAndConfirm(tester, presetLabel: '120x40 (Wide)');

      final resizeCmds = client.execCommands
          .where((c) => c.startsWith('herdr pane resize'))
          .toList();
      expect(resizeCmds, hasLength(2), reason: 'Cols と Rows の両方変更で 2 回送信');
      // Cols → Rows の順（ユーザー決定6）。
      expect(resizeCmds[0], contains('--direction right'));
      expect(resizeCmds[0], contains('--pane w1:p1'));
      expect(amountOf(resizeCmds[0])!, closeTo(20 / 200, 1e-9));
      expect(resizeCmds[1], contains('--direction down'));
      expect(resizeCmds[1], contains('--pane w1:p1'));
      expect(amountOf(resizeCmds[1])!, closeTo(5 / 70, 1e-9));

      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
