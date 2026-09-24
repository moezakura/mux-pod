import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/widgets/multiplexer_tiles.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('TerminalScreen herdr (backend flow / display)', () {
    testWidgets(
      'T10 selectors (workspace → tab → pane) each close on selection and '
      'switch the displayed pane via the single commit without mutation',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrTwoWorkspaceSnapshotFixture,
            'herdr pane read w1:p1': 'content from p1\n',
            'herdr pane read w2:p1': 'content from p2\n',
          },
          settle: false,
        );

        // 初期表示は w1:p1（snapshot から解決）
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p1')),
          isTrue,
        );

        // workspace セレクタ（Select Session 相当）: セッションセグメントタップ
        await tester.tap(find.text('lab-ws1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Session'), findsOneWidget);
        expect(find.text('lab-ws2'), findsOneWidget);

        // workspace 選択 → シート即閉じ + 切替コミット（workspace のフォーカス pane）
        await tester.tap(find.byKey(const ValueKey('mux-sel-session-lab-ws2')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Session'), findsNothing);
        expect(find.text('Select Window'), findsNothing);

        // A8 監視: 切替イベントがリングバッファに記録される
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('switch target -> w2:p1')),
          isTrue,
          reason: 'workspace 選択が切替コミット（_switchHerdrTarget）を呼ぶこと',
        );

        // ポーリングが新しいターゲットを読む
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w2:p1')),
          isTrue,
          reason: '切替後に新しい pane ID がポーリング対象になること',
        );
        expect(find.textContaining('content from p2'), findsWidgets);
        // T11: ブレッドクラムの workspace ラベルが選択結果へ更新される
        expect(
          find.text('lab-ws2'),
          findsOneWidget,
          reason: 'パンくずの workspace 名が選択結果のラベルに更新されること',
        );

        // tab セレクタ（Select Window 相当）: 現在 workspace（lab-ws2）の tab 一覧
        await tester.tap(find.text('1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Window'), findsOneWidget);
        expect(find.text('1: 1'), findsOneWidget);

        // tab 選択 → シート即閉じ（切替先は同一ターゲットのため no-op）
        await tester.tap(find.byKey(const ValueKey('mux-sel-window-w2:t1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Window'), findsNothing);
        expect(find.text('Select Pane'), findsNothing);

        // pane セレクタ（Select Pane 相当）: 現在 tab の pane 一覧。
        // A10: pane 表示名は currentPath（cwd=/var）を優先する
        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Pane'), findsOneWidget);
        expect(find.text('/var'), findsOneWidget);

        // pane 選択 → シート即閉じ + 切替コミット
        await tester.tap(find.byKey(const ValueKey('mux-sel-pane-w2:p1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Pane'), findsNothing);

        // セレクタ経由の切替でも mutation コマンドは一切発行されない
        expect(
          client.execCommands.any((c) => c.contains('select-pane')),
          isFalse,
        );
        expect(
          client.execCommands.any((c) => c.contains('herdr pane focus')),
          isFalse,
        );
      },
    );
    testWidgets('T10 selectors highlight the current display target as initial '
        'emphasis (workspace/tab/pane)', (tester) async {
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

      // workspace セレクタ（Select Session 相当）: 現在ターゲット（w1:p1）が
      // 属する workspace が active 表示（ActiveListTile のアクティブ時は title が
      // 太字になる）
      await tester.tap(find.text('lab-ws1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Session'), findsOneWidget);
      final wsTitle = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('mux-sel-session-lab-ws1')),
          matching: find.text('lab-ws1'),
        ),
      );
      expect(wsTitle.style?.fontWeight, FontWeight.bold);

      // シートを閉じて tab セレクタを開く: 現在 tab（w1:t1）が active 表示
      await tester.tapAt(const Offset(500, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Session'), findsNothing);

      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Window'), findsOneWidget);
      final tabTitle = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('mux-sel-window-w1:t1')),
          matching: find.text('1: 1'),
        ),
      );
      expect(tabTitle.style?.fontWeight, FontWeight.bold);

      // シートを閉じて pane セレクタを開く: 現在 pane（w1:p1、cwd=/tmp）が
      // active 表示。pane 表示名は cwd（A10）を優先する
      await tester.tapAt(const Offset(500, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Window'), findsNothing);

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Pane'), findsOneWidget);
      expect(find.text('/tmp'), findsOneWidget);
      final paneTitle = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('mux-sel-pane-w1:p1')),
          matching: find.text('/tmp'),
        ),
      );
      expect(paneTitle.style?.fontWeight, FontWeight.bold);

      // セレクタを閉じる
      await tester.tapAt(const Offset(500, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Pane'), findsNothing);
    });
    testWidgets(
      'H-1 same-label workspaces (tmp w3/w4 pattern) highlight only the '
      'sessionId-matched workspace in the session selector',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'tmp',
          sessionId: 'w2',
          execOutputs: {
            'herdr api snapshot': kHerdrSameLabelSnapshotFixture,
            'herdr pane read': 'content from w2\n',
          },
          settle: false,
        );

        // 現在ターゲットは sessionId=w2 の workspace（w2:p1）に解決される。
        // workspace セレクタ（Select Session 相当）を開く。
        await tester.tap(find.text('tmp'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Session'), findsOneWidget);

        // 同名ラベル "tmp" の workspace が w1 / w2 の 2 つ表示される。
        final tiles = tester
            .widgetList<MultiplexerSessionTile>(
              find.byType(MultiplexerSessionTile),
            )
            .toList();
        expect(tiles, hasLength(2));
        expect(tiles.map((t) => t.session.name).toSet(), {'tmp'});

        // ハイライトは ID を一義的な基準とする:
        // sessionId 一致（w2）の workspace だけが active になり、
        // 同名ラベルでも ID 不一致（w1）は active にならない。
        final activeById = {for (final t in tiles) t.session.id: t.isActive};
        expect(
          activeById['w2'],
          isTrue,
          reason: '現在の workspace ID（w2）だけがハイライトされること',
        );
        expect(
          activeById['w1'],
          isFalse,
          reason: '同名ラベル "tmp" でも ID 不一致（w1）はハイライトされないこと',
        );
      },
    );
    testWidgets('M2 regression: tmux では pane indicator が表示される', (tester) async {
      // tmux backend: kFullTreeOutput の mysession/shell は
      // pane %0/%1 の 2 ペインを持つため indicator が描画される。
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      expect(paneIndicatorPainter(), findsWidgets);
    });
  });
  group('TerminalScreen herdr セレクタ再タップガード (bug3)', () {
    testWidgets('セレクタ開手中の再タップは無視され、シートが多重起動しない', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoWorkspaceSnapshotFixture,
          'herdr pane read w1:p1': 'content from p1\n',
          'herdr pane read w2:p1': 'content from p2\n',
        },
        settle: false,
      );

      // workspace セグメント（lab-ws1）を連続タップ。
      // 1回目のタップで _herdrSelectorOpening=true になり、2回目以降は
      // ガードで無視される（シートが多重起動しない・バグ3）。
      await tester.tap(find.text('lab-ws1'));
      await tester.tap(find.text('lab-ws1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // シートは1つだけ表示される（多重起動しない・バグ3）。
      expect(find.text('Select Session'), findsOneWidget);

      // シートを閉じるとフラグがリセットされ、再度開ける。
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('lab-ws1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Select Session'),
        findsOneWidget,
        reason: 'シートを閉じた後は再度セレクタを開けること',
      );
    });
  });
}
