import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('Q-02: herdr pane セレクタの Split（分割プレビュー経由）配線', () {
    testWidgets('分割プレビューのアクティブ pane タップ → Split Right で '
        'pane split コマンドを発行する', (tester) async {
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

      // 分割プレビュー内タップ（アクティブ pane・矩形 80x24 → インライン分割
      // モード）→ Split Right ボタン。
      await tester.tap(
        find.byKey(const ValueKey('terminal-pane-layout-w1:p1')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('terminal-split-right-w1:p1')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        client.execCommands.any(
          (c) => c == 'herdr pane split w1:p1 --direction right',
        ),
        isTrue,
        reason: '分割プレビューは PaneWriter.splitPane（herdr pane split）を発行すること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets(
      '分割プレビュー内の Split Down は herdr pane split --direction down を発行する',
      (tester) async {
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

        await tester.tap(
          find.byKey(const ValueKey('terminal-pane-layout-w1:p1')),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('terminal-split-down-w1:p1')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          client.execCommands.any(
            (c) => c == 'herdr pane split w1:p1 --direction down',
          ),
          isTrue,
          reason: 'Split Down は vertical 方向の pane split を発行すること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  });
  group('N-T: herdr pane セレクタの分割プレビュー（新規）', () {
    testWidgets('ヘッダーは Resize のみ + ローディング中 0.7 固定（N-T1）', (tester) async {
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

      // ローディング中: Split / Rename / Zoom のツールチップは存在しない。
      expect(find.byTooltip('Split Pane'), findsNothing);
      expect(find.byTooltip('Rename Pane'), findsNothing);
      expect(find.byTooltip('Zoom Pane'), findsNothing);
      // topExpected: true → ローディング中から maxHeight が画面高の 0.7 固定
      // （top 表示後と同じ高さでジャンプしない）。
      final sheetBox = tester.widget<ConstrainedBox>(
        find
            .ancestor(
              of: find.text('Select Pane'),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      final screenHeight = MediaQuery.sizeOf(
        tester.element(find.text('Select Pane')),
      ).height;
      expect(
        sheetBox.constraints.maxHeight,
        closeTo(screenHeight * 0.7, 0.001),
        reason: 'topExpected によりローディング中から maxHeight 0.7 固定',
      );

      await tester.pump(const Duration(milliseconds: 300));

      // データロード後: ヘッダーは Resize のみ。
      expect(find.byTooltip('Resize Pane'), findsOneWidget);
      expect(find.byTooltip('Split Pane'), findsNothing);
      expect(find.byTooltip('Rename Pane'), findsNothing);
      expect(find.byTooltip('Zoom Pane'), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('herdr ビジュアライザ表示 + アクティブ pane は現在表示中の pane（N-T2）', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
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

      // 分割プレビューが表示される。
      expect(
        find.byKey(const ValueKey('terminal-pane-layout-w1:p1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('terminal-pane-layout-w1:p2')),
        findsOneWidget,
      );

      // アクティブ pane のハイライトは _targetSource?.currentPaneId（= w1:p1、
      // 現在表示中の pane）基準。非アクティブ pane は黒半透明のまま。
      Color? paneColorOf(String paneId) {
        final container = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(ValueKey('terminal-pane-layout-$paneId')),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (container.decoration as BoxDecoration).color;
      }

      expect(paneColorOf('w1:p1'), isNot(Colors.black45));
      expect(paneColorOf('w1:p2'), Colors.black45);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('非アクティブ pane タップで対象 pane に切替えてシートが閉じる（N-T3）', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(
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
      expect(find.text('Select Pane'), findsOneWidget);

      // 非アクティブ pane（w1:p2）をタップ → 選択（onPaneSelected）に倒れる。
      await tester.tap(
        find.byKey(const ValueKey('terminal-pane-layout-w1:p2')),
      );
      await tester.pump();
      // シートの閉じアニメーション + 表示切替を進める。
      await tester.pump(const Duration(milliseconds: 400));

      // シートが閉じ、表示対象が w1:p2 に切替わる。
      expect(find.text('Select Pane'), findsNothing);
      expect(find.text('Pane 2'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('オフセット付き rect（x:26 / y:1）でもプレビューが 0 起点で欠けない（N-T4）', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrResizedSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final paneFinder = find.byKey(
        const ValueKey('terminal-pane-layout-w1:p1'),
      );
      expect(paneFinder, findsOneWidget);

      // min 正規化: minLeft（26）/ minTop（1）が差し引かれ 0 起点で配置される。
      final positioned = tester.widget<Positioned>(
        find.ancestor(of: paneFinder, matching: find.byType(Positioned)).first,
      );
      expect(
        positioned.left,
        lessThan(1.0),
        reason: 'minLeft（26）が差し引かれ 0 起点で描画されること',
      );
      expect(
        positioned.top,
        lessThan(1.0),
        reason: 'minTop（1）が差し引かれ 0 起点で描画されること',
      );

      // プレビュー右端/下端がプレビュー領域内に収まる（欠けない）。
      final stackRect = tester.getRect(
        find.ancestor(of: paneFinder, matching: find.byType(Stack)).first,
      );
      final paneRect = tester.getRect(paneFinder);
      expect(paneRect.right, lessThanOrEqualTo(stackRect.right + 0.5));
      expect(paneRect.bottom, lessThanOrEqualTo(stackRect.bottom + 0.5));

      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
