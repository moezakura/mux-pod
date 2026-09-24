import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('TerminalScreen herdr スクロールバック (bug4)', () {
    testWidgets('深い履歴の要求行数はユーザー設定 scrollbackLines と整合する', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        settings: const AppSettings(keepScreenOn: false, scrollbackLines: 2000),
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'content\n',
          'herdr pane read w1:p1 --source recent --lines 2000 --raw':
              'deep-0\ndeep-1\n',
        },
        settle: false,
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      state.loadHistoryForScrollForTesting();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        client.execCommands.any(
          (c) =>
              c.contains('herdr pane read w1:p1 --source recent') &&
              c.contains('--lines 2000'),
        ),
        isTrue,
        reason: 'バグ4: herdr の深い履歴は scrollbackLines（2000）で要求されること',
      );
    });

    testWidgets('scrollbackLines が最小値未満でもクランプされ、最大値超過でもクランプされる', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        // 20000 超過（例: 99999）→ クランプして 20000 で要求される。
        settings: const AppSettings(
          keepScreenOn: false,
          scrollbackLines: 99999,
        ),
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'content\n',
          'herdr pane read w1:p1 --source recent --lines 20000 --raw':
              'deep-0\ndeep-1\n',
        },
        settle: false,
      );

      final dynamic state = tester.state(find.byType(TerminalScreen));
      state.loadHistoryForScrollForTesting();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        client.execCommands.any(
          (c) =>
              c.contains('herdr pane read w1:p1 --source recent') &&
              c.contains('--lines 20000'),
        ),
        isTrue,
        reason: 'バグ4: scrollbackLines は [200, 20000] にクランプされること',
      );
    });

    testWidgets('初回コンテンツ受信時は末尾アライン（scrollToBottom相当）で最下部に到達する', (tester) async {
      // herdr は cursorX/cursorY=0 固定のため、scrollToCaret の中央寄せだと
      // 最下部より手前で停止する。backendKind==herdr では末尾アラインに分岐し、
      // 履歴がある状態でも maxScrollExtent（最下部）へ到達することを検証する。
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        settings: const AppSettings(
          keepScreenOn: false,
          adjustMode: 'manual',
          fontSize: 14.0,
        ),
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          // 履歴 + pane（24行）でビューポートを超えるだけの行数を返す
          'herdr pane read': List.generate(300, (i) => 'content-$i').join('\n'),
        },
        settle: false,
      );

      // 初回コンテンツ受信（_applyUpdate → _scrollToCaret → 100ms遅延）
      await tester.pump(const Duration(milliseconds: 100));
      // scrollToBottom の animateTo(300ms) を消化
      await tester.pump(const Duration(milliseconds: 500));

      final scrollable = find.descendant(
        of: find.byType(AnsiTextView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason: 'コンテンツがビューポートを超えスクロール可能な状態であること',
      );
      expect(
        position.pixels,
        closeTo(position.maxScrollExtent, 1.0),
        reason: 'herdr（cursorY=0固定）では末尾アラインで最下部に到達すること',
      );
    });
  });
}
