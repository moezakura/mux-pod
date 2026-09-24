import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('TerminalScreen herdr (backend flow / display)', () {
    testWidgets(
      'breadcrumb shows workspace label, tab segment, and pane segment '
      '(A9 display state / T11)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        // workspace ラベル + tab セグメント + pane セグメント（T11）。
        // tabId はスナップショット解決済みの実値（w1:t1）を保持するため、
        // 2 セグメント pane ID（w1:p1）でも tab セグメント "1"（実ラベル）が
        // 表示される（L-1 / M-4）。
        expect(find.text('lab-ws1'), findsOneWidget);
        expect(find.text('1'), findsOneWidget); // tab セグメント（実ラベル '1'）
        expect(find.byIcon(Icons.tab), findsOneWidget);
        expect(find.text('Pane 1'), findsOneWidget);

        // T4: セッション（workspace）セグメントのタップで共通シートの
        // workspace 一覧（第 1 段）が開く
        await tester.tap(find.text('lab-ws1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Session'), findsOneWidget);
      },
    );
    testWidgets(
      'T4: tab segment tap opens the selector at the tab stage (stage 2)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        // tab セグメント（snapshot 解決済みラベル '1'）タップ → 現在 workspace の
        // tab 一覧（第 2 段）が開く
        await tester.tap(find.text('1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Window'), findsOneWidget);
        // 現在 workspace（lab-ws1）の tab が表示される（index: name）
        expect(find.text('1: 1'), findsOneWidget);
      },
    );
    testWidgets(
      'T4: pane segment tap opens the selector at the pane stage (stage 3)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        // pane セグメント（'Pane 1'）タップ → 現在 tab の pane 一覧（第 3 段）
        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Pane'), findsOneWidget);
        // A10: pane 表示名は cwd（/tmp）優先
        expect(find.text('/tmp'), findsOneWidget);
      },
    );
    testWidgets(
      'M-4: tab segment shows the snapshot-resolved tab label (not a number)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrLabeledTabSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        // 旧実装（数字抽出）なら '1' になるが、M-4 では実ラベル 'editor' を表示する
        expect(find.text('editor'), findsOneWidget);
        expect(find.text('1'), findsNothing);
      },
    );
  });
}
