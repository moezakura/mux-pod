import 'package:flutter/material.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_pane.dart';
import 'package:flutter_muxpod/services/terminal/font_calculator.dart';
import 'package:flutter_muxpod/widgets/dialogs/resize_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

// C4: HerdrResizePaneDialog（tmux と同構造の絶対値 UI）のウィジェットテスト。
//
// 新レイアウト（ユーザー決定・正本）:
//   Preview（概算ラベル）→ 警告（pane2枚以上のみ）→ Cols/Rows 数値入力 →
//   絶対値プリセット（80x24 (Standard) 等）→ Cancel / Resize
// 戻り値: ResizeResult(cols, rows)

// showDialog の戻り値をテストから参照できるようにするハーネス。
class _DialogHarness {
  ResizeResult? result;
}

void main() {
  // 横並び 2 pane fixture（0 起点・コンテナ 160x24）。
  const p1 = MultiplexerPane(
    index: 1,
    id: 'w1:p1',
    active: true,
    left: 0,
    top: 0,
    width: 80,
    height: 24,
  );
  const p2 = MultiplexerPane(
    index: 2,
    id: 'w1:p2',
    left: 80,
    top: 0,
    width: 80,
    height: 24,
  );

  // showDialog の戻り値をテストから参照できるようにするハーネス。
  Future<_DialogHarness> openDialog(
    WidgetTester tester, {
    List<MultiplexerPane> panes = const [],
    int currentCols = 80,
    int currentRows = 24,
    double screenWidth = 0,
    double screenHeight = 0,
    double fontSize = 14,
    String fontFamily = 'monospace',
  }) async {
    // ダイアログ下部（プリセットチップ等）がデフォルトの 800x600 サーフェス
    // からはみ出してタップが空振りしないよう、縦を広く確保する。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = _DialogHarness();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                harness.result = await showDialog<ResizeResult>(
                  context: context,
                  builder: (_) => HerdrResizePaneDialog(
                    targetPaneId: 'w1:p1',
                    panes: panes,
                    currentCols: currentCols,
                    currentRows: currentRows,
                    screenWidth: screenWidth,
                    screenHeight: screenHeight,
                    fontSize: fontSize,
                    fontFamily: fontFamily,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return harness;
  }

  Future<void> tapResize(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Resize'));
    await tester.pumpAndSettle();
  }

  group('HerdrResizePaneDialog', () {
    testWidgets('警告: pane 1 枚では表示されない（条件4）', (tester) async {
      await openDialog(tester, panes: [p1]);

      expect(find.text('Other pane sizes may also change.'), findsNothing);
    });

    testWidgets('警告: pane 2 枚以上で表示される（条件4）', (tester) async {
      await openDialog(tester, panes: [p1, p2]);

      expect(find.text('Other pane sizes may also change.'), findsOneWidget);
    });

    testWidgets('レイアウト: プレビュー（概算）・Cols/Rows 入力・絶対値プリセット', (tester) async {
      await openDialog(tester, panes: [p1, p2]);

      // プレビュー（概算ラベル・0 起点正規化）。
      expect(find.text('概算(estimated)'), findsOneWidget);
      expect(find.text('1\n80x24'), findsOneWidget);
      expect(find.text('2\n80x24'), findsOneWidget);
      // Cols/Rows 数値入力。
      expect(find.text('Cols'), findsOneWidget);
      expect(find.text('Rows'), findsOneWidget);
      // 絶対値プリセット（tmux と共通）。
      expect(find.text('80x24 (Standard)'), findsOneWidget);
      expect(find.text('120x40 (Wide)'), findsOneWidget);
      expect(find.text('160x50 (Full HD)'), findsOneWidget);
      // 旧 UI 要素は削除済み（ユーザー決定）: Current 表示・方向パッド・相対量チップ。
      expect(find.text('Current: 80 x 24'), findsNothing);
      expect(find.byTooltip('Right'), findsNothing);
      expect(find.text('+20%'), findsNothing);
      expect(find.text('Direction'), findsNothing);
    });

    testWidgets('Cols/Rows の◀▶ ステッパーで値が変わる', (tester) async {
      await openDialog(
        tester,
        panes: [p1, p2],
        currentCols: 100,
        currentRows: 70,
      );

      // 初期値（currentCols / currentRows）。
      expect(find.text('100'), findsOneWidget);
      expect(find.text('70'), findsOneWidget);

      // Cols ▶ 1 回 → 101（.first = Cols の ▶）。
      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pump();
      expect(find.text('101'), findsOneWidget);

      // Rows ◀ 1 回 → 69（.last = Rows の ◀）。
      await tester.tap(find.byIcon(Icons.chevron_left).last);
      await tester.pump();
      expect(find.text('69'), findsOneWidget);
    });

    testWidgets('プリセット選択で Cols/Rows が更新され Resize に反映される', (tester) async {
      final harness = await openDialog(
        tester,
        panes: [p1, p2],
        currentCols: 100,
        currentRows: 70,
      );

      await tester.tap(find.text('80x24 (Standard)'));
      await tester.pump();
      expect(find.text('80'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);

      await tapResize(tester);

      expect(harness.result, isNotNull);
      expect(harness.result!.cols, 80);
      expect(harness.result!.rows, 24);
      expect(find.text('Resize Pane'), findsNothing);
    });

    testWidgets('Resize で ResizeResult(cols, rows) が返る（初期値のまま）', (
      tester,
    ) async {
      final harness = await openDialog(
        tester,
        panes: [p1, p2],
        currentCols: 100,
        currentRows: 70,
      );

      await tapResize(tester);

      expect(harness.result, isNotNull);
      expect(harness.result!.cols, 100);
      expect(harness.result!.rows, 70);
    });

    testWidgets('サイズ不明 pane（width=0）はプレビューに「サイズ不明」表示（E1）', (tester) async {
      const unknown = MultiplexerPane(
        index: 1,
        id: 'w1:p1',
        left: 0,
        top: 0,
        width: 0,
        height: 0,
      );
      await openDialog(tester, panes: [unknown]);

      expect(find.text('1\nサイズ不明'), findsOneWidget);
      expect(find.text('概算(estimated)'), findsOneWidget);
    });

    testWidgets('Match Screen プリセットが表示され選択できる', (tester) async {
      final matchCols = FontCalculator.calculateMaxCols(
        screenWidth: 800,
        fontSize: 14,
        fontFamily: 'monospace',
      );
      final matchRows = FontCalculator.calculateMaxRows(
        screenHeight: 1400,
        fontSize: 14,
        fontFamily: 'monospace',
      );
      final harness = await openDialog(
        tester,
        panes: [p1],
        screenWidth: 800,
        screenHeight: 1400,
        fontSize: 14,
        fontFamily: 'monospace',
      );

      expect(
        find.text('Match Screen ($matchCols x $matchRows)'),
        findsOneWidget,
      );

      await tester.tap(find.text('Match Screen ($matchCols x $matchRows)'));
      await tester.pump();
      await tapResize(tester);

      expect(harness.result, isNotNull);
      expect(harness.result!.cols, matchCols);
      expect(harness.result!.rows, matchRows);
    });

    testWidgets('panes 空: プレビュー・警告なしで Cols/Rows 入力のみ', (tester) async {
      await openDialog(tester, panes: const []);

      expect(find.text('概算(estimated)'), findsNothing);
      expect(find.text('Other pane sizes may also change.'), findsNothing);
      expect(find.text('Cols'), findsOneWidget);
      expect(find.text('Rows'), findsOneWidget);
      expect(find.text('80x24 (Standard)'), findsOneWidget);
    });

    testWidgets('Cancel で null を返して閉じる', (tester) async {
      final harness = await openDialog(tester, panes: [p1, p2]);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(harness.result, isNull);
      expect(find.text('Resize Pane'), findsNothing);
    });
  });
}
